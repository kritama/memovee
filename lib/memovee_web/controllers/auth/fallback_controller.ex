defmodule MemoveeWeb.Auth.FallbackController do
  @moduledoc false

  use MemoveeWeb, :controller

  def call(conn, {:error, %TamaOAuth.Error{} = error}) do
    conn
    |> put_status(error.status)
    |> put_no_store()
    |> json(TamaOAuth.Error.to_map(error))
  end

  def call(conn, {:error, _reason}) do
    error = TamaOAuth.Error.new(:invalid_request)

    conn
    |> put_status(error.status)
    |> put_no_store()
    |> json(TamaOAuth.Error.to_map(error))
  end

  defp put_no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end
end
