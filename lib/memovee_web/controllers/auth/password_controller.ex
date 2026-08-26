defmodule MemoveeWeb.Auth.PasswordController do
  use MemoveeWeb, :controller

  alias Memovee.Accounts
  alias MemoveeWeb.UserAuth

  import MemoveeWeb.SessionHelper, only: [create_session: 3]

  def update(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create_session(params, "Password updated successfully!")
  end
end
