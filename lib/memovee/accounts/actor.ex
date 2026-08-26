defmodule Memovee.Accounts.Actor do
  @moduledoc """
  Stable account principal used for lifecycle attribution.
  """

  use Memovee.Schema
  use Eventful.Transitable

  alias __MODULE__.{Event, Transitions}

  Transitions
  |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "actors" do
    field :current_state, :string, default: "active"
    field :current_state_version, :integer, default: 0

    has_many :events, Event, foreign_key: :transitioning_actor_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(actor, attrs \\ %{}) do
    cast(actor, attrs, [])
  end
end
