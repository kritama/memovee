defmodule MemoveeWeb.Auth.PasswordControllerTest do
  use MemoveeWeb.ConnCase, async: true

  import Memovee.AccountsFixtures

  test "requires authentication within the ten-minute sudo window", %{conn: conn} do
    user = user_fixture()
    eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)

    conn =
      conn
      |> log_in_user(user, token_authenticated_at: eleven_minutes_ago)
      |> patch(~p"/auth/password", %{"user" => %{}})

    assert conn.halted
    assert redirected_to(conn) == ~p"/users/log-in"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You must re-authenticate to access this page."
  end
end
