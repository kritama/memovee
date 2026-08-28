defmodule Memovee.OAuth.Revocation do
  @moduledoc "Client-authenticated, non-oracular OAuth credential revocation."

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Token}
  alias Memovee.OAuth
  alias Memovee.OAuth.{Access, Client, Event, KeyProvider, RateLimiter}
  alias Memovee.OAuth.Client.ReplayStore
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.Repo
  alias TamaOAuth.{ClientAuthentication, Error, TokenRequest}

  def revoke(params, authorization_headers \\ [])

  def revoke(params, authorization_headers) when is_map(params) do
    with :ok <- rate_limit(params["client_id"]),
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

  def revoke(_params, _headers),
    do: {:error, Error.new(:invalid_request, stage: :revocation_request)}

  defp revoke_if_owned(raw_token, client_id) do
    case token_grant_id(raw_token) do
      {:ok, grant_id} -> revoke_grant(grant_id, client_id)
      :unknown -> {:ok, TamaOAuth.Revocation.response()}
    end
  end

  defp revoke_grant(grant_id, client_id) do
    Repo.transact(fn ->
      with {:ok, grant} <- GrantManager.lock(grant_id),
           true <- grant.oauth_client_id == client_id,
           %Actor{} = actor <- Repo.get(Actor, grant.actor_id),
           {:ok, grant} <- GrantManager.revoke(grant, actor),
           :ok <- revoke_grant_tokens(grant.id) do
        Event.emit(:revoked, %{client_id: client_id, grant_id: grant.id, actor_id: actor.id})
        {:ok, TamaOAuth.Revocation.response()}
      else
        _error -> {:ok, TamaOAuth.Revocation.response()}
      end
    end)
  end

  defp token_grant_id(raw_token) do
    with {:ok, jwks} <- KeyProvider.public_jwks(),
         {:ok, claims} <-
           TamaOAuth.JWT.verify_access_token(raw_token, jwks,
             issuer: OAuth.issuer(),
             audience: OAuth.resource(),
             scopes: ["mcp.message"],
             algorithms: [OAuth.config(:signing_algorithm)]
           ),
         {:ok, token_id} <- Ecto.UUID.cast(claims["jti"]),
         grant_id when is_binary(grant_id) <- grant_id_for_token(token_id, "oauth_access") do
      {:ok, grant_id}
    else
      _error -> refresh_grant_id(raw_token)
    end
  end

  defp refresh_grant_id(raw_token) do
    digest = Token.oauth_token_digest(raw_token)

    case grant_id_for_digest(digest) do
      grant_id when is_binary(grant_id) -> {:ok, grant_id}
      nil -> :unknown
    end
  end

  defp grant_id_for_token(token_id, context) do
    Repo.one(
      from token in Token,
        join: access in Access,
        on: access.actor_token_id == token.id,
        where: token.id == ^token_id and token.context == ^context,
        select: access.oauth_grant_id
    )
  end

  defp grant_id_for_digest(digest) do
    Repo.one(
      from token in Token,
        join: access in Access,
        on: access.actor_token_id == token.id,
        where: token.token == ^digest and token.context == "oauth_refresh",
        select: access.oauth_grant_id
    )
  end

  defp revoke_grant_tokens(grant_id) do
    now = OAuth.now()

    token_ids =
      from(access in Access,
        where: access.oauth_grant_id == ^grant_id,
        select: access.actor_token_id
      )

    _result =
      Repo.update_all(
        from(token in Token,
          where: token.id in subquery(token_ids) and is_nil(token.revoked_at)
        ),
        set: [revoked_at: now]
      )

    :ok
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

  defp rate_limit(client_id) do
    case RateLimiter.check(:revocation, client_id || :unknown) do
      :ok ->
        :ok

      {:error, _retry_after} ->
        {:error, Error.new(:temporarily_unavailable, stage: :rate_limit)}
    end
  end
end
