defmodule MemoveeWeb.Auth.EndpointsTest do
  use MemoveeWeb.ConnCase, async: false

  import Memovee.OAuthFixtures

  alias Memovee.OAuth.Client

  test "publishes authorization-server metadata", %{conn: conn} do
    conn = get(conn, "/.well-known/oauth-authorization-server")

    assert response = json_response(conn, 200)
    assert response["issuer"] == Memovee.OAuth.issuer()
    assert response["token_endpoint"] == Memovee.OAuth.endpoint("/auth/tokens")
    assert response["scopes_supported"] == ["mcp.message"]
    assert response["code_challenge_methods_supported"] == ["S256"]
    assert response["protected_resources"] == [Memovee.OAuth.resource()]
    assert ["no-store"] = get_resp_header(conn, "cache-control")
    assert ["no-cache"] = get_resp_header(conn, "pragma")
  end

  test "publishes public-only JWKS", %{conn: conn} do
    conn = get(conn, "/.well-known/jwks.json")
    assert %{"keys" => [key]} = json_response(conn, 200)
    assert key["kid"] == "memovee-oauth-test-rs256-1"

    for private_parameter <- ~w(d p q dp dq qi oth k) do
      refute Map.has_key?(key, private_parameter)
    end
  end

  test "starts authorization in the browser and requires login for consent", %{conn: conn} do
    conn = get(conn, "/auth/authorizations/new", authorization_params())
    assert [consent_path] = get_resp_header(conn, "location")
    assert consent_path =~ "/auth/consent/"

    conn = get(recycle(conn), consent_path)
    assert redirected_to(conn) =~ "/users/log-in"
  end

  test "token endpoint rejects JSON bodies with an OAuth error", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/auth/tokens", %{"grant_type" => "authorization_code"})

    assert %{"error" => "invalid_request"} = json_response(conn, 400)
    assert ["no-store"] = get_resp_header(conn, "cache-control")
  end

  test "token mode gate precedes content-type validation", %{conn: conn} do
    original = Application.fetch_env!(:memovee, Memovee.OAuth)
    on_exit(fn -> Application.put_env(:memovee, Memovee.OAuth, original) end)

    for mode <- [:disabled, :prepared] do
      Application.put_env(:memovee, Memovee.OAuth, Keyword.put(original, :mode, mode))

      response_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/auth/tokens", %{"grant_type" => "authorization_code"})

      assert %{"error" => "invalid_grant"} = json_response(response_conn, 400)
      assert ["no-store"] = get_resp_header(response_conn, "cache-control")
    end
  end

  test "disabled endpoint mode gates precede content-type validation", %{conn: conn} do
    replace_oauth_config(mode: :disabled, minimal: true)

    introspection_conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/auth/introspections", %{"token" => "unknown"})

    assert %{"error" => "invalid_client"} = json_response(introspection_conn, 401)
    assert ["no-store"] = get_resp_header(introspection_conn, "cache-control")

    revocation_conn =
      introspection_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/auth/revocations", %{"token" => "unknown"})

    assert %{"error" => "temporarily_unavailable"} = json_response(revocation_conn, 503)
    assert ["no-store"] = get_resp_header(revocation_conn, "cache-control")
  end

  test "introspection requires the configured Tama credential", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/introspections", %{"token" => "unknown"})

    assert %{"error" => "invalid_client"} = json_response(conn, 401)
  end

  test "prepared mode publishes trust but does not advertise or authorize the resource", %{
    conn: conn
  } do
    replace_oauth_config(mode: :prepared)

    metadata_conn = get(conn, "/.well-known/oauth-authorization-server")
    metadata = json_response(metadata_conn, 200)
    refute Map.has_key?(metadata, "protected_resources")
    assert ["no-store"] = get_resp_header(metadata_conn, "cache-control")

    jwks_conn = get(recycle(metadata_conn), "/.well-known/jwks.json")
    assert %{"keys" => [_key]} = json_response(jwks_conn, 200)

    authorization_conn =
      get(recycle(jwks_conn), "/auth/authorizations/new", authorization_params())

    assert %{"error" => "temporarily_unavailable"} = json_response(authorization_conn, 503)

    token_conn =
      authorization_conn
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/tokens", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id(),
        "code" => "unusable"
      })

    assert %{"error" => "invalid_grant"} = json_response(token_conn, 400)

    registration_conn =
      token_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/auth/registrations", %{})

    assert %{"error" => "temporarily_unavailable"} = json_response(registration_conn, 503)

    revocation_conn =
      registration_conn
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/revocations", %{
        "client_id" => client_id(),
        "token" => "deliberately-invalid-access-token"
      })

    assert response(revocation_conn, 200) == ""
  end

  test "prepared mode authenticates a Tama assertion and returns inactive for an unknown token",
       %{
         conn: conn
       } do
    replace_oauth_config(mode: :prepared)
    {params, []} = introspection_request("deliberately-invalid-access-token")

    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/introspections", params)

    assert %{"active" => false} = json_response(conn, 200)

    replay_conn =
      conn
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/introspections", params)

    assert %{"error" => "invalid_client"} = json_response(replay_conn, 401)
  end

  test "disabled mode needs no integration values and exposes no trust endpoints", %{conn: conn} do
    authorization_request = authorization_params()
    replace_oauth_config(mode: :disabled, minimal: true)

    metadata_conn = get(conn, "/.well-known/oauth-authorization-server")
    assert response(metadata_conn, 404) == ""
    assert ["no-store"] = get_resp_header(metadata_conn, "cache-control")

    jwks_conn = get(recycle(metadata_conn), "/.well-known/jwks.json")
    assert response(jwks_conn, 404) == ""

    authorization_conn =
      get(recycle(jwks_conn), "/auth/authorizations/new", authorization_request)

    assert %{"error" => "temporarily_unavailable"} = json_response(authorization_conn, 503)

    registration_conn =
      authorization_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/auth/registrations", %{})

    assert %{"error" => "temporarily_unavailable"} = json_response(registration_conn, 503)

    token_conn =
      registration_conn
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/tokens", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id(),
        "code" => "unusable"
      })

    assert %{"error" => "invalid_grant"} = json_response(token_conn, 400)

    introspection_conn =
      token_conn
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/introspections", %{"token" => "unknown"})

    assert %{"error" => "invalid_client"} = json_response(introspection_conn, 401)

    revocation_conn =
      introspection_conn
      |> recycle()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/revocations", %{"client_id" => client_id(), "token" => "unknown"})

    assert %{"error" => "temporarily_unavailable"} = json_response(revocation_conn, 503)
  end

  test "filters OAuth and account credentials from Phoenix parameter logs" do
    credentials =
      Map.new(
        ~w(
          access_token
          authorization
          client_assertion
          client_secret
          code
          password
          password_confirmation
          refresh_token
          token
        ),
        &{&1, "must-not-appear"}
      )

    assert Phoenix.Logger.filter_values(credentials) ==
             Map.new(credentials, fn {key, _value} -> {key, "[FILTERED]"} end)
  end

  test "malformed introspection requests share a fixed unknown-client rate bucket" do
    clear_unknown_introspection_bucket()
    on_exit(&clear_unknown_introspection_bucket/0)

    request_marker = System.unique_integer([:positive, :monotonic])

    results =
      Enum.map(1..121, fn request ->
        Memovee.OAuth.introspect(
          %{"token" => "unknown"},
          ["Bearer malformed-#{request_marker}-#{request}"],
          {:introspection_rate_limit_test, request_marker, request}
        )
      end)

    assert Enum.any?(results, fn
             {:error, %TamaOAuth.Error{code: :temporarily_unavailable, stage: :rate_limit}} ->
               true

             _result ->
               false
           end)
  end

  test "registers a bounded public native client without issuing a secret", %{conn: conn} do
    params = %{
      "application_type" => "native",
      "client_name" => "Local MCP Host",
      "redirect_uris" => ["http://127.0.0.1:49321/callback"],
      "grant_types" => ["authorization_code", "refresh_token"],
      "response_types" => ["code"],
      "token_endpoint_auth_method" => "none",
      "scope" => "mcp.message"
    }

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/auth/registrations", params)

    assert response = json_response(conn, 201)
    assert response["client_id"] =~ "/auth/registrations/"
    assert response["token_endpoint_auth_method"] == "none"
    refute Map.has_key?(response, "client_secret")
    assert {:ok, metadata} = Client.fetch(response["client_id"])
    assert metadata.registration_type == :dynamic
    refute metadata.verified_client_metadata?
  end

  defp replace_oauth_config(options) do
    original = Application.fetch_env!(:memovee, Memovee.OAuth)
    on_exit(fn -> Application.put_env(:memovee, Memovee.OAuth, original) end)

    replacement =
      if Keyword.get(options, :minimal, false) do
        [mode: Keyword.fetch!(options, :mode)]
      else
        Keyword.put(original, :mode, Keyword.fetch!(options, :mode))
      end

    Application.put_env(:memovee, Memovee.OAuth, replacement)
  end

  defp clear_unknown_introspection_bucket do
    identifier_digest = :unknown |> :erlang.term_to_binary() |> TamaOAuth.Crypto.digest()

    key =
      :erlang.term_to_binary(
        {Memovee.OAuth.RateLimiter, :introspection, :client, identifier_digest}
      )

    :ets.match_delete(Memovee.OAuth.RateLimiter.Local, {{key, :_}, :_, :_})
  end
end
