defmodule Memovee.Memory.Post do
  @moduledoc """
  Canonical dense text projected into Tama.
  """

  use Memovee.Schema

  alias Memovee.Memory.{Metadata, Projection, Tagging}

  schema "memory_posts" do
    belongs_to :owner_actor, Memovee.Accounts.Actor
    belongs_to :created_by_actor, Memovee.Accounts.Actor
    field :memory_revision, :integer, default: 1
    field :origin_identifier, :string
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
  def changeset(post, attrs, opts \\ []) do
    post
    |> cast(attrs, [:title, :body, :metadata], empty_values: [])
    |> validate_required([:body, :metadata])
    |> validate_length(:title, min: 1, max: 255, count: :codepoints)
    |> validate_length(:body, max: 32_768, count: :codepoints)
    |> validate_change(:body, fn :body, body ->
      if String.valid?(body), do: [], else: [body: "must be valid UTF-8"]
    end)
    |> validate_format(:title, ~r/^[^\x00]*$/, message: "must not contain NUL characters")
    |> validate_format(:body, ~r/^[^\x00]*$/, message: "must not contain NUL characters")
    |> validate_change(:metadata, &Metadata.validate_strings/2)
    |> validate_change(:metadata, fn :metadata, metadata ->
      if Metadata.reserved?(metadata),
        do: [metadata: "contains reserved fields"],
        else: []
    end)
    |> validate_change(:body, fn :body, body ->
      if String.trim(body) == "", do: [body: "can't be blank"], else: []
    end)
    |> validate_structured_metadata(Keyword.get(opts, :structured, false))
    |> put_body_hash()
    |> unique_constraint([:owner_actor_id, :origin_identifier])
    |> check_constraint(:body, name: :memory_posts_body_non_blank)
    |> check_constraint(:body_hash, name: :memory_posts_body_hash_format)
  end

  @doc false
  def structured?(%__MODULE__{origin_identifier: origin_identifier}),
    do: is_binary(origin_identifier)

  @doc false
  def validate_structure(%__MODULE__{} = post, tags) when is_list(tags) do
    metadata_changeset = Metadata.changeset(%Metadata{}, post.metadata)
    kind = Ecto.Changeset.get_field(metadata_changeset, :kind)

    kind_keys =
      for tag <- tags,
          tag_value(tag, :namespace) == "kind",
          do: tag_value(tag, :key)

    if metadata_changeset.valid? and kind_keys == [kind],
      do: :ok,
      else: {:error, :invalid_candidate}
  end

  defp validate_structured_metadata(changeset, false), do: changeset

  defp validate_structured_metadata(changeset, true) do
    if Enum.all?(~w(title body metadata tags), &Map.has_key?(changeset.params, &1)) and
         Metadata.changeset(%Metadata{}, get_field(changeset, :metadata)).valid? do
      changeset
    else
      add_error(changeset, :metadata, "requires a complete structured memory payload")
    end
  end

  defp put_body_hash(changeset) do
    case fetch_change(changeset, :body) do
      {:ok, body} when is_binary(body) -> put_change(changeset, :body_hash, body_hash(body))
      _ -> changeset
    end
  end

  defp body_hash(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end

  defp tag_value(tag, key) when is_map(tag),
    do: Map.get(tag, key) || Map.get(tag, Atom.to_string(key))
end
