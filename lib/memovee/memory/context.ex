defmodule Memovee.Memory.Context do
  @moduledoc "Validated identity and source context supplied by the trusted Tama service."
  use Memovee.Schema

  @primary_key false
  @fields [:actor_id, :origin_identifier]

  embedded_schema do
    field :actor_id, Ecto.UUID
    field :origin_identifier, :string
  end

  def changeset(context, attrs) when is_map(attrs) do
    keys = Map.keys(attrs)

    if Enum.all?(keys, &(&1 in @fields)) or
         Enum.all?(keys, &(&1 in ~w(actor_id origin_identifier))) do
      context
      |> cast(attrs, @fields)
      |> validate_required(@fields)
      |> validate_length(:origin_identifier, max: 512, count: :codepoints)
      |> validate_format(:origin_identifier, ~r/^[^\x00]*$/,
        message: "must not contain NUL characters"
      )
    else
      context |> change() |> add_error(:base, "contains unexpected fields")
    end
  end

  def changeset(context, _attrs) do
    context |> change() |> add_error(:base, "must be an object")
  end
end
