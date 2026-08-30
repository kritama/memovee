defmodule Memovee.OAuth.Grant do
  @moduledoc "An Actor-owned OAuth authorization grant."

  use Memovee.Schema
  use Eventful.Transitable

  alias Memovee.Accounts.Actor
  alias Memovee.OAuth.Access
  alias __MODULE__.{Event, Transitions}

  Transitions
  |> governs(:current_state, on: Event, lock: :current_state_version)

  schema "oauth_grants" do
    field :oauth_client_id, :string
    field :resource, :string
    field :scope, :string
    field :current_state, :string, default: "pending"
    field :current_state_version, :integer, default: 0
    field :last_used_at, :utc_datetime_usec

    belongs_to :actor, Actor
    has_many :oauth_accesses, Access, foreign_key: :oauth_grant_id
    has_many :events, Event, foreign_key: :oauth_grant_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:oauth_client_id, :resource, :scope, :last_used_at])
    |> validate_required([:actor_id, :oauth_client_id, :resource, :scope])
    |> unique_constraint([:actor_id, :oauth_client_id, :resource],
      name: :oauth_grants_active_identity_index
    )
  end
end
