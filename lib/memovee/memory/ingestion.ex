defmodule Memovee.Memory.Ingestion do
  @moduledoc "An immutable source submission and its eventual canonical Post."
  use Memovee.Schema

  schema "memory_ingestions" do
    belongs_to :owner_actor, Memovee.Accounts.Actor
    belongs_to :created_by_actor, Memovee.Accounts.Actor
    belongs_to :post, Memovee.Memory.Post
    field :origin_identifier, :string
    field :original_content, :string
    field :source_hash, :string
    field :saved_receipt, :map
    timestamps(type: :utc_datetime)
  end
end
