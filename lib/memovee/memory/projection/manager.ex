defmodule Memovee.Memory.Projection.Manager do
  @moduledoc """
  Creates, retrieves, and synchronizes Tama projections.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi
  alias Memovee.Accounts.Actor
  alias Memovee.Memory.{Post, Projection}
  alias Memovee.Repo

  def list_for_post(%Post{} = post) do
    Projection
    |> where([projection], projection.post_id == ^post.id)
    |> order_by([projection], desc: projection.id)
    |> Repo.all()
  end

  def list_pending do
    Projection
    |> join(:inner, [projection], post in Post, on: post.id == projection.post_id)
    |> where(
      [projection, post],
      projection.current_state == "pending" or
        (projection.current_state == "synced" and
           fragment("? IS DISTINCT FROM ?", projection.synced_body_hash, post.body_hash))
    )
    |> order_by([projection], asc: projection.id)
    |> Repo.all()
  end

  def get!(id), do: Repo.get!(Projection, id)

  def create(%Post{} = post, attrs) do
    attrs = put_default_identifier(attrs, post.id)

    %Projection{}
    |> Projection.changeset(attrs)
    |> put_change(:post_id, post.id)
    |> Repo.insert()
  end

  def change(%Projection{} = projection, attrs \\ %{}) do
    Projection.changeset(projection, attrs)
  end

  def sync(%Actor{} = actor, %Projection{} = projection) do
    Eventful.Transit.perform(projection, actor, "sync")
  end

  def complete(%Actor{} = actor, %Projection{} = projection, tama_entity_id, body_hash) do
    Eventful.Transit.perform(projection, actor, "complete",
      parameters: %{tama_entity_id: tama_entity_id, body_hash: body_hash}
    )
  end

  def fail(%Actor{} = actor, %Projection{} = projection, reason) when is_atom(reason) do
    Eventful.Transit.perform(projection, actor, "fail",
      parameters: %{reason: Atom.to_string(reason)}
    )
  end

  def retry(%Actor{} = actor, %Projection{} = projection) do
    Eventful.Transit.perform(projection, actor, "retry")
  end

  def invalidate(%Actor{} = actor, %Projection{} = projection) do
    Eventful.Transit.perform(projection, actor, "invalidate")
  end

  def invalidate_for_post(%Actor{} = actor, %Post{} = post) do
    Projection
    |> where(
      [projection],
      projection.post_id == ^post.id and projection.current_state != "pending"
    )
    |> order_by([projection], asc: projection.id)
    |> Repo.all()
    |> Enum.reduce_while({:ok, []}, fn projection, {:ok, transitions} ->
      case invalidate(actor, projection) do
        {:ok, transition} -> {:cont, {:ok, [transition | transitions]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
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
      |> Multi.run(:body_hash, fn repo, _changes ->
        verify_body_hash(repo, projection_changeset.data.post_id, body_hash)
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
