defmodule MemoveeWeb.Auth.JWKSController do
  @moduledoc false

  use MemoveeWeb, :controller

  alias Memovee.OAuth.KeyProvider
  alias Memovee.OAuth.Tama.MCP

  action_fallback MemoveeWeb.Auth.FallbackController

  def show(conn, _params) do
    if MCP.configured?() do
      with {:ok, jwks} <- KeyProvider.public_jwks() do
        conn
        |> put_resp_header("cache-control", "public, max-age=300")
        |> json(jwks)
      end
    else
      send_resp(conn, :not_found, "")
    end
  end
end
