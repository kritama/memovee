defmodule MemoveeWeb.Tama.Memory.Schemas.CreatePostRequest do
  @moduledoc "Ordinary-agent and trusted Tama service save envelopes. Saved source identifiers replay before candidate validation."
  require OpenApiSpex
  alias MemoveeWeb.Tama.Memory.Schemas.{DirectPostRequest, GraphPostRequest}

  OpenApiSpex.schema(%{
    title: "CreateMemoryPostRequest",
    oneOf: [GraphPostRequest, DirectPostRequest]
  })
end
