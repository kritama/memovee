defmodule Memovee.OAuth.Token.Exchange do
  @moduledoc "Atomic authorization-code and rotating-refresh exchanges."

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Token}
  alias Memovee.OAuth

  alias Memovee.OAuth.{
    Access,
    Client,
    Code,
    Event,
    Grant,
    KeyProvider,
    RateLimiter
  }

  alias Memovee.OAuth.Actor, as: OAuthActor
  alias Memovee.OAuth.Client.ReplayStore
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias Memovee.Repo
  alias TamaOAuth.{ClientAuthentication, Error, PKCE, RefreshToken, Scope, TokenRequest}

  def exchange(params, authorization_headers \\ [], remote_ip \\ nil)

  def exchange(params, authorization_headers, remote_ip) when is_map(params) do
    with :ok <- rate_limit(remote_ip, params["client_id"]),
         {:ok, request} <-
           TokenRequest.parse(params, authorization_headers: authorization_headers),
         {:ok, metadata} <- Client.fetch(request.client_id),
         {:ok, _client_id} <- authenticate(request, metadata, authorization_headers) do
      perform_exchange(request)
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, :temporarily_unavailable} ->
        {:error, Error.new(:temporarily_unavailable, stage: :client_metadata)}

      _error ->
        {:error, Error.new(:invalid_client, stage: :client_authentication)}
    end
  end

  def exchange(_params, _headers, _remote_ip),
    do: {:error, Error.new(:invalid_request, stage: :token_request)}

  defp perform_exchange(%TokenRequest{grant_type: :authorization_code} = request) do
    Repo.transact(fn -> exchange_code(request) end)
  end

  defp perform_exchange(%TokenRequest{grant_type: :refresh_token} = request) do
    case Repo.transact(fn -> exchange_refresh(request) end) do
      {:ok, {:replay, %Error{} = error}} -> {:error, error}
      result -> result
    end
  end

  defp exchange_code(request) do
    params = request.params
    now = OAuth.now()
    digest = TamaOAuth.Crypto.digest(params["code"])

    with {:ok, {grant_id, actor_id}} <- code_grant_identity(digest),
         {:ok, %Actor{} = actor} <- active_actor(actor_id),
         {:ok, %Grant{} = grant} <- GrantManager.lock(grant_id),
         {:ok, %Code{} = code} <- lock_code(digest),
         :ok <- validate_code(request, grant, code, actor, now),
         {:ok, _code} <- code |> Ecto.Changeset.change(consumed_at: now) |> Repo.update(),
         :ok <- revoke_active_refresh_tokens(grant.id, now),
         {:ok, response} <- issue_tokens(grant, actor, nil, 0, now) do
      Event.emit(:authorization_code_exchanged, %{
        client_id: grant.oauth_client_id,
        grant_id: grant.id,
        actor_id: actor.id
      })

      {:ok, response}
    else
      {:error, %Error{} = error} -> {:error, error}
      _error -> {:error, Error.new(:invalid_grant, stage: :authorization_code)}
    end
  end

  defp exchange_refresh(request) do
    params = request.params
    now = OAuth.now()
    digest = Token.oauth_token_digest(params["refresh_token"])

    case refresh_grant_identity(digest) do
      {:ok, {grant_id, actor_id}} ->
        exchange_refresh_for_grant(request, digest, grant_id, actor_id, now)

      _error ->
        {:error, Error.new(:invalid_grant, stage: :refresh_token)}
    end
  end

  defp exchange_refresh_for_grant(request, digest, grant_id, actor_id, now) do
    with {:ok, %Actor{} = actor} <- active_actor(actor_id),
         {:ok, %Grant{} = grant} <- GrantManager.lock(grant_id),
         {:ok, %Token{} = token, %Access{} = access} <- lock_refresh(digest),
         :ok <- validate_refresh_binding(request, grant, token, access, actor),
         {:ok, decision} <- evaluate_refresh(token, access, now),
         :ok <- rotate_refresh(token, access, now),
         {:ok, response} <-
           issue_tokens(grant, actor, decision.family_id, decision.next_generation, now) do
      Event.emit(:refresh_succeeded, %{
        client_id: grant.oauth_client_id,
        grant_id: grant.id,
        actor_id: actor.id
      })

      {:ok, response}
    else
      {:replay, family_id} -> revoke_replayed_family(grant_id, family_id, now)
      {:error, %Error{} = error} -> {:error, error}
      _error -> {:error, Error.new(:invalid_grant, stage: :refresh_token)}
    end
  end

  defp authenticate(request, metadata, authorization_headers) do
    ClientAuthentication.authenticate(
      request.authentication_method,
      %{
        client_id: request.client_id,
        metadata: metadata,
        params: request.params,
        authorization_headers: authorization_headers
      },
      algorithms: OAuth.config(:token_endpoint_auth_signing_algorithms),
      token_endpoint: OAuth.endpoint("/auth/tokens"),
      clock_skew_seconds: OAuth.config(:client_assertion_clock_skew_seconds),
      key_resolver: &Client.key/3,
      claim_replay: &ReplayStore.claim/2
    )
  end

  defp validate_code(request, grant, code, actor, now) do
    valid? =
      active_authorization?(grant, actor) and code_bound?(request, grant, code) and
        usable_code?(code, now) and
        PKCE.verify(request.params["code_verifier"], code.code_challenge)

    if valid?, do: :ok, else: {:error, Error.new(:invalid_grant, stage: :code_binding)}
  end

  defp active_authorization?(grant, actor) do
    grant.current_state == "active" and actor.current_state == "active"
  end

  defp code_bound?(request, grant, code) do
    code.oauth_grant_id == grant.id and grant.oauth_client_id == request.client_id and
      code.redirect_uri == request.params["redirect_uri"] and code.resource == grant.resource and
      code.scope == grant.scope
  end

  defp usable_code?(code, now) do
    is_nil(code.consumed_at) and DateTime.compare(code.expires_at, now) == :gt
  end

  defp validate_refresh_binding(request, grant, token, access, actor) do
    requested_scope = request.params["scope"] || grant.scope

    valid? =
      access.oauth_grant_id == grant.id and token.actor_id == actor.id and
        grant.current_state == "active" and grant.oauth_client_id == request.client_id and
        grant.resource == OAuth.resource() and
        match?({:ok, ^requested_scope}, Scope.normalize(requested_scope, [grant.scope]))

    if valid?, do: :ok, else: {:error, Error.new(:invalid_grant, stage: :refresh_binding)}
  end

  defp evaluate_refresh(token, access, now) do
    status =
      cond do
        not is_nil(access.rotated_at) -> :rotated
        not is_nil(token.revoked_at) -> :revoked
        true -> :active
      end

    RefreshToken.evaluate(
      %RefreshToken.State{
        id: token.id,
        family_id: access.family_id,
        generation: access.generation,
        status: status,
        issued_at: token.inserted_at,
        expires_at: token.expires_at,
        last_used_at: token.authenticated_at
      },
      now,
      idle_lifetime_seconds: OAuth.config(:refresh_token_idle_lifetime_seconds)
    )
  end

  defp issue_tokens(grant, actor, family_id, generation, now) do
    access_expires_at = DateTime.add(now, OAuth.config(:access_token_lifetime_seconds), :second)
    refresh_expires_at = DateTime.add(now, OAuth.config(:refresh_token_lifetime_seconds), :second)

    {refresh_token, refresh_reference} =
      Token.build_oauth_refresh_token(actor, refresh_expires_at)

    with {:ok, refresh_reference} <- Repo.insert(refresh_reference),
         family_id = family_id || refresh_reference.id,
         {:ok, _refresh_access} <-
           refresh_reference
           |> Access.changeset(grant, %{family_id: family_id, generation: generation})
           |> Repo.insert(),
         access_reference = Token.build_oauth_access_reference(actor, access_expires_at),
         {:ok, access_reference} <- Repo.insert(access_reference),
         {:ok, _access} <-
           access_reference
           |> Access.changeset(grant, %{family_id: family_id, generation: generation})
           |> Repo.insert(),
         {:ok, signing} <- KeyProvider.signing_key(),
         {:ok, access_token, _claims} <-
           mint_access_token(grant, actor, access_reference, signing, now),
         {:ok, _grant} <-
           grant
           |> Ecto.Changeset.change(last_used_at: now)
           |> Repo.update() do
      {:ok,
       %{
         "access_token" => access_token,
         "token_type" => "Bearer",
         "expires_in" => OAuth.config(:access_token_lifetime_seconds),
         "refresh_token" => refresh_token,
         "scope" => grant.scope
       }}
    end
  end

  defp mint_access_token(grant, actor, access_reference, signing, now) do
    TamaOAuth.JWT.mint_access_token(
      %{
        "iss" => OAuth.issuer(),
        "sub" => actor.id,
        "aud" => grant.resource,
        "client_id" => grant.oauth_client_id,
        "scope" => grant.scope,
        "jti" => access_reference.id
      },
      signing.key,
      algorithm: signing.algorithm,
      kid: signing.kid,
      now: DateTime.to_unix(now),
      ttl: OAuth.config(:access_token_lifetime_seconds)
    )
  end

  defp code_grant_identity(digest) do
    case Repo.one(
           from code in Code,
             join: grant in Grant,
             on: grant.id == code.oauth_grant_id,
             where: code.code_digest == ^digest,
             select: {grant.id, grant.actor_id}
         ) do
      nil -> {:error, :invalid_grant}
      identity -> {:ok, identity}
    end
  end

  defp lock_code(digest) do
    Code
    |> where([code], code.code_digest == ^digest)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %Code{} = code -> {:ok, code}
      nil -> {:error, :invalid_grant}
    end
  end

  defp refresh_grant_identity(digest) do
    query =
      from token in Token,
        join: access in Access,
        on: access.actor_token_id == token.id,
        join: grant in Grant,
        on: grant.id == access.oauth_grant_id,
        where: token.context == "oauth_refresh" and token.token == ^digest,
        select: {grant.id, grant.actor_id}

    case Repo.one(query) do
      nil -> {:error, :invalid_grant}
      identity -> {:ok, identity}
    end
  end

  defp lock_refresh(digest) do
    query =
      from token in Token,
        join: access in Access,
        on: access.actor_token_id == token.id,
        where: token.context == "oauth_refresh" and token.token == ^digest,
        select: {token, access},
        lock: "FOR UPDATE"

    case Repo.one(query) do
      {%Token{} = token, %Access{} = access} -> {:ok, token, access}
      nil -> {:error, :invalid_grant}
    end
  end

  defp active_actor(actor_id) do
    query =
      from actor in Actor,
        where: actor.id == ^actor_id and actor.type == :user and actor.current_state == "active",
        lock: "FOR SHARE"

    case Repo.one(query) do
      %Actor{} = actor -> {:ok, actor}
      nil -> {:error, :inactive_actor}
    end
  end

  defp revoke_active_refresh_tokens(grant_id, now) do
    token_ids =
      from(access in Access,
        join: token in Token,
        on: token.id == access.actor_token_id,
        where:
          access.oauth_grant_id == ^grant_id and token.context == "oauth_refresh" and
            is_nil(token.revoked_at),
        select: token.id
      )

    _result =
      Repo.update_all(from(token in Token, where: token.id in subquery(token_ids)),
        set: [revoked_at: now]
      )

    :ok
  end

  defp rotate_refresh(token, access, now) do
    with {:ok, _token} <-
           token |> Ecto.Changeset.change(revoked_at: now, authenticated_at: now) |> Repo.update(),
         {:ok, _access} <- access |> Ecto.Changeset.change(rotated_at: now) |> Repo.update() do
      :ok
    end
  end

  defp revoke_replayed_family(grant_id, family_id, now) do
    token_ids =
      from(access in Access,
        where: access.family_id == ^family_id,
        select: access.actor_token_id
      )

    _result =
      Repo.update_all(from(token in Token, where: token.id in subquery(token_ids)),
        set: [revoked_at: now]
      )

    with {:ok, grant} <- GrantManager.lock(grant_id),
         {:ok, actor} <- OAuthActor.get() do
      _transition = GrantManager.revoke(grant, actor)
    end

    Event.emit(:refresh_replayed, %{grant_id: grant_id, reason: :family_replay})
    {:ok, {:replay, Error.new(:invalid_grant, stage: :refresh_replay)}}
  end

  defp rate_limit(remote_ip, client_id) do
    case RateLimiter.token(
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
