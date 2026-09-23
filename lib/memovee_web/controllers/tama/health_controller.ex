defmodule MemoveeWeb.Tama.HealthController do
  use MemoveeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MemoveeWeb.Schemas.Tama.HealthResponse
  alias MemoveeWeb.Schemas.Tama.Memory.UnauthorizedResponse

  tags ["memory"]

  operation :show,
    operation_id: "tama_health_show",
    summary: "Validate an Agent API credential",
    responses: [
      ok: {"Authorized Agent", "application/json", HealthResponse},
      unauthorized:
        {"Invalid or missing API credential", "application/json", UnauthorizedResponse}
    ]

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
