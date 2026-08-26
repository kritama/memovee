defmodule Memovee.Accounts.Actor.TransitionsTest do
  use Memovee.DataCase, async: true

  import Memovee.AccountsFixtures

  alias Memovee.Accounts
  alias Memovee.Accounts.Actor

  test "deactivates and reactivates an actor with attributed events" do
    performing_actor = user_fixture().actor
    transitioning_actor = user_fixture().actor

    assert {:ok, %{event: deactivated_event, resource: deactivated_actor}} =
             Accounts.transition_actor(performing_actor, transitioning_actor, :deactivate)

    assert deactivated_event.transitioning_actor_id == performing_actor.id
    assert deactivated_event.actor_id == transitioning_actor.id
    assert deactivated_event.id |> Ecto.UUID.cast!() |> Ecto.UUID.version() == 7
    assert deactivated_actor.current_state == "inactive"
    assert deactivated_actor.current_state_version == 1

    assert {:ok, %{event: activated_event, resource: activated_actor}} =
             Accounts.transition_actor(deactivated_actor, transitioning_actor, :activate)

    assert activated_event.transitioning_actor_id == performing_actor.id
    assert activated_event.actor_id == transitioning_actor.id
    assert activated_actor.current_state == "active"
    assert activated_actor.current_state_version == 2
  end

  test "declares only the supported actor state transitions" do
    assert Actor.Transitions.valid_states() |> Enum.sort() == ~w(active inactive)

    assert [%{from: "active", to: "inactive", via: "deactivate"}] =
             Actor.Transitions.possible_events(%Actor{current_state: "active"})

    assert [%{from: "inactive", to: "active", via: "activate"}] =
             Actor.Transitions.possible_events(%Actor{current_state: "inactive"})
  end

  test "returns an error for an unsupported transition event" do
    actor = user_fixture().actor
    transitioning_actor = user_fixture().actor

    assert {:error, %Eventful.Error{code: :invalid_transition_event}} =
             Accounts.transition_actor(actor, transitioning_actor, :archive)
  end
end
