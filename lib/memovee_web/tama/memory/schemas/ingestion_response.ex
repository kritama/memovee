defmodule MemoveeWeb.Tama.Memory.Schemas.IngestionResponse do
  @moduledoc false
  require OpenApiSpex
  alias MemoveeWeb.Tama.Memory.Schemas.SaveReceipt
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MemoryIngestionResponse",
    type: :object,
    additionalProperties: false,
    required: [:data],
    properties: %{
      data: %Schema{
        type: :object,
        additionalProperties: false,
        required: [:ingestion_id, :state, :source_hash, :receipt],
        properties: %{
          ingestion_id: %Schema{type: :string, format: :uuid},
          state: %Schema{type: :string, enum: ~w(open saved)},
          source_hash: %Schema{type: :string},
          receipt: %Schema{allOf: [SaveReceipt], nullable: true}
        }
      }
    }
  })
end
