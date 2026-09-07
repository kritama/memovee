defmodule Memovee.Memory.Candidate do
  @moduledoc "Validates persisted memory values without trusting generated identity or lifecycle fields."
  alias Memovee.Memory.Metadata

  @reserved ~w(owner_actor_id actor_id created_by_actor_id current_state current_state_version origin_identifier)
  @tag_keys ~w(namespace key name description metadata)

  def validate(attrs, graph?) when is_map(attrs) do
    metadata = Map.get(attrs, "metadata", %{})

    with true <- is_map(metadata) and not reserved?(metadata),
         true <-
           not graph? or
             (Metadata.changeset(%Metadata{}, metadata).valid? and
                Enum.all?(~w(title body metadata tags), &Map.has_key?(attrs, &1))),
         true <- valid_post?(attrs),
         {:ok, tags} <- tags(Map.get(attrs, "tags", []), metadata, graph?) do
      {:ok, {Map.take(attrs, ~w(title body)) |> Map.put("metadata", metadata), tags}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_candidate}
    end
  end

  def reserved?(value) when is_map(value) do
    Enum.any?(value, fn {key, child} -> to_string(key) in @reserved or reserved?(child) end)
  end

  def reserved?(value) when is_list(value), do: Enum.any?(value, &reserved?/1)
  def reserved?(_), do: false

  defp valid_post?(attrs) do
    body = attrs["body"]
    title = attrs["title"]

    is_binary(body) and String.valid?(body) and String.trim(body) != "" and
      byte_size(body) <= 32_768 and
      (is_nil(title) or (is_binary(title) and String.length(title) in 1..255))
  end

  defp tags(values, metadata, graph?) when is_list(values) do
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

  defp tags(_, _, _), do: {:error, :invalid_tags}

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
    metadata = Map.get(tag, "metadata", %{})
    description = tag["description"]

    if Enum.all?(Map.keys(tag), &(&1 in @tag_keys)) and namespace in ~w(kind project topic tool) and
         valid_key?(key) and valid_name?(name) and valid_tag_metadata?(metadata, description) do
      {:ok, tag |> Map.put("namespace", namespace) |> Map.put("key", key)}
    else
      {:error, :invalid_tags}
    end
  end

  defp normalize_tag(_), do: {:error, :invalid_tags}

  defp valid_key?(key),
    do:
      is_binary(key) and String.length(key) <= 100 and
        Regex.match?(~r/\A[a-z0-9][a-z0-9._-]*\z/, key)

  defp valid_name?(name), do: String.trim(name) != "" and String.length(name) <= 255

  defp valid_tag_metadata?(metadata, description),
    do:
      is_map(metadata) and not reserved?(metadata) and
        (is_nil(description) or is_binary(description))

  defp generated_key(name) do
    key =
      name
      |> String.downcase()
      |> String.replace("/", ".")
      |> String.replace(~r/[^a-z0-9._-]+/, "-")
      |> String.trim_leading(".")

    key = key |> String.replace(~r/\A[._-]+|[._-]+\z/, "") |> String.slice(0, 100)
    if key == "", do: "tag-" <> String.slice(hash(name), 0, 12), else: key
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

  def hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
