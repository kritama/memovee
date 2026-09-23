defmodule Memovee.Projections.Indexing.Manager do
  @moduledoc "Persists pending indexing work. Worker execution belongs to the indexing integration."
  import Ecto.Query
  import Ecto.Changeset
  alias Ecto.Multi
  alias Jason.OrderedObject
  alias Memovee.Memory.{Post, Scope, Tag, Tagging}
  alias Memovee.Projections.Indexing
  alias Memovee.Projections.Indexing.Worker
  alias Memovee.Repo

  def get_for_post(%Scope{} = scope, %Post{} = post) do
    authorized_post(scope, post, fn current ->
      case Repo.get_by(Indexing,
             post_id: current.id,
             revision: current.memory_revision,
             indexing_version: 1
           ) do
        nil -> {:error, :not_found}
        projection -> {:ok, projection}
      end
    end)
  end

  def create(%Scope{} = scope, %Post{} = post) do
    authorized_post(scope, post, &create_for_post/1)
  end

  defp create_for_post(post) do
    tags =
      Repo.all(
        from tag in Tag,
          join: tagging in Tagging,
          on: tagging.tag_id == tag.id,
          where: tagging.post_id == ^post.id and tag.owner_actor_id == ^post.owner_actor_id,
          order_by: tag.id
      )

    value = %{
      "post_id" => post.id,
      "revision" => post.memory_revision,
      "title" => post.title,
      "body" => post.body,
      "metadata" => post.metadata,
      "indexing_version" => 1,
      "tags" =>
        Enum.map(
          tags,
          &Map.take(Map.from_struct(&1), [:id, :namespace, :key, :name, :description])
        )
    }

    %Indexing{
      owner_actor_id: post.owner_actor_id,
      post_id: post.id,
      revision: post.memory_revision,
      fingerprint: fingerprint(value)
    }
    |> Indexing.changeset()
    |> then(fn changeset ->
      Multi.new()
      |> Multi.insert(:projection, changeset)
      |> Oban.insert(:job, fn %{projection: projection} ->
        Worker.new(%{projection_id: projection.id})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{projection: projection}} -> {:ok, projection}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end)
  end

  def fingerprint(value) do
    :crypto.hash(:sha256, canonical_json(value)) |> Base.encode16(case: :lower)
  end

  def canonical_json(value), do: value |> order_keys() |> Jason.encode!()

  def bump(%Scope{} = scope, %Post{} = post) do
    authorized_post(scope, post, fn current ->
      with {:ok, updated} <-
             current |> change(memory_revision: current.memory_revision + 1) |> Repo.update(),
           {:ok, _job} <- create_for_post(updated) do
        {:ok, updated}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp authorized_post(scope, post, operation) do
    Repo.transaction(fn ->
      scope =
        case Scope.refresh(scope) do
          {:ok, refreshed} -> refreshed
          {:error, reason} -> Repo.rollback(reason)
        end

      current =
        Repo.one(
          from row in Post,
            where: row.id == ^post.id and row.owner_actor_id == ^scope.owner.id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:not_found)

      case operation.(current) do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # #13 supplies Oban-driven execution and callback fencing; declarations must not allow premature readiness.
  def worker_transition(_changes), do: {:error, %Eventful.Error{code: :worker_not_implemented}}

  def invalidate_transition({changeset, event_changeset}) do
    actor = get_assoc(event_changeset, :actor, :struct)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:authorization, fn repo, _ ->
      authorize_invalidation(repo, actor, changeset.data)
    end)
    |> Ecto.Multi.run(:revision, fn repo, _ -> superseded_revision(repo, changeset.data) end)
    |> Ecto.Multi.insert(:event, event_changeset)
    |> Ecto.Multi.update(:resource, changeset, stale_error_field: :current_state)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event, resource: resource}} ->
        {:ok, %Eventful.Transition{event: event, resource: resource}}

      {:error, :authorization, :forbidden, _} ->
        {:error, %Eventful.Error{code: :forbidden}}

      {:error, step, error, _} ->
        {:error, %Eventful.Error{code: step, message: error}}
    end
  end

  defp authorize_invalidation(repo, actor, projection) do
    with %Indexing{} = current <- repo.get(Indexing, projection.id),
         %Post{} = post <- repo.get(Post, current.post_id),
         {:ok, scope} <-
           Scope.resolve(actor, %{
             "context" => %{"actor_id" => post.owner_actor_id, "origin_identifier" => post.id}
           }),
         {:ok, scope} <- Scope.refresh(scope),
         true <- scope.owner.id == post.owner_actor_id do
      {:ok, post}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp superseded_revision(repo, projection) do
    projection = repo.get!(Indexing, projection.id)

    post =
      repo.one!(
        from post in Post,
          where: post.id == ^projection.post_id,
          lock: "FOR UPDATE"
      )

    if projection.revision < post.memory_revision,
      do: {:ok, post.memory_revision},
      else: {:error, :current_revision}
  end

  defp order_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, child} -> {to_string(key), order_keys(child)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> OrderedObject.new()
  end

  defp order_keys(value) when is_list(value), do: Enum.map(value, &order_keys/1)
  defp order_keys(value), do: value
end
