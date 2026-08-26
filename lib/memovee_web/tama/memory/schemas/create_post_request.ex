defmodule MemoveeWeb.Tama.Memory.Schemas.CreatePostRequest do
  @moduledoc """
  Request body for creating a canonical memory post.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateMemoryPostRequest",
    type: :object,
    additionalProperties: false,
    properties: %{
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
        description: "Canonical memory text"
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
