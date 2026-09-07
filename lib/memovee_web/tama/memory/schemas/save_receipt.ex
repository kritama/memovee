defmodule MemoveeWeb.Tama.Memory.Schemas.SaveReceipt do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "SaveReceipt",
    type: :object,
    additionalProperties: false,
    required: [:post_id, :ingestion_id, :body_hash, :tag_ids, :indexing_status, :replayed],
    properties: %{
      post_id: %Schema{type: :string, format: :uuid},
      ingestion_id: %Schema{type: :string, format: :uuid},
      body_hash: %Schema{type: :string},
      tag_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
      indexing_status: %Schema{type: :string, enum: ~w(pending processing ready failed)},
      replayed: %Schema{type: :boolean}
    }
  })
end
