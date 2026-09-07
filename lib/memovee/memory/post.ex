defmodule Memovee.Memory.Post do
  @moduledoc """
  Canonical dense text projected into Tama.
  """

  use Memovee.Schema

  alias Memovee.Memory.{Candidate, Projection, Tagging}

  schema "memory_posts" do
    belongs_to :owner_actor, Memovee.Accounts.Actor
    belongs_to :created_by_actor, Memovee.Accounts.Actor
    field :memory_revision, :integer, default: 1
    field :title, :string
    field :body, :string
    field :body_hash, :string
    field :metadata, :map, default: %{}

    has_many :taggings, Tagging
    has_many :tags, through: [:taggings, :tag]
    has_many :projections, Projection

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body, :metadata])
    |> validate_required([:body, :metadata])
    |> validate_length(:title, max: 255)
    |> validate_change(:body, fn :body, body ->
      if byte_size(body) > 32_768, do: [body: "exceeds 32768 UTF-8 bytes"], else: []
    end)
    |> validate_change(:metadata, fn :metadata, metadata ->
      if Candidate.reserved?(metadata),
        do: [metadata: "contains reserved fields"],
        else: []
    end)
    |> validate_change(:body, fn :body, body ->
      if String.trim(body) == "", do: [body: "can't be blank"], else: []
    end)
    |> put_body_hash()
    |> check_constraint(:body, name: :memory_posts_body_non_blank)
    |> check_constraint(:body_hash, name: :memory_posts_body_hash_format)
  end

  defp put_body_hash(changeset) do
    case fetch_change(changeset, :body) do
      {:ok, body} -> put_change(changeset, :body_hash, body_hash(body))
      :error -> changeset
    end
  end

  defp body_hash(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end
end
