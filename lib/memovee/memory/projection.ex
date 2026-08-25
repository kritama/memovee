defmodule Memovee.Memory.Projection do
  @moduledoc """
  Synchronization relationship between a canonical post and a Tama target.
  """

  use Memovee.Schema
  use Eventful.Transitable

  alias Memovee.Memory.Post
  alias __MODULE__.{Event, Transitions}

  Transitions
  |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "memory_projections" do
    field :identifier, :string
    field :tama_space_id, Ecto.UUID
    field :tama_class_id, Ecto.UUID
    field :tama_entity_id, Ecto.UUID
    field :synced_body_hash, :string
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :post, Post
    has_many :events, Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(projection, attrs) do
    projection
    |> cast(attrs, [:identifier, :tama_space_id, :tama_class_id, :metadata])
    |> validate_required([:identifier, :tama_space_id, :tama_class_id, :metadata])
    |> validate_length(:identifier, max: 255)
    |> validate_change(:identifier, fn :identifier, identifier ->
      if String.trim(identifier) == "", do: [identifier: "can't be blank"], else: []
    end)
    |> check_constraint(:identifier, name: :memory_projections_identifier_non_blank)
    |> foreign_key_constraint(:post_id)
    |> unique_constraint([:post_id, :tama_space_id, :tama_class_id],
      name: :memory_projections_post_target_index
    )
    |> unique_constraint([:tama_space_id, :tama_class_id, :identifier],
      name: :memory_projections_target_identifier_index
    )
  end
end
