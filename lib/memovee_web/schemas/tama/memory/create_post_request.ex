defmodule MemoveeWeb.Schemas.Tama.Memory.CreatePostRequest do
  @moduledoc false
  require OpenApiSpex
  alias MemoveeWeb.Schemas.Tama.Memory.{Context, MemoryMetadata}
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
          title: %Schema{
            type: :string,
            nullable: true,
            minLength: 1,
            maxLength: 255,
            pattern: ~r/^[^\x00]*$/
          },
          body: %Schema{
            type: :string,
            minLength: 1,
            maxLength: 32_768,
            pattern: ~r/^(?=[^\x00]*\S)[^\x00]*$/,
            description: "At most 32768 Unicode code points"
          },
          metadata: MemoryMetadata,
          tags: %Schema{
            allOf: [
              %Schema{
                type: :array,
                maxItems: 12,
                uniqueItems: true,
                description:
                  "At most 11 tags without a kind tag; 12 tags require an explicit kind tag matching metadata.kind.",
                items: %Schema{
                  type: :object,
                  additionalProperties: false,
                  required: [:namespace, :key, :name],
                  properties: %{
                    namespace: %Schema{type: :string, enum: ~w(kind project topic tool)},
                    key: %Schema{
                      type: :string,
                      minLength: 1,
                      maxLength: 100,
                      pattern: ~r/^[a-z0-9][a-z0-9._-]*$/
                    },
                    name: %Schema{
                      type: :string,
                      minLength: 1,
                      maxLength: 255,
                      pattern: ~r/^(?=[^\x00]*\S)[^\x00]*$/
                    }
                  }
                }
              },
              %Schema{
                anyOf: [
                  %Schema{type: :array, maxItems: 11},
                  %Schema{
                    not: %Schema{
                      type: :array,
                      items: %Schema{
                        type: :object,
                        not: %Schema{
                          type: :object,
                          properties: %{namespace: %Schema{type: :string, enum: ["kind"]}},
                          required: [:namespace]
                        }
                      }
                    }
                  }
                ]
              }
            ]
          }
        }
      }
    }
  })
end
