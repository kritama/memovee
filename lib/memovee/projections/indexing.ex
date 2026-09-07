defmodule Memovee.Projections.Indexing do
  @moduledoc "Durable memory indexing state and artifacts; Oban owns work scheduling and retries."
  use Memovee.Schema
  use Eventful.Transitable
  alias __MODULE__.{Event, Transitions}
  Transitions |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "projections_indexings" do
    belongs_to :owner_actor, Memovee.Accounts.Actor
    belongs_to :post, Memovee.Memory.Post
    field :revision, :integer
    field :fingerprint, :string
    field :profile, :string, default: "memory-v1"
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    # Opaque fencing token for future graph callbacks, not a queue lease.
    field :lease_token, Ecto.UUID
    field :description, :string
    field :chunks, {:array, :map}
    field :last_error, :map
    field :indexed_at, :utc_datetime_usec
    has_many :events, Event
    timestamps(type: :utc_datetime)
  end
end
