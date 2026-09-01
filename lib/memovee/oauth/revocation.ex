defmodule Memovee.OAuth.Revocation do
  @moduledoc "Client-authenticated, non-oracular OAuth credential revocation."

  alias Memovee.Accounts.{Actor, Token}
  alias Memovee.Accounts.Actor.Manager, as: ActorManager
  alias Memovee.Accounts.Token.Manager, as: TokenManager
  alias Memovee.OAuth
  alias Memovee.OAuth.Access.Manager, as: AccessManager
  alias Memovee.OAuth.{Client, Event, KeyProvider, RateLimiter}
  alias Memovee.OAuth.Client.Authentication
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.OAuth.Tama.MCP
  alias Memovee.Repo
  alias TamaOAuth.{Error, JWKS, JWT, TokenRequest}

  @access_token_clock_skew_seconds 30

  def revoke(params, authorization_headers \\ [], remote_ip \\ nil)

  def revoke(params, authorization_headers, remote_ip) when is_map(params) do
    with :ok <- MCP.require_configured(),
         :ok <- rate_limit(remote_ip, params["client_id"]),
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
         {:ok, claims} <- verify_revocable_access_token(raw_token, jwks),
         {:ok, token_id} <- Ecto.UUID.cast(claims["jti"]),
         {grant_id, actor_id} <- AccessManager.grant_identity_for_access(token_id, claims) do
      {:ok, {grant_id, actor_id}}
    else
      _error -> refresh_grant_identity(raw_token)
    end
  end

  defp verify_revocable_access_token(raw_token, jwks) do
    algorithm = OAuth.config(:signing_algorithm)

    with {:ok, %{"alg" => ^algorithm, "kid" => kid}} <-
           JWT.peek_access_token_header(raw_token, algorithms: [algorithm]),
         {:ok, key} <- JWKS.select(jwks, kid, algorithm, algorithms: [algorithm]),
         {:ok, claims} <- JWT.verify_signature(raw_token, key, algorithm),
         :ok <- validate_revocable_access_claims(claims) do
      {:ok, claims}
    else
      _error -> {:error, :invalid_access_token}
    end
  end

  defp validate_revocable_access_claims(claims) do
    now = DateTime.to_unix(OAuth.now())
    issued_at = claims["iat"]
    expires_at = claims["exp"]
    not_before = Map.get(claims, "nbf", issued_at)

    valid? =
      claims["iss"] == OAuth.issuer() and
        Enum.all?(~w(sub aud client_id scope jti), &(is_binary(claims[&1]) and claims[&1] != "")) and
        match?({:ok, _subject}, Ecto.UUID.cast(claims["sub"])) and
        valid_revocation_times?(issued_at, expires_at, not_before, now)

    if valid?, do: :ok, else: {:error, :invalid_access_token}
  end

  defp valid_revocation_times?(issued_at, expires_at, not_before, now) do
    Enum.all?([issued_at, expires_at, not_before, now], &is_integer/1) and
      issued_at <= now + @access_token_clock_skew_seconds and
      not_before <= now + @access_token_clock_skew_seconds and expires_at > issued_at
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
    Authentication.authenticate(
      method,
      %{
        client_id: client_id,
        metadata: metadata,
        params: params,
        authorization_headers: authorization_headers
      },
      "/auth/revocations"
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
