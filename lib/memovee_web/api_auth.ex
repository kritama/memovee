defmodule MemoveeWeb.ApiAuth do
  @moduledoc """
  Authenticates direct API requests as active agent Actors.
  """

  import Plug.Conn

  alias Memovee.Accounts
  alias Memovee.Accounts.Scope

  @bearer_pattern ~r/\ABearer ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.([A-Za-z0-9_-]{43})\z/

  def init(opts), do: opts

  def call(conn, _opts) do
    with [authorization] <- get_req_header(conn, "authorization"),
         [_, client_id, client_secret] <- Regex.run(@bearer_pattern, authorization),
         {:ok, actor} <- Accounts.verify_api_token(client_id, client_secret, "api") do
      assign(conn, :current_scope, Scope.for_actor(actor))
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, body)
    |> halt()
  end
end
