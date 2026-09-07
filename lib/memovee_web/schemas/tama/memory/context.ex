defmodule MemoveeWeb.Schemas.Tama.Memory.Context do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MemoryContext",
    type: :object,
    additionalProperties: false,
    required: [:actor_id, :origin_identifier],
    properties: %{
      actor_id: %Schema{type: :string, format: :uuid},
      origin_identifier: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 512,
        pattern: ~r/^[^\x00]*$/
      }
    }
  })
end
