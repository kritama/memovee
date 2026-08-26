defmodule MemoveeWeb.Tama.Memory.Schemas.MemoryPost do
  @moduledoc """
  API representation of a canonical memory post.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MemoryPost",
    type: :object,
    additionalProperties: false,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string, nullable: true},
      body: %Schema{type: :string},
      body_hash: %Schema{type: :string, pattern: ~r/^[0-9a-f]{64}$/},
      metadata: %Schema{type: :object, properties: %{}, additionalProperties: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :title, :body, :body_hash, :metadata, :inserted_at, :updated_at],
    example: %{
      "id" => "0198ed0c-c430-7cf0-a7c9-97304f9c7644",
      "title" => "Launch notes",
      "body" => "The launch is scheduled for Friday.",
      "body_hash" => "ad2207af482b9822e557ed8c2dccd5d53113e901b60f2c3fb3b393f53c5062cd",
      "metadata" => %{"source" => "agent"},
      "inserted_at" => "2026-08-27T12:00:00Z",
      "updated_at" => "2026-08-27T12:00:00Z"
    }
  })
end
