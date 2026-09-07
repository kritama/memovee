defmodule Memovee.Memory.Tag do
  @moduledoc """
  Namespaced taxonomy value assigned to memory posts.
  """

  use Memovee.Schema

  alias Memovee.Memory.{Metadata, Tagging}

  @tag_keys ~w(namespace key name description metadata)

  @key_format ~r/\A[a-z0-9][a-z0-9._-]*\z/

  schema "memory_tags" do
    belongs_to :owner_actor, Memovee.Accounts.Actor
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
    |> validate_length(:key, max: 100)
    |> validate_length(:name, max: 255)
    |> validate_format(:namespace, @key_format)
    |> validate_format(:key, @key_format)
    |> validate_change(:name, fn :name, name ->
      if String.trim(name) == "", do: [name: "can't be blank"], else: []
    end)
    |> validate_change(:metadata, fn :metadata, metadata ->
      if Metadata.reserved?(metadata), do: [metadata: "contains reserved fields"], else: []
    end)
    |> check_constraint(:name, name: :memory_tags_name_non_blank)
    |> unique_constraint([:owner_actor_id, :namespace, :key],
      name: :memory_tags_owner_actor_id_namespace_key_index
    )
  end

  def prepare(values, metadata, graph?) when is_list(values) do
    with true <- not graph? or Enum.all?(values, &graph_tag?/1),
         {:ok, normalized} <- normalize_tags(values),
         {:ok, normalized} <- kind_tag(normalized, metadata, graph?) do
      tags =
        normalized
        |> Enum.uniq_by(&{&1["namespace"], &1["key"]})
        |> Enum.sort_by(&{&1["namespace"], &1["key"]})

      if length(tags) <= 12, do: {:ok, tags}, else: {:error, :invalid_tags}
    else
      false -> {:error, :invalid_tags}
      error -> error
    end
  end

  def prepare(_, _, _), do: {:error, :invalid_tags}

  defp graph_tag?(tag) when is_map(tag), do: Enum.sort(Map.keys(tag)) == ~w(key name namespace)
  defp graph_tag?(_), do: false

  defp normalize_tags(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case normalize_tag(value) do
        {:ok, tag} -> {:cont, {:ok, acc ++ [tag]}}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_tag(%{"namespace" => namespace, "name" => name} = tag)
       when is_binary(namespace) and is_binary(name) do
    namespace = namespace |> String.trim() |> String.downcase()
    key = Map.get(tag, "key", generated_key(name))
    key = if is_binary(key), do: key |> String.trim() |> String.downcase(), else: key
    normalized = tag |> Map.put("namespace", namespace) |> Map.put("key", key)

    if Enum.all?(Map.keys(tag), &(&1 in @tag_keys)) and namespace in ~w(kind project topic tool) and
         changeset(%__MODULE__{}, normalized).valid? do
      {:ok, normalized}
    else
      {:error, :invalid_tags}
    end
  end

  defp normalize_tag(_), do: {:error, :invalid_tags}

  defp generated_key(name) do
    key =
      name
      |> String.downcase()
      |> String.replace("/", ".")
      |> String.replace(~r/[^a-z0-9._-]+/, "-")
      |> String.trim_leading(".")

    key = key |> String.replace(~r/\A[._-]+|[._-]+\z/, "") |> String.slice(0, 100)

    if key == "",
      do:
        "tag-" <> String.slice(:crypto.hash(:sha256, name) |> Base.encode16(case: :lower), 0, 12),
      else: key
  end

  defp kind_tag(tags, metadata, graph?) do
    kind = metadata["kind"]
    kinds = Enum.filter(tags, &(&1["namespace"] == "kind"))

    cond do
      not graph? ->
        {:ok, tags}

      Enum.any?(kinds, &(&1["key"] != kind)) ->
        {:error, :kind_tag_mismatch}

      kinds == [] ->
        {:ok, [%{"namespace" => "kind", "key" => kind, "name" => String.capitalize(kind)} | tags]}

      true ->
        {:ok, tags}
    end
  end

  defp normalize_key(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_key(value), do: value
end
