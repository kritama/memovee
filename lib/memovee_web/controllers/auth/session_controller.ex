defmodule MemoveeWeb.Auth.SessionController do
  use MemoveeWeb, :controller

  alias MemoveeWeb.UserAuth

  import MemoveeWeb.SessionHelper, only: [create_session: 3]

  def create(conn, %{"_action" => "confirmed"} = params) do
    create_session(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create_session(conn, params, "Welcome back!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
