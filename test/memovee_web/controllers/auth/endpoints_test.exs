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
  end

  test "publishes public-only JWKS", %{conn: conn} do
    conn = get(conn, "/.well-known/jwks.json")
    assert %{"keys" => [key]} = json_response(conn, 200)
    assert key["kid"] == "memovee-oauth-test-1"

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

  test "introspection requires the configured Tama credential", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/introspections", %{"token" => "unknown"})

    assert %{"error" => "invalid_client"} = json_response(conn, 401)
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
end
