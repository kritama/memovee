defmodule MemoveeWeb.Tama.Memory.Schemas.MemoryTagInput do
  @moduledoc false
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MemoryTagInput",
    type: :object,
    additionalProperties: false,
    required: [:namespace, :name],
    properties: %{
      namespace: %Schema{
        type: :string,
        description: "Trimmed and lowercased; kind, project, topic or tool"
      },
      key: %Schema{
        type: :string,
        maxLength: 100,
        description: "Canonical key; generated from name when omitted"
      },
      name: %Schema{type: :string, minLength: 1, maxLength: 255},
      description: %Schema{type: :string, nullable: true},
      metadata: %Schema{type: :object, additionalProperties: true}
    }
  })
end
