defmodule Memovee.OAuth.Authorization do
  @moduledoc "Authorization request, consent, and approval orchestration."

  alias Memovee.Accounts.{Actor, Scope}
  alias Memovee.Accounts.Actor.Manager, as: ActorManager
  alias Memovee.OAuth
  alias Memovee.OAuth.{Client, Event, RateLimiter}
  alias Memovee.OAuth.Code.Manager, as: CodeManager
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.OAuth.Request.Manager, as: RequestManager
  alias Memovee.OAuth.Tama.MCP
  alias Memovee.Repo
  alias TamaOAuth.{AuthorizationRequest, ClientMetadata, Crypto, Error}

  @authorization_response_query_keys ~w(code error error_description error_uri iss scope state)

  def start(params, remote_ip \\ nil) when is_map(params) do
    with :ok <- MCP.require_enabled(),
         :ok <- rate_limit(remote_ip),
         {:ok, request} <-
           AuthorizationRequest.validate(params,
             resource: MCP.resource(),
             supported_scopes: MCP.supported_scopes()
           ),
         {:ok, metadata} <- Client.fetch(request.client_id),
         true <- ClientMetadata.redirect_allowed?(request.redirect_uri, metadata),
         {handle, digest} <- opaque_credential(),
         {:ok, _persisted} <- RequestManager.create(request, metadata.metadata_digest, digest) do
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
    with {:ok, actor} <- ActorManager.get_active_user(actor.id),
         {:ok, request} <- RequestManager.get_pending(handle),
         :ok <- validate_current_policy(request),
         {:ok, metadata} <- Client.refresh(request.client_id),
         :ok <- validate_metadata(request, metadata) do
      {:ok,
       %{
         request: request,
         actor: actor,
         client_name: metadata.client_name,
         client_uri: metadata.client_uri,
         redirect_authority: redirect_authority(request.redirect_uri),
         loopback_redirect?: loopback_redirect?(request.redirect_uri),
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
      with {:ok, actor} <- ActorManager.get_active_user(actor_id, lock: :update),
           {:ok, request} <- RequestManager.get_pending(handle, lock: true),
           {:ok, request} <- RequestManager.transition(request, actor, "deny") do
        Event.emit(:authorization_denied, %{client_id: request.client_id, actor_id: actor.id})
        {:ok, redirect_uri(request, %{"error" => "access_denied"})}
      end
    end)
  end

  def deny(_scope, _handle), do: {:error, :invalid_consent}

  defp approve_transaction(actor_id, handle) do
    with {:ok, actor} <- ActorManager.get_active_user(actor_id, lock: :update),
         {:ok, request} <- RequestManager.get_pending(handle, lock: true),
         :ok <- validate_current_policy(request),
         {:ok, metadata} <- Client.refresh(request.client_id),
         :ok <- validate_metadata(request, metadata),
         {:ok, grant} <- GrantManager.resolve_for_approval(actor, request),
         {raw_code, code_digest} <- opaque_credential(),
         {:ok, _code} <-
           CodeManager.issue(grant, request, code_digest,
             refresh_token_allowed: "refresh_token" in metadata.grant_types
           ),
         {:ok, request} <- RequestManager.transition(request, actor, "approve") do
      Event.emit(:authorization_approved, %{
        client_id: request.client_id,
        grant_id: grant.id,
        actor_id: actor.id
      })

      {:ok, redirect_uri(request, %{"code" => raw_code})}
    end
  end

  defp validate_metadata(request, metadata) do
    valid? =
      Crypto.secure_compare(request.client_metadata_digest, metadata.metadata_digest) and
        ClientMetadata.redirect_allowed?(request.redirect_uri, metadata)

    if valid?, do: :ok, else: {:error, :client_metadata_changed}
  end

  defp validate_current_policy(request) do
    with true <- MCP.enabled?(),
         true <- request.resource == MCP.resource(),
         {:ok, scope} <- MCP.normalize_scope(request.scope),
         true <- scope == request.scope do
      :ok
    else
      _error -> {:error, :authorization_policy_changed}
    end
  end

  defp redirect_uri(request, params) do
    uri = URI.parse(request.redirect_uri)

    response_query =
      params
      |> Map.put("state", request.state)
      |> Map.put("iss", OAuth.issuer())
      |> URI.encode_query()

    query = merge_redirect_query(uri.query, response_query)

    %{uri | query: query} |> URI.to_string()
  end

  defp merge_redirect_query(query, response_query) when query in [nil, ""], do: response_query

  defp merge_redirect_query(query, response_query) do
    preserved_query =
      query
      |> String.split("&", trim: false)
      |> Enum.reject(&authorization_response_pair?/1)
      |> Enum.join("&")

    if preserved_query == "", do: response_query, else: preserved_query <> "&" <> response_query
  end

  defp authorization_response_pair?(pair) do
    key = pair |> String.split("=", parts: 2) |> List.first()
    URI.decode_www_form(key) in @authorization_response_query_keys
  rescue
    ArgumentError -> false
  end

  defp redirect_authority(redirect_uri) do
    uri = URI.parse(redirect_uri)
    host = if String.contains?(uri.host, ":"), do: "[#{uri.host}]", else: uri.host
    if uri.port, do: "#{host}:#{uri.port}", else: host
  end

  defp loopback_redirect?(redirect_uri) do
    redirect_uri
    |> URI.parse()
    |> Map.get(:host)
    |> TamaOAuth.URI.loopback_host?()
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
