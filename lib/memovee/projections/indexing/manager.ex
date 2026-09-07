defmodule Memovee.Projections.Indexing.Manager do
  @moduledoc "Persists pending indexing work. Worker execution belongs to the indexing integration."
  import Ecto.Query
  import Ecto.Changeset
  alias Ecto.Multi
  alias Memovee.Accounts.Actor
  alias Memovee.Memory.{Candidate, Post, Tag, Tagging}
  alias Memovee.Projections.Indexing
  alias Memovee.Repo
  alias Memovee.Workers.MemoryProjection

  def create_pending(%Post{} = post) do
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
      "profile" => "memory-v1",
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
    |> change()
    |> unique_constraint([:post_id, :revision, :profile])
    |> then(fn changeset ->
      Multi.new()
      |> Multi.insert(:projection, changeset)
      |> Oban.insert(:job, fn %{projection: projection} ->
        MemoryProjection.new(%{projection_id: projection.id})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{projection: projection}} -> {:ok, projection}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end)
  end

  def fingerprint(value), do: value |> canonical_json() |> Candidate.hash()

  def canonical_json(value) when is_map(value) do
    "{" <>
      (value
       |> Enum.map(fn {key, child} -> {to_string(key), child} end)
       |> Enum.sort_by(&elem(&1, 0))
       |> Enum.map_join(",", fn {key, child} ->
         Jason.encode!(key) <> ":" <> canonical_json(child)
       end)) <> "}"
  end

  def canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  def canonical_json(value), do: Jason.encode!(value)

  def bump(%Post{} = post) do
    with {:ok, updated} <-
           post |> change(memory_revision: post.memory_revision + 1) |> Repo.update(),
         {:ok, _job} <- create_pending(updated) do
      {:ok, updated}
    end
  end

  # #13 supplies Oban-driven execution and callback fencing; declarations must not allow premature readiness.
  def worker_transition(_changes), do: {:error, %Eventful.Error{code: :worker_not_implemented}}

  def invalidate_transition({changeset, event_changeset}) do
    actor_id = get_assoc(event_changeset, :actor, :struct).id
    configured_id = Application.get_env(:memovee, :memory_tama_actor_id)

    if actor_id == configured_id and
         Repo.exists?(
           from actor in Actor,
             where: actor.id == ^actor_id and actor.current_state == "active"
         ) do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:event, event_changeset)
      |> Ecto.Multi.update(:resource, changeset, stale_error_field: :current_state)
      |> Repo.transaction()
      |> case do
        {:ok, %{event: event, resource: resource}} ->
          {:ok, %Eventful.Transition{event: event, resource: resource}}

        {:error, step, error, _} ->
          {:error, %Eventful.Error{code: step, message: error}}
      end
    else
      {:error, %Eventful.Error{code: :forbidden}}
    end
  end
end
