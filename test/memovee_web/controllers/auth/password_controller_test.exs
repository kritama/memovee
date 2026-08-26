defmodule MemoveeWeb.Auth.PasswordControllerTest do
  use MemoveeWeb.ConnCase, async: true

  import Memovee.AccountsFixtures

  alias Memovee.Accounts

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

  test "rejects invalid password parameters without expiring the session", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    session_token = get_session(conn, :user_token)

    conn =
      patch(conn, ~p"/auth/password", %{
        "user" => %{
          "password" => "too short",
          "password_confirmation" => "does not match"
        }
      })

    assert redirected_to(conn) == ~p"/users/settings"
    assert get_session(conn, :user_token) == session_token
    assert Accounts.get_user_by_session_token(session_token)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Password could not be updated. Check the requirements and try again."
  end

  test "rejects requests without user parameters", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> patch(~p"/auth/password", %{})

    assert redirected_to(conn) == ~p"/users/settings"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Password could not be updated. Check the requirements and try again."
  end
end
