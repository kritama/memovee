defmodule MemoveeWeb.Schemas.Tama.Memory.MemoryErrorResponse do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MemoryErrorResponse",
    type: :object,
    additionalProperties: false,
    required: [:error],
    properties: %{
      error: %Schema{
        type: :object,
        additionalProperties: false,
        required: [:code, :message, :retryable, :details],
        properties: %{
          code: %Schema{type: :string},
          message: %Schema{type: :string},
          retryable: %Schema{type: :boolean},
          details: %Schema{type: :object, additionalProperties: true}
        }
      }
    }
  })
end
