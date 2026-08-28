defmodule Memovee.OAuth.Revocation do
  @moduledoc "Client-authenticated, non-oracular OAuth credential revocation."

  alias Memovee.Accounts.{Actor, Token}
  alias Memovee.Accounts.Actor.Manager, as: ActorManager
  alias Memovee.Accounts.Token.Manager, as: TokenManager
  alias Memovee.OAuth
  alias Memovee.OAuth.Access.Manager, as: AccessManager
  alias Memovee.OAuth.{Client, Event, KeyProvider, RateLimiter}
  alias Memovee.OAuth.Client.ReplayStore
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.Repo
  alias TamaOAuth.{ClientAuthentication, Error, TokenRequest}

  def revoke(params, authorization_headers \\ [], remote_ip \\ nil)

  def revoke(params, authorization_headers, remote_ip) when is_map(params) do
    with :ok <- rate_limit(remote_ip, params["client_id"]),
         {:ok, request} <- TamaOAuth.Revocation.parse(params),
         {:ok, method} <- TokenRequest.detect_authentication(params, authorization_headers),
         {:ok, metadata} <- Client.fetch(request.client_id),
         {:ok, _client_id} <-
           authenticate(method, request.client_id, params, metadata, authorization_headers) do
      revoke_if_owned(request.token, request.client_id)
    else
      {:error, %Error{} = error} -> {:error, error}
      _error -> {:error, Error.new(:invalid_client, stage: :client_authentication)}
    end
  end

  def revoke(_params, _headers, _remote_ip),
    do: {:error, Error.new(:invalid_request, stage: :revocation_request)}

  defp revoke_if_owned(raw_token, client_id) do
    case token_grant_identity(raw_token) do
      {:ok, {grant_id, actor_id}} -> revoke_grant(grant_id, actor_id, client_id)
      :unknown -> {:ok, TamaOAuth.Revocation.response()}
    end
  end

  defp revoke_grant(grant_id, actor_id, client_id) do
    Repo.transact(fn ->
      with {:ok, %Actor{} = actor} <- ActorManager.get(actor_id, lock: :update),
           {:ok, grant} <- GrantManager.lock(grant_id),
           true <- grant.actor_id == actor.id and grant.oauth_client_id == client_id,
           {:ok, grant} <- GrantManager.revoke(grant, actor),
           :ok <- revoke_grant_tokens(grant.id) do
        Event.emit(:revoked, %{client_id: client_id, grant_id: grant.id, actor_id: actor.id})
        {:ok, TamaOAuth.Revocation.response()}
      else
        _error -> {:ok, TamaOAuth.Revocation.response()}
      end
    end)
  end

  defp token_grant_identity(raw_token) do
    with {:ok, jwks} <- KeyProvider.public_jwks(),
         {:ok, claims} <-
           TamaOAuth.JWT.verify_access_token(raw_token, jwks,
             issuer: OAuth.issuer(),
             audience: OAuth.resource(),
             scopes: ["mcp.message"],
             algorithms: [OAuth.config(:signing_algorithm)]
           ),
         {:ok, token_id} <- Ecto.UUID.cast(claims["jti"]),
         {grant_id, actor_id} <- AccessManager.grant_identity_for_token(token_id, "oauth_access") do
      {:ok, {grant_id, actor_id}}
    else
      _error -> refresh_grant_identity(raw_token)
    end
  end

  defp refresh_grant_identity(raw_token) do
    digest = Token.oauth_token_digest(raw_token)

    case AccessManager.refresh_grant_identity(digest) do
      {:ok, identity} -> {:ok, identity}
      {:error, :invalid_grant} -> :unknown
    end
  end

  defp revoke_grant_tokens(grant_id) do
    grant_id
    |> AccessManager.grant_token_ids_query()
    |> TokenManager.revoke_oauth(OAuth.now())
  end

  defp authenticate(method, client_id, params, metadata, authorization_headers) do
    ClientAuthentication.authenticate(
      method,
      %{
        client_id: client_id,
        metadata: metadata,
        params: params,
        authorization_headers: authorization_headers
      },
      algorithms: OAuth.config(:token_endpoint_auth_signing_algorithms),
      token_endpoint: OAuth.endpoint("/auth/revocations"),
      clock_skew_seconds: OAuth.config(:client_assertion_clock_skew_seconds),
      key_resolver: &Client.key/3,
      claim_replay: &ReplayStore.claim/2
    )
  end

  defp rate_limit(remote_ip, client_id) do
    case RateLimiter.revocation(
           remote_ip || {:internal, self()},
           client_id || :unknown
         ) do
      :ok ->
        :ok

      {:error, _retry_after} ->
        {:error, Error.new(:temporarily_unavailable, stage: :rate_limit)}
    end
  end
end
