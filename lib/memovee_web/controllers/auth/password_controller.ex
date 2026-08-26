defmodule MemoveeWeb.Auth.PasswordController do
  use MemoveeWeb, :controller

  alias Memovee.Accounts
  alias MemoveeWeb.UserAuth

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {updated_user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, "Password updated successfully!")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(updated_user, user_params)

      {:error, %Ecto.Changeset{}} ->
        reject_invalid_password(conn)
    end
  end

  def update(conn, _params), do: reject_invalid_password(conn)

  defp reject_invalid_password(conn) do
    conn
    |> put_flash(
      :error,
      "Password could not be updated. Check the requirements and try again."
    )
    |> redirect(to: ~p"/users/settings")
  end
end
