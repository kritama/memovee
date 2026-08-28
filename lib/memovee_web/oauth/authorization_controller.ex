defmodule MemoveeWeb.OAuth.AuthorizationController do
  @moduledoc false

  use MemoveeWeb, :controller

  alias Memovee.OAuth

  action_fallback MemoveeWeb.OAuth.FallbackController

  def new(conn, params) do
    with {:ok, handle} <- OAuth.start_authorization(params, conn.remote_ip) do
      redirect(conn, to: ~p"/auth/consent/#{handle}")
    end
  end
end
