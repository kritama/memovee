defmodule Memovee.Accounts.Actor do
  @moduledoc """
  Stable account principal used for lifecycle attribution.
  """

  use Memovee.Schema

  @states ~w(active inactive)

  schema "actors" do
    field :current_state, :string, default: "active"

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(actor, attrs \\ %{}) do
    actor
    |> cast(attrs, [])
    |> validate_required([:current_state])
    |> validate_inclusion(:current_state, @states)
    |> check_constraint(:current_state, name: :actors_current_state_check)
  end
end
