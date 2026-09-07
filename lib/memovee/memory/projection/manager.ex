defmodule Memovee.Memory.Projection.Manager do
  @moduledoc """
  Creates, retrieves, and synchronizes Tama projections.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi
  alias Memovee.Memory.{Post, Projection, Scope}
  alias Memovee.Repo

  def list_for_post(%Scope{} = scope, %Post{} = post) do
    with {:ok, post} <- Post.Manager.get(scope, post.id) do
      {:ok,
       Repo.all(
         from projection in Projection,
           where: projection.post_id == ^post.id,
           order_by: [desc: projection.id]
       )}
    end
  end

  def list_pending(%Scope{} = scope) do
    with {:ok, scope} <- Scope.refresh(scope) do
      {:ok,
       Repo.all(
         from projection in Projection,
           join: post in Post,
           on: post.id == projection.post_id,
           where:
             post.owner_actor_id == ^scope.owner.id and
               (projection.current_state == "pending" or
                  (projection.current_state == "synced" and
                     fragment("? IS DISTINCT FROM ?", projection.synced_body_hash, post.body_hash))),
           order_by: projection.id
       )}
    end
  end

  def get(%Scope{} = scope, id) do
    case scoped_projection(scope, id) do
      {:ok, _scope, projection} -> {:ok, projection}
      error -> error
    end
  end

  def create(%Scope{} = scope, %Post{} = post, attrs) do
    Repo.transaction(fn ->
      with {:ok, scope} <- Scope.refresh(scope),
           {:ok, post} <- Post.Manager.get(scope, post.id),
           {:ok, projection} <-
             %Projection{}
             |> Projection.changeset(put_default_identifier(attrs, post.id))
             |> put_change(:post_id, post.id)
             |> Repo.insert() do
        projection
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def change(%Projection{} = projection, attrs \\ %{}) do
    Projection.changeset(projection, attrs)
  end

  def sync(%Scope{} = scope, %Projection{} = projection) do
    perform_transition(scope, projection, "sync")
  end

  def complete(%Scope{} = scope, %Projection{} = projection, tama_entity_id, body_hash) do
    perform_transition(scope, projection, "complete",
      parameters: %{tama_entity_id: tama_entity_id, body_hash: body_hash}
    )
  end

  def fail(%Scope{} = scope, %Projection{} = projection, reason) when is_atom(reason) do
    perform_transition(scope, projection, "fail", parameters: %{reason: Atom.to_string(reason)})
  end

  def retry(%Scope{} = scope, %Projection{} = projection) do
    perform_transition(scope, projection, "retry")
  end

  def invalidate(%Scope{} = scope, %Projection{} = projection) do
    perform_transition(scope, projection, "invalidate")
  end

  def invalidate_for_post(%Scope{} = scope, %Post{} = post) do
    with {:ok, scope} <- Scope.refresh(scope),
         %Post{} = post <- Repo.get_by(Post, id: post.id, owner_actor_id: scope.owner.id) do
      invalidate_projections(scope, post)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp invalidate_projections(scope, post) do
    Projection
    |> where(
      [projection],
      projection.post_id == ^post.id and projection.current_state != "pending"
    )
    |> order_by([projection], asc: projection.id)
    |> Repo.all()
    |> Enum.reduce_while({:ok, []}, fn projection, {:ok, transitions} ->
      case invalidate(scope, projection) do
        {:ok, transition} -> {:cont, {:ok, [transition | transitions]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp perform_transition(%Scope{} = scope, %Projection{} = projection, event, opts \\ []) do
    with {:ok, scope, projection} <- scoped_projection(scope, projection.id) do
      Eventful.Transit.perform(projection, scope.actor, event, opts)
    end
  end

  defp scoped_projection(scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id), {:ok, scope} <- Scope.refresh(scope) do
      case Repo.one(
             from projection in Projection,
               join: post in Post,
               on: post.id == projection.post_id,
               where: projection.id == ^id and post.owner_actor_id == ^scope.owner.id
           ) do
        nil -> {:error, :not_found}
        projection -> {:ok, scope, projection}
      end
    else
      :error -> {:error, :invalid_id}
      error -> error
    end
  end

  def complete_transition({projection_changeset, event_changeset}) do
    metadata = get_embed(event_changeset, :metadata, :struct)

    with {:ok, tama_entity_id} <- cast_uuid(parameter(metadata, :tama_entity_id)),
         {:ok, body_hash} <- cast_body_hash(parameter(metadata, :body_hash)) do
      projection_changeset =
        projection_changeset
        |> put_change(:tama_entity_id, tama_entity_id)
        |> put_change(:synced_body_hash, body_hash)
        |> unique_constraint(:tama_entity_id,
          name: :memory_projections_tama_entity_id_index
        )
        |> check_constraint(:synced_body_hash,
          name: :memory_projections_synced_body_hash_format
        )

      event_changeset = refresh_event_changes(event_changeset, projection_changeset)

      Multi.new()
      |> Multi.run(:authorization, fn _, _ ->
        authorize_transition(projection_changeset, event_changeset)
      end)
      |> Multi.run(:body_hash, fn repo, %{authorization: post} ->
        verify_body_hash(repo, post.id, body_hash)
      end)
      |> Multi.insert(:event, event_changeset)
      |> Multi.update(:resource, projection_changeset, stale_error_field: :current_state)
      |> Repo.transaction(timeout: 15_000)
      |> normalize_transaction()
    else
      {:error, reason} ->
        {:error, %Eventful.Error{code: :invalid_transition_parameters, message: reason}}
    end
  end

  def transition({changeset, event_changeset}) do
    Multi.new()
    |> Multi.run(:authorization, fn _, _ -> authorize_transition(changeset, event_changeset) end)
    |> Multi.insert(:event, event_changeset)
    |> Multi.update(:resource, changeset, stale_error_field: :current_state)
    |> Repo.transaction()
    |> normalize_transaction()
  end

  defp authorize_transition(changeset, event_changeset) do
    actor = get_assoc(event_changeset, :actor, :struct)
    projection = Repo.get(Projection, changeset.data.id)

    with %Projection{} <- projection,
         %Post{} = post <- Repo.get(Post, projection.post_id),
         {:ok, scope} <- Scope.resolve(actor, transition_context(actor, post)),
         {:ok, scope} <- Scope.refresh(scope),
         true <- post.owner_actor_id == scope.owner.id do
      {:ok, post}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp transition_context(actor, post) do
    if actor.id == Application.get_env(:memovee, :memory_tama_actor_id),
      do: %{"context" => %{"actor_id" => post.owner_actor_id, "origin_identifier" => post.id}},
      else: %{}
  end

  defp parameter(%Eventful.Metadata{parameters: parameters}, key) do
    Map.get(parameters, key) || Map.get(parameters, Atom.to_string(key))
  end

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_tama_entity_id}
    end
  end

  defp cast_body_hash(value) when is_binary(value) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, value),
      do: {:ok, value},
      else: {:error, :invalid_body_hash}
  end

  defp cast_body_hash(_value), do: {:error, :invalid_body_hash}

  defp verify_body_hash(repo, post_id, expected_body_hash) do
    current_body_hash =
      Post
      |> where([post], post.id == ^post_id)
      |> select([post], post.body_hash)
      |> lock("FOR SHARE")
      |> repo.one()

    case current_body_hash do
      ^expected_body_hash -> {:ok, expected_body_hash}
      nil -> {:error, :post_not_found}
      _other -> {:error, :stale_body}
    end
  end

  defp refresh_event_changes(event_changeset, projection_changeset) do
    metadata = get_embed(event_changeset, :metadata, :struct)

    recorded_changes =
      Eventful.Metadata.build(
        projection_changeset.data,
        projection_changeset.changes,
        %{}
      ).changes

    put_embed(event_changeset, :metadata, %{metadata | changes: recorded_changes})
  end

  defp normalize_transaction({:ok, transaction}) do
    {:ok,
     %Eventful.Transition{
       event: transaction.event,
       resource: transaction.resource
     }}
  end

  defp normalize_transaction({:error, :body_hash, reason, data}) do
    {:error, %Eventful.Error{code: reason, data: data}}
  end

  defp normalize_transaction({:error, code, message, data}) do
    {:error, %Eventful.Error{code: code, message: message, data: data}}
  end

  defp put_default_identifier(attrs, identifier) do
    cond do
      Map.has_key?(attrs, :identifier) or Map.has_key?(attrs, "identifier") -> attrs
      Enum.any?(Map.keys(attrs), &is_binary/1) -> Map.put(attrs, "identifier", identifier)
      true -> Map.put(attrs, :identifier, identifier)
    end
  end
end
