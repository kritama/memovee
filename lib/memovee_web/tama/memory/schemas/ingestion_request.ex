defmodule MemoveeWeb.Tama.Memory.Schemas.IngestionRequest do
  @moduledoc false
  require OpenApiSpex
  alias MemoveeWeb.Tama.Memory.Schemas.Context
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "OpenMemoryIngestion",
    type: :object,
    additionalProperties: false,
    required: [:context, :content],
    properties: %{context: Context, content: %Schema{type: :string, minLength: 1}}
  })
end
