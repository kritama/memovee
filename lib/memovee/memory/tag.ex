defmodule Memovee.Memory.Tag do
  @moduledoc """
  Namespaced taxonomy value assigned to memory posts.
  """

  use Memovee.Schema

  alias Memovee.Memory.Tagging

  @key_format ~r/\A[a-z0-9][a-z0-9._-]*\z/

  schema "memory_tags" do
    field :namespace, :string
    field :key, :string
    field :name, :string
    field :description, :string
    field :metadata, :map, default: %{}

    has_many :taggings, Tagging
    has_many :posts, through: [:taggings, :post]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:namespace, :key, :name, :description, :metadata])
    |> update_change(:namespace, &normalize_key/1)
    |> update_change(:key, &normalize_key/1)
    |> validate_required([:namespace, :key, :name, :metadata])
    |> validate_length(:namespace, max: 100)
    |> validate_format(:namespace, @key_format)
    |> validate_format(:key, @key_format)
    |> validate_change(:name, fn :name, name ->
      if String.trim(name) == "", do: [name: "can't be blank"], else: []
    end)
    |> check_constraint(:name, name: :memory_tags_name_non_blank)
    |> unique_constraint([:namespace, :key], name: :memory_tags_namespace_key_index)
  end

  defp normalize_key(value), do: value |> String.trim() |> String.downcase()
end
