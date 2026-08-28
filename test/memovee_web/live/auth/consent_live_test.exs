defmodule MemoveeWeb.Auth.ConsentLiveTest do
  use MemoveeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Memovee.OAuthFixtures

  setup :register_and_log_in_user

  test "renders the authenticated consent boundary", %{conn: conn} do
    assert {:ok, handle} = Memovee.OAuth.start_authorization(authorization_params())
    assert {:ok, view, _html} = live(conn, "/auth/consent/#{handle}")

    assert has_element?(view, "#oauth-consent")
    assert has_element?(view, "#oauth-consent-client-name")
    assert has_element?(view, "#oauth-consent-resource")
    assert has_element?(view, "#oauth-consent-form")
    assert has_element?(view, "#oauth-consent-approve")
    assert has_element?(view, "#oauth-consent-deny")
  end
end
