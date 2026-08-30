defmodule MemoveeWeb.Tama.Memory.Schemas.MemoryPostResponse do
  @moduledoc """
  Response body for a single canonical memory post.
  """

  require OpenApiSpex

  alias MemoveeWeb.Tama.Memory.Schemas.MemoryPost

  OpenApiSpex.schema(%{
    title: "MemoryPostResponse",
    type: :object,
    additionalProperties: false,
    properties: %{
      data: MemoryPost
    },
    required: [:data],
    example: %{
      "data" => MemoryPost.schema().example
    }
  })
end
