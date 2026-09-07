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

  @doc false
  def changeset(ingestion, attrs) do
    ingestion
    |> cast(attrs, [:original_content])
    |> validate_required([
      :owner_actor_id,
      :created_by_actor_id,
      :origin_identifier,
      :original_content
    ])
    |> validate_change(:original_content, fn :original_content, content ->
      if String.valid?(content) and String.trim(content) != "",
        do: [],
        else: [original_content: "must be nonblank UTF-8 text"]
    end)
    |> put_source_hash()
    |> foreign_key_constraint(:owner_actor_id)
    |> foreign_key_constraint(:created_by_actor_id)
    |> unique_constraint([:owner_actor_id, :origin_identifier])
  end

  defp put_source_hash(changeset) do
    case fetch_change(changeset, :original_content) do
      {:ok, content} when is_binary(content) ->
        put_change(
          changeset,
          :source_hash,
          :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        )

      _ ->
        changeset
    end
  end
end
