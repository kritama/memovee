defmodule MemoveeWeb.Auth.RegistrationController do
  @moduledoc false

  use MemoveeWeb, :controller

  alias Memovee.OAuth.Client.Registration.Manager
  alias Memovee.OAuth.RateLimiter
  alias Memovee.OAuth.Tama.MCP

  action_fallback MemoveeWeb.Auth.FallbackController

  def create(conn, params) do
    with :ok <- MCP.require_enabled(),
         :ok <- require_json(conn),
         :ok <- rate_limit(conn.remote_ip),
         {:ok, response} <- Manager.create(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> json(response)
    end
  end

  defp require_json(conn) do
    case get_req_header(conn, "content-type") do
      ["application/json" <> _rest] -> :ok
      _headers -> {:error, TamaOAuth.Error.new(:invalid_request, stage: :content_type)}
    end
  end

  defp rate_limit(remote_ip) do
    case RateLimiter.registration(remote_ip) do
      :ok ->
        :ok

      {:error, _retry_after} ->
        {:error, TamaOAuth.Error.new(:temporarily_unavailable, stage: :rate_limit)}
    end
  end
end
