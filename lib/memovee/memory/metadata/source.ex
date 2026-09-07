defmodule Memovee.Memory.Metadata.Source do
  @moduledoc "Source attribution reported by the submitting agent."
  use Memovee.Schema

  @primary_key false

  embedded_schema do
    field :channel, :string
    field :reference, :string
  end

  def changeset(source, attrs) when is_map(attrs) do
    if Enum.sort(Map.keys(attrs)) == ~w(channel reference) do
      source
      |> cast(attrs, [:channel, :reference], empty_values: [])
      |> validate_required([:channel])
      |> validate_inclusion(:channel, ["agent"])
      |> validate_format(:reference, ~r/^[^\x00]*$/, message: "must not contain NUL characters")
      |> validate_length(:reference, min: 1, max: 512, count: :codepoints)
    else
      source |> change() |> add_error(:base, "must contain only channel and reference")
    end
  end

  def changeset(source, _attrs), do: source |> change() |> add_error(:base, "must be an object")
end
