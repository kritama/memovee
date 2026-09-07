defmodule Memovee.Memory.Metadata do
  @moduledoc "Structured provenance and classification for a memory candidate."
  use Memovee.Schema

  alias __MODULE__.Source

  @reserved ~w(owner_actor_id actor_id created_by_actor_id current_state current_state_version origin_identifier)
  @primary_key false
  @fields [
    :kind,
    :epistemic_status,
    :approval,
    :occurred_at,
    :effective_at,
    :derived_from_post_ids
  ]
  @keys ~w(kind epistemic_status approval source occurred_at effective_at derived_from_post_ids)

  embedded_schema do
    field :kind, :string
    field :epistemic_status, :string
    field :approval, :string
    field :occurred_at, :string
    field :effective_at, :string
    field :derived_from_post_ids, {:array, Ecto.UUID}
    embeds_one :source, Source
  end

  def changeset(metadata, attrs) when is_map(attrs) do
    if Enum.sort(Map.keys(attrs)) == Enum.sort(@keys) do
      metadata
      |> cast(attrs, @fields, empty_values: [])
      |> cast_embed(:source, required: true)
      |> validate_required([:kind, :epistemic_status, :approval])
      |> validate_inclusion(:kind, ~w(fact preference decision brief progress review procedure))
      |> validate_inclusion(
        :epistemic_status,
        ~w(user_stated observed proposed inferred reported)
      )
      |> validate_inclusion(:approval, ~w(unspecified proposed reported_approved))
      |> validate_change(:occurred_at, &validate_timestamp/2)
      |> validate_change(:effective_at, &validate_timestamp/2)
      |> validate_length(:derived_from_post_ids, max: 20)
      |> validate_references()
    else
      metadata |> change() |> add_error(:base, "must contain exactly the metadata fields")
    end
  end

  def changeset(metadata, _attrs),
    do: metadata |> change() |> add_error(:base, "must be an object")

  def reserved?(value) when is_map(value) do
    Enum.any?(value, fn {key, child} -> to_string(key) in @reserved or reserved?(child) end)
  end

  def reserved?(value) when is_list(value), do: Enum.any?(value, &reserved?/1)
  def reserved?(_), do: false

  defp validate_timestamp(field, value) do
    case DateTime.from_iso8601(value) do
      {:ok, _, _} -> []
      _ -> [{field, "must be an RFC3339 timestamp"}]
    end
  end

  defp validate_references(changeset) do
    case get_field(changeset, :derived_from_post_ids) do
      nil ->
        add_error(changeset, :derived_from_post_ids, "must be a list")

      ids ->
        if Enum.uniq(ids) == ids,
          do: changeset,
          else: add_error(changeset, :derived_from_post_ids, "must contain unique IDs")
    end
  end
end
