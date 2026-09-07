defmodule MemoveeWeb.Tama.Memory.Schemas.DirectPostRequest do
  @moduledoc """
  Request body for creating a canonical memory post.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "DirectMemoryPostRequest",
    type: :object,
    additionalProperties: false,
    properties: %{
      tags: %Schema{
        type: :array,
        items: MemoveeWeb.Tama.Memory.Schemas.MemoryTagInput,
        description: "At most twelve unique normalized tags, including the synthesized kind tag"
      },
      title: %Schema{
        type: :string,
        nullable: true,
        maxLength: 255,
        description: "Optional human-readable title"
      },
      body: %Schema{
        type: :string,
        minLength: 1,
        pattern: ~r/\S/,
        description: "Canonical memory text, at most 32768 UTF-8 bytes"
      },
      metadata: %Schema{
        type: :object,
        properties: %{},
        additionalProperties: true,
        default: %{},
        description: "Arbitrary JSON metadata"
      }
    },
    required: [:body],
    example: %{
      "title" => "Launch notes",
      "body" => "The launch is scheduled for Friday.",
      "metadata" => %{"source" => "agent"}
    }
  })
end
