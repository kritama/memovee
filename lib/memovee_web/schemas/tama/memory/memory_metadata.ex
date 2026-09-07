defmodule MemoveeWeb.Schemas.Tama.Memory.MemoryMetadata do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MemoryMetadataV1",
    type: :object,
    additionalProperties: false,
    required: [
      :kind,
      :epistemic_status,
      :approval,
      :source,
      :occurred_at,
      :effective_at,
      :derived_from_post_ids
    ],
    properties: %{
      kind: %Schema{
        type: :string,
        enum: ~w(fact preference decision brief progress review procedure)
      },
      epistemic_status: %Schema{
        type: :string,
        enum: ~w(user_stated observed proposed inferred reported)
      },
      approval: %Schema{type: :string, enum: ~w(unspecified proposed reported_approved)},
      source: %Schema{
        type: :object,
        additionalProperties: false,
        required: [:channel, :reference],
        properties: %{
          channel: %Schema{type: :string, enum: ["agent"]},
          reference: %Schema{type: :string, nullable: true, maxLength: 512}
        }
      },
      occurred_at: %Schema{type: :string, format: :"date-time", nullable: true},
      effective_at: %Schema{type: :string, format: :"date-time", nullable: true},
      derived_from_post_ids: %Schema{
        type: :array,
        maxItems: 20,
        uniqueItems: true,
        items: %Schema{type: :string, format: :uuid}
      }
    }
  })
end
