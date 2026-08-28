defmodule Memovee.OAuth.Introspection do
  @moduledoc "Authenticated, non-oracular access-token introspection."

  alias Memovee.Accounts.{Actor, Token}
  alias Memovee.OAuth
  alias Memovee.OAuth.{Access, Cache, Grant, KeyProvider, RateLimiter}
  alias Memovee.OAuth.Access.Manager, as: AccessManager
  alias Memovee.OAuth.Client.ReplayStore
  alias Memovee.OAuth.Grant.Manager, as: GrantManager
  alias TamaOAuth.{ClientAuthentication, ClientMetadata, Error, TokenRequest}

  def introspect(params, credentials, remote_ip \\ nil) do
    with :ok <- rate_limit(remote_ip, params["client_id"] || credentials),
         :ok <- authenticate_resource_server(params, credentials),
         {:ok, raw_token} <- TamaOAuth.Introspection.parse_request(params) do
      active_or_inactive(raw_token)
    else
      {:error, %Error{} = error} -> {:error, error}
      _error -> {:error, Error.new(:invalid_client, stage: :introspection_authentication)}
    end
  end

  defp active_or_inactive(raw_token) do
    with {:ok, jwks} <- KeyProvider.public_jwks(),
         {:ok, claims} <-
           TamaOAuth.JWT.verify_access_token(raw_token, jwks,
             issuer: OAuth.issuer(),
             audience: OAuth.resource(),
             scopes: ["mcp.message"],
             algorithms: [OAuth.config(:signing_algorithm)]
           ),
         {:ok, token_id} <- Ecto.UUID.cast(claims["jti"]),
         {%Token{} = token, %Access{} = access, %Grant{} = grant, %Actor{} = actor} <-
           AccessManager.active_reference(token_id, OAuth.now()),
         true <- valid_binding?(claims, token, access, grant, actor),
         {:ok, response} <- TamaOAuth.Introspection.active(claims, grant.id),
         {:ok, _grant} <- GrantManager.touch_usage(grant, OAuth.now()) do
      {:ok, response}
    else
      _error -> {:ok, TamaOAuth.Introspection.inactive()}
    end
  end

  defp valid_binding?(claims, token, access, grant, actor) do
    token.actor_id == actor.id and access.oauth_grant_id == grant.id and
      claims["sub"] == actor.id and claims["client_id"] == grant.oauth_client_id and
      claims["aud"] == grant.resource and claims["scope"] == grant.scope and
      claims["jti"] == token.id
  end

  defp authenticate_resource_server(params, credentials) do
    expected = OAuth.config(:introspection_bearer_token)

    case credentials do
      ["Bearer " <> presented] when is_binary(expected) and expected != "" ->
        if TamaOAuth.Crypto.secure_compare(presented, expected),
          do: :ok,
          else: {:error, :invalid_client}

      _headers ->
        authenticate_private_key_jwt(params, credentials)
    end
  end

  defp authenticate_private_key_jwt(params, credentials) do
    client_id = OAuth.config(:introspection_client_id)
    jwks_uri = OAuth.config(:introspection_jwks_uri, nil)

    metadata = %ClientMetadata{
      client_id: client_id,
      client_name: "Tama MCP App",
      client_uri: nil,
      redirect_uris: [OAuth.resource()],
      grant_types: ["client_credentials"],
      response_types: ["code"],
      token_endpoint_auth_methods_supported: ["private_key_jwt"],
      token_endpoint_auth_signing_algorithms:
        OAuth.config(:token_endpoint_auth_signing_algorithms),
      jwks_uri: jwks_uri
    }

    with true <- is_binary(jwks_uri),
         true <- params["client_id"] == client_id,
         {:ok, :private_key_jwt} <- TokenRequest.detect_authentication(params, credentials),
         {:ok, ^client_id} <-
           ClientAuthentication.authenticate(
             :private_key_jwt,
             %{
               client_id: client_id,
               metadata: metadata,
               params: params,
               authorization_headers: credentials
             },
             algorithms: OAuth.config(:token_endpoint_auth_signing_algorithms),
             token_endpoint: OAuth.endpoint("/auth/introspections"),
             clock_skew_seconds: OAuth.config(:client_assertion_clock_skew_seconds),
             key_resolver: &introspection_key/3,
             claim_replay: &ReplayStore.claim/2
           ) do
      :ok
    else
      _ -> {:error, :invalid_client}
    end
  end

  defp introspection_key(%ClientMetadata{jwks_uri: jwks_uri}, kid, algorithm) do
    cache_key = {:introspection_jwks, jwks_uri}

    with {:ok, jwks} <- cached_introspection_jwks(cache_key, jwks_uri),
         {:ok, key} <-
           TamaOAuth.JWKS.select(jwks, kid, algorithm, algorithms: [algorithm]) do
      {:ok, key}
    else
      {:error, :temporarily_unavailable} -> {:error, :temporarily_unavailable}
      _error -> {:error, :invalid_client}
    end
  end

  defp cached_introspection_jwks(cache_key, jwks_uri) do
    case Cache.get(cache_key) do
      nil ->
        with {:ok, jwks} <- TamaOAuth.JWKS.fetch(jwks_uri, jwks_uri) do
          :ok = Cache.put(cache_key, jwks, :timer.minutes(5))
          {:ok, jwks}
        end

      jwks ->
        {:ok, jwks}
    end
  end

  defp rate_limit(remote_ip, client_id) do
    case RateLimiter.introspection(remote_ip || {:internal, self()}, client_id) do
      :ok ->
        :ok

      {:error, _retry_after} ->
        {:error, Error.new(:temporarily_unavailable, stage: :rate_limit)}
    end
  end
end
