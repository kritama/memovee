defmodule Memovee.OAuth.Authorization do
  @moduledoc "Authorization request, consent, and approval orchestration."

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Scope}
  alias Memovee.OAuth
  alias Memovee.OAuth.{Client, Code, Event, Grant, RateLimiter, Request}
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.OAuth.Tama.MCP
  alias Memovee.Repo
  alias TamaOAuth.{AuthorizationRequest, ClientMetadata, Crypto, Error}

  def start(params, remote_ip \\ nil) when is_map(params) do
    with :ok <- rate_limit(remote_ip),
         {:ok, request} <-
           AuthorizationRequest.validate(params,
             resource: MCP.resource(),
             supported_scopes: MCP.supported_scopes()
           ),
         {:ok, metadata} <- Client.fetch(request.client_id),
         true <- ClientMetadata.redirect_allowed?(request.redirect_uri, metadata),
         {handle, digest} <- opaque_credential(),
         {:ok, _persisted} <- persist_request(request, metadata, digest) do
      Event.emit(:authorization_started, %{client_id: request.client_id})
      {:ok, handle}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, :rate_limited} ->
        {:error, Error.new(:temporarily_unavailable, stage: :rate_limit)}

      {:error, :temporarily_unavailable} ->
        {:error, Error.new(:temporarily_unavailable, stage: :client_metadata)}

      _error ->
        Event.emit(:authorization_failed, %{reason: :invalid_request})
        {:error, Error.new(:invalid_request, stage: :authorization)}
    end
  end

  def consent(%Scope{actor: %Actor{} = actor}, handle) do
    with {:ok, actor} <- active_actor(actor.id),
         {:ok, request} <- load_pending(handle),
         {:ok, metadata} <- Client.refresh(request.client_id),
         :ok <- validate_metadata(request, metadata) do
      {:ok,
       %{
         request: request,
         actor: actor,
         client_name: metadata.client_name,
         client_uri: metadata.client_uri,
         redirect_authority: redirect_authority(request.redirect_uri),
         verified_client_metadata?: metadata.verified_client_metadata?
       }}
    else
      _error -> {:error, :invalid_consent}
    end
  end

  def consent(_scope, _handle), do: {:error, :invalid_consent}

  def approve(%Scope{actor: %Actor{id: actor_id}}, handle) do
    Repo.transact(fn -> approve_transaction(actor_id, handle) end)
  end

  def approve(_scope, _handle), do: {:error, :invalid_consent}

  def deny(%Scope{actor: %Actor{id: actor_id}}, handle) do
    Repo.transact(fn ->
      with {:ok, actor} <- active_actor(actor_id, lock: true),
           {:ok, request} <- load_pending(handle, lock: true),
           {:ok, request} <- transition_request(request, actor, "deny") do
        Event.emit(:authorization_denied, %{client_id: request.client_id, actor_id: actor.id})
        {:ok, redirect_uri(request, %{"error" => "access_denied"})}
      end
    end)
  end

  def deny(_scope, _handle), do: {:error, :invalid_consent}

  defp approve_transaction(actor_id, handle) do
    with {:ok, actor} <- active_actor(actor_id, lock: true),
         {:ok, request} <- load_pending(handle, lock: true),
         {:ok, metadata} <- Client.refresh(request.client_id),
         :ok <- validate_metadata(request, metadata),
         {:ok, grant} <- GrantManager.resolve_for_approval(actor, request),
         {raw_code, code_digest} <- opaque_credential(),
         {:ok, _code} <- create_code(grant, request, code_digest),
         {:ok, request} <- transition_request(request, actor, "approve") do
      Event.emit(:authorization_approved, %{
        client_id: request.client_id,
        grant_id: grant.id,
        actor_id: actor.id
      })

      {:ok, redirect_uri(request, %{"code" => raw_code})}
    end
  end

  defp persist_request(request, metadata, digest) do
    expires_at =
      OAuth.now()
      |> DateTime.add(OAuth.config(:authorization_request_lifetime_seconds), :second)

    %Request{}
    |> Request.changeset(%{
      handle_digest: digest,
      client_id: request.client_id,
      client_metadata_digest: metadata.metadata_digest,
      redirect_uri: request.redirect_uri,
      resource: request.resource,
      scope: request.scope,
      state: request.state,
      code_challenge: request.code_challenge,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  defp create_code(%Grant{} = grant, %Request{} = request, digest) do
    expires_at =
      OAuth.now()
      |> DateTime.add(OAuth.config(:authorization_code_lifetime_seconds), :second)

    %Code{oauth_grant_id: grant.id}
    |> Code.changeset(%{
      code_digest: digest,
      redirect_uri: request.redirect_uri,
      resource: request.resource,
      scope: request.scope,
      code_challenge: request.code_challenge,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  defp load_pending(handle, opts \\ [])

  defp load_pending(handle, opts) when is_binary(handle) do
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

  defp load_pending(_handle, _opts), do: {:error, :invalid_request_handle}

  defp active_actor(id, opts \\ []) do
    query =
      from actor in Actor,
        where: actor.id == ^id and actor.type == :user and actor.current_state == "active"

    query = if opts[:lock], do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      %Actor{} = actor -> {:ok, actor}
      nil -> {:error, :inactive_actor}
    end
  end

  defp validate_metadata(request, metadata) do
    valid? =
      Crypto.secure_compare(request.client_metadata_digest, metadata.metadata_digest) and
        ClientMetadata.redirect_allowed?(request.redirect_uri, metadata)

    if valid?, do: :ok, else: {:error, :client_metadata_changed}
  end

  defp transition_request(request, actor, event_name) do
    case Eventful.Transit.perform(request, actor, event_name) do
      {:ok, %{resource: transitioned}} -> {:ok, transitioned}
      error -> error
    end
  end

  defp redirect_uri(request, params) do
    uri = URI.parse(request.redirect_uri)

    query =
      uri.query
      |> then(fn query -> if query, do: URI.decode_query(query), else: %{} end)
      |> Map.merge(params)
      |> Map.put("state", request.state)
      |> Map.put("iss", OAuth.issuer())
      |> URI.encode_query()

    %{uri | query: query} |> URI.to_string()
  end

  defp redirect_authority(redirect_uri) do
    uri = URI.parse(redirect_uri)
    host = if String.contains?(uri.host, ":"), do: "[#{uri.host}]", else: uri.host
    if uri.port, do: "#{host}:#{uri.port}", else: host
  end

  defp opaque_credential do
    value = Crypto.opaque_token()
    {value, Crypto.digest(value)}
  end

  defp rate_limit(remote_ip) do
    case RateLimiter.authorization(remote_ip || {:internal, self()}) do
      :ok -> :ok
      {:error, _retry_after} -> {:error, :rate_limited}
    end
  end
end
