defmodule Memovee.OAuthFixtures do
  @moduledoc false

  alias Memovee.Cache
  alias Memovee.OAuth

  @introspection_kid "tama-test-introspection-rs256-1"

  def client_id, do: "http://127.0.0.1/client.json"
  def redirect_uri, do: "http://127.0.0.1/callback"
  def verifier, do: String.duplicate("v", 43)

  def authorization_params(overrides \\ %{}) do
    {:ok, challenge} = TamaOAuth.PKCE.challenge(verifier())

    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => client_id(),
        "redirect_uri" => redirect_uri(),
        "resource" => OAuth.resource(),
        "scope" => "mcp.message",
        "state" => "opaque-client-state",
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      },
      overrides
    )
  end

  def authorize(scope) do
    {:ok, handle} = OAuth.start_authorization(authorization_params())
    {:ok, redirect_uri} = OAuth.approve(scope, handle)
    query = redirect_uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    %{handle: handle, code: Map.fetch!(query, "code"), redirect_uri: redirect_uri}
  end

  def exchange_code(code) do
    OAuth.exchange(%{
      "grant_type" => "authorization_code",
      "client_id" => client_id(),
      "code" => code,
      "redirect_uri" => redirect_uri(),
      "code_verifier" => verifier()
    })
  end

  def introspect_token(token) do
    {params, credentials} = introspection_request(token)
    OAuth.introspect(params, credentials)
  end

  def introspection_request(token) do
    client_id = OAuth.config(:introspection_client_id)
    jwks_uri = OAuth.config(:introspection_jwks_uri)
    endpoint = OAuth.endpoint("/auth/introspections")

    signing_key = Application.fetch_env!(:memovee, :test_tama_introspection_signing_key)

    {:ok, public_jwks} = TamaOAuth.JWKS.public_document([signing_key])

    :ok =
      Cache.put!(
        {:introspection_jwks, jwks_uri},
        public_jwks,
        ttl: :timer.minutes(5)
      )

    {:ok, assertion, _claims} =
      TamaOAuth.ClientAssertion.mint(client_id, endpoint, signing_key,
        algorithm: "RS256",
        algorithms: ["RS256"],
        kid: @introspection_kid,
        jti: TamaOAuth.Crypto.opaque_token(),
        now: OAuth.now() |> DateTime.to_unix(),
        ttl: 60
      )

    params = %{
      "token" => token,
      "client_id" => client_id,
      "client_assertion_type" => TamaOAuth.ClientAssertion.assertion_type(),
      "client_assertion" => assertion
    }

    {params, []}
  end
end
