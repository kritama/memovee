defmodule MemoveeWeb.Tama.Memory.Schemas.CreatePostRequest do
  @moduledoc false
  require OpenApiSpex
  alias MemoveeWeb.Tama.Memory.Schemas.{Context, MemoryMetadata}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CreateMemoryPostRequest",
    type: :object,
    additionalProperties: false,
    required: [:context, :post],
    properties: %{
      context: Context,
      post: %Schema{
        type: :object,
        additionalProperties: false,
        required: [:title, :body, :metadata, :tags],
        properties: %{
          title: %Schema{type: :string, nullable: true, minLength: 1, maxLength: 255},
          body: %Schema{
            type: :string,
            minLength: 1,
            maxLength: 32_768,
            description: "At most 32768 UTF-8 bytes"
          },
          metadata: MemoryMetadata,
          tags: %Schema{
            type: :array,
            maxItems: 12,
            items: %Schema{
              type: :object,
              additionalProperties: false,
              required: [:namespace, :key, :name],
              properties: %{
                namespace: %Schema{type: :string, enum: ~w(kind project topic tool)},
                key: %Schema{type: :string, minLength: 1, maxLength: 100},
                name: %Schema{type: :string, minLength: 1, maxLength: 255}
              }
            }
          }
        }
      }
    }
  })
end
