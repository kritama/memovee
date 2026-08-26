defmodule MemoveeWeb.Email.ConfirmationControllerTest do
  use MemoveeWeb.ConnCase, async: true

  import Memovee.AccountsFixtures

  alias Memovee.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    new_email = unique_user_email()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_update_email_instructions(
          %{user | email: new_email},
          user.email,
          url
        )
      end)

    conn = log_in_user(conn, user)
    current_token = get_session(conn, :user_token)
    other_token = Accounts.generate_user_session_token(user)

    for session_token <- [current_token, other_token] do
      MemoveeWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(session_token)}")
    end

    %{
      conn: conn,
      user: user,
      new_email: new_email,
      token: token,
      current_token: current_token,
      other_token: other_token
    }
  end

  test "updates the email, disconnects old sessions, and establishes a new session", context do
    conn = get(context.conn, ~p"/users/settings/confirm-email/#{context.token}")

    assert redirected_to(conn) == ~p"/users/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Email changed successfully."
    refute Accounts.get_user_by_email(context.user.email)
    assert Accounts.get_user_by_email(context.new_email)

    new_token = get_session(conn, :user_token)
    assert new_token not in [context.current_token, context.other_token]
    assert Accounts.get_user_by_session_token(new_token)
    refute Accounts.get_user_by_session_token(context.current_token)
    refute Accounts.get_user_by_session_token(context.other_token)

    current_topic = "users_sessions:#{Base.url_encode64(context.current_token)}"
    other_topic = "users_sessions:#{Base.url_encode64(context.other_token)}"

    assert_receive %Phoenix.Socket.Broadcast{
      event: "disconnect",
      topic: ^current_topic
    }

    assert_receive %Phoenix.Socket.Broadcast{
      event: "disconnect",
      topic: ^other_topic
    }
  end

  test "rejects an invalid token without replacing the session", context do
    conn = get(context.conn, ~p"/users/settings/confirm-email/invalid")

    assert redirected_to(conn) == ~p"/users/settings"
    assert get_session(conn, :user_token) == context.current_token
    assert Accounts.get_user_by_email(context.user.email)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Email change link is invalid or it has expired."
  end

  test "requires an authenticated user", %{token: token} do
    conn = build_conn() |> get(~p"/users/settings/confirm-email/#{token}")

    assert conn.halted
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
