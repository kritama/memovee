defmodule MemoveeWeb.Tama.Memory.Schemas.UnauthorizedResponse do
  @moduledoc """
  Response body returned when Tama API authentication fails.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "UnauthorizedResponse",
    type: :object,
    additionalProperties: false,
    properties: %{
      error: %Schema{type: :string, enum: ["unauthorized"]}
    },
    required: [:error],
    example: %{"error" => "unauthorized"}
  })
end
