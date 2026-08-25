defmodule Memovee.Memory.Post do
  @moduledoc """
  Canonical dense text projected into Tama.
  """

  use Memovee.Schema

  alias Memovee.Memory.{Projection, Tagging}

  schema "memory_posts" do
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
