defmodule MemoveeWeb.Auth.ConsentLiveTest do
  use MemoveeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Memovee.OAuthFixtures

  alias Memovee.OAuth.Client.Registration.Manager, as: RegistrationManager

  setup :register_and_log_in_user

  test "renders the authenticated consent boundary", %{conn: conn} do
    assert {:ok, handle} = Memovee.OAuth.start_authorization(authorization_params())
    assert {:ok, view, _html} = live(conn, "/auth/consent/#{handle}")

    assert has_element?(view, "#oauth-consent")
    assert has_element?(view, "#oauth-consent-client-name")
    assert has_element?(view, "#oauth-consent-client-verification", "Verified metadata")
    assert has_element?(view, "#oauth-consent-client-uri")
    assert has_element?(view, "#oauth-consent-loopback-warning")
    refute has_element?(view, "#oauth-consent-unverified-warning")
    assert has_element?(view, "#oauth-consent-resource")
    assert has_element?(view, "#oauth-consent-scopes")
    assert has_element?(view, "#oauth-consent-form")
    assert has_element?(view, "#oauth-consent-approve")
    assert has_element?(view, "#oauth-consent-deny")
  end

  test "warns before authorizing dynamically registered client metadata", %{conn: conn} do
    redirect_uri = "http://127.0.0.1:49321/callback"

    assert {:ok, registration} =
             RegistrationManager.create(%{
               "application_type" => "native",
               "client_name" => "Unverified MCP Client",
               "client_uri" => "https://client.example",
               "redirect_uris" => [redirect_uri],
               "grant_types" => ["authorization_code", "refresh_token"],
               "response_types" => ["code"],
               "token_endpoint_auth_method" => "none",
               "scope" => "mcp.message"
             })

    assert {:ok, handle} =
             Memovee.OAuth.start_authorization(
               authorization_params(%{
                 "client_id" => registration["client_id"],
                 "redirect_uri" => redirect_uri
               })
             )

    assert {:ok, view, _html} = live(conn, "/auth/consent/#{handle}")

    assert has_element?(view, "#oauth-consent-client-verification", "Unverified metadata")
    assert has_element?(view, "#oauth-consent-unverified-warning")
    assert has_element?(view, "#oauth-consent-loopback-warning")
  end
end
