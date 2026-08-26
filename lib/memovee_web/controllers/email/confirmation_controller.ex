defmodule MemoveeWeb.Email.ConfirmationController do
  use MemoveeWeb, :controller

  alias Memovee.Accounts
  alias MemoveeWeb.UserAuth

  def show(conn, %{"token" => token}) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_email(user, token) do
      {:ok, {updated_user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, "Email changed successfully.")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(updated_user)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings")
    end
  end
end
