defmodule MemoveeWeb.Tama.Memory.Schemas.IngestionStatusRequest do
  @moduledoc false
  require OpenApiSpex
  alias MemoveeWeb.Tama.Memory.Schemas.Context

  OpenApiSpex.schema(%{
    title: "MemoryIngestionStatus",
    type: :object,
    additionalProperties: false,
    required: [:context],
    properties: %{context: Context}
  })
end
