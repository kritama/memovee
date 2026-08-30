defmodule MemoveeWeb.Auth.IntrospectionController do
  @moduledoc false

  use MemoveeWeb, :controller

  alias Memovee.OAuth

  action_fallback MemoveeWeb.Auth.FallbackController

  def create(conn, params) do
    with :ok <- require_form_encoding(conn),
         {:ok, response} <-
           OAuth.introspect(params, get_req_header(conn, "authorization"), conn.remote_ip) do
      conn
      |> put_no_store()
      |> json(response)
    end
  end

  defp require_form_encoding(conn) do
    case get_req_header(conn, "content-type") do
      ["application/x-www-form-urlencoded" <> _rest] -> :ok
      _headers -> {:error, TamaOAuth.Error.new(:invalid_request, stage: :content_type)}
    end
  end

  defp put_no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end
end
