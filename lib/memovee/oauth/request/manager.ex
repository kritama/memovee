defmodule Memovee.OAuth.Request.Manager do
  @moduledoc "Owns OAuth authorization-request persistence, locking, transitions, and retention."

  import Ecto.Query

  alias Memovee.OAuth
  alias Memovee.OAuth.Actor
  alias Memovee.OAuth.Request
  alias Memovee.OAuth.Request.Event
  alias Memovee.Repo
  alias TamaOAuth.Crypto

  @terminal_states ~w(approved denied expired)

  def create(request, metadata_digest, handle_digest) do
    expires_at =
      OAuth.now()
      |> DateTime.add(OAuth.config(:authorization_request_lifetime_seconds), :second)

    %Request{}
    |> Request.changeset(%{
      handle_digest: handle_digest,
      client_id: request.client_id,
      client_metadata_digest: metadata_digest,
      redirect_uri: request.redirect_uri,
      resource: request.resource,
      scope: request.scope,
      state: request.state,
      code_challenge: request.code_challenge,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  def get_pending(handle, opts \\ [])

  def get_pending(handle, opts) when is_binary(handle) do
    now = OAuth.now()
    digest = Crypto.digest(handle)

    query =
      from request in Request,
        where:
          request.handle_digest == ^digest and request.current_state == "pending" and
            request.expires_at > ^now

    query = if opts[:lock], do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      %Request{} = request -> {:ok, request}
      nil -> {:error, :invalid_request_handle}
    end
  end

  def get_pending(_handle, _opts), do: {:error, :invalid_request_handle}

  def transition(%Request{} = request, actor, event_name) do
    case Eventful.Transit.perform(request, actor, event_name) do
      {:ok, %{resource: transitioned}} -> {:ok, transitioned}
      error -> error
    end
  end

  def cleanup(now) do
    batch_size = OAuth.config(:authorization_request_cleanup_batch_size)
    cutoff = DateTime.add(now, -OAuth.config(:authorization_request_retention_seconds), :second)

    with {:ok, expired_count} <- expire_pending(now, batch_size),
         {:ok, deleted_count} <- delete_terminal(cutoff, batch_size) do
      {:ok, expired_count == batch_size or deleted_count == batch_size}
    end
  end

  def active_client_ids_query(now) do
    from request in Request,
      where: request.current_state == "pending" and request.expires_at > ^now,
      distinct: true,
      select: %{client_id: request.client_id}
  end

  def active_for_client?(client_id, now) do
    Repo.exists?(
      from(request in Request,
        where:
          request.client_id == ^client_id and request.current_state == "pending" and
            request.expires_at > ^now
      )
    )
  end

  defp expire_pending(now, batch_size) do
    with {:ok, actor} <- Actor.get() do
      requests =
        Request
        |> where([request], request.current_state == "pending" and request.expires_at <= ^now)
        |> order_by([request], asc: request.expires_at, asc: request.id)
        |> limit(^batch_size)
        |> lock("FOR UPDATE")
        |> Repo.all()

      Enum.reduce_while(requests, {:ok, 0}, &expire_request(&1, &2, actor))
    end
  end

  defp expire_request(request, {:ok, count}, actor) do
    case transition(request, actor, "expire") do
      {:ok, _request} -> {:cont, {:ok, count + 1}}
      error -> {:halt, error}
    end
  end

  defp delete_terminal(cutoff, batch_size) do
    request_ids =
      Request
      |> where(
        [request],
        request.current_state in @terminal_states and request.expires_at <= ^cutoff
      )
      |> order_by([request], asc: request.expires_at, asc: request.id)
      |> limit(^batch_size)
      |> lock("FOR UPDATE")
      |> select([request], request.id)
      |> Repo.all()

    Repo.delete_all(from event in Event, where: event.oauth_request_id in ^request_ids)

    {deleted_count, _requests} =
      Repo.delete_all(from request in Request, where: request.id in ^request_ids)

    {:ok, deleted_count}
  end
end
