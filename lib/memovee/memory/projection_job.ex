defmodule Memovee.Memory.ProjectionJob do
  @moduledoc "Durable work for the memory search projection, separate from Tama synchronization."
  use Memovee.Schema
  use Eventful.Transitable
  alias __MODULE__.{Event, Transitions}
  Transitions |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "memory_projection_jobs" do
    belongs_to :owner_actor, Memovee.Accounts.Actor
    belongs_to :post, Memovee.Memory.Post
    field :revision, :integer
    field :fingerprint, :string
    field :profile, :string, default: "memory-v1"
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    field :attempts, :integer, default: 0
    field :available_at, :utc_datetime_usec
    field :lease_token, Ecto.UUID
    field :lease_expires_at, :utc_datetime_usec
    field :description, :string
    field :chunks, {:array, :map}
    field :last_error, :map
    field :indexed_at, :utc_datetime_usec
    has_many :events, Event
    timestamps(type: :utc_datetime)
  end
end
