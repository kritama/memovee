defmodule MemoveeWeb.Schemas.Tama.HealthResponse do
  @moduledoc "Response body for the authenticated Agent API health check."

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TamaHealthResponse",
    type: :object,
    additionalProperties: false,
    properties: %{
      status: %Schema{type: :string, enum: ["ok"]}
    },
    required: [:status],
    example: %{"status" => "ok"}
  })
end
