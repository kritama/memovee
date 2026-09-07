defmodule MemoveeWeb.Schemas.Tama.Memory.SaveReceipt do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SaveReceipt",
    type: :object,
    additionalProperties: false,
    required: [:post_id, :body_hash, :tag_ids, :indexing_status, :replayed],
    properties: %{
      post_id: %Schema{type: :string, format: :uuid},
      body_hash: %Schema{type: :string, pattern: ~r/^[0-9a-f]{64}$/},
      tag_ids: %Schema{
        type: :array,
        maxItems: 12,
        uniqueItems: true,
        items: %Schema{type: :string, format: :uuid}
      },
      indexing_status: %Schema{type: :string, enum: ~w(pending processing ready failed)},
      replayed: %Schema{type: :boolean}
    }
  })
end
