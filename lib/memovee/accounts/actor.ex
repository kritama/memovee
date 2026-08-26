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
    field :type, Ecto.Enum, values: [:user, :agent]
    field :identifier, :string
    field :current_state, :string, default: "active"
    field :current_state_version, :integer, default: 0

    has_one :user, Memovee.Accounts.User
    has_many :tokens, Memovee.Accounts.Token
    has_many :relationships, Memovee.Accounts.Relationship

    has_many :targeted_relationships, Memovee.Accounts.Relationship, foreign_key: :target_actor_id

    has_many :events, Event, foreign_key: :transitioning_actor_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(actor, attrs \\ %{}) do
    cast(actor, attrs, [])
  end

  @doc false
  def user_changeset(actor) do
    actor
    |> cast(%{}, [])
    |> put_change(:type, :user)
    |> put_change(:identifier, nil)
  end

  @doc false
  def agent_changeset(actor, attrs) do
    actor
    |> cast(attrs, [:identifier])
    |> update_change(:identifier, &normalize_identifier/1)
    |> put_change(:type, :agent)
    |> validate_required([:identifier])
    |> validate_length(:identifier, max: 160)
    |> unique_constraint(:identifier)
    |> check_constraint(:identifier, name: :actors_identifier_by_type_check)
  end

  defp normalize_identifier(identifier) do
    identifier
    |> String.trim()
    |> String.downcase()
  end
end
