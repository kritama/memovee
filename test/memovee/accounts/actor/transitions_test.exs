defmodule Memovee.Accounts.Actor.TransitionsTest do
  use Memovee.DataCase, async: true

  alias Memovee.Accounts
  alias Memovee.Accounts.Actor

  test "deactivates and reactivates an actor with attributed events" do
    assert {:ok, performing_actor} = Accounts.create_actor()
    assert {:ok, transitioning_actor} = Accounts.create_actor()

    assert {:ok, %{event: deactivated_event, resource: deactivated_actor}} =
             Accounts.deactivate_actor(performing_actor, transitioning_actor)

    assert deactivated_event.transitioning_actor_id == transitioning_actor.id
    assert deactivated_event.actor_id == performing_actor.id
    assert deactivated_event.id |> Ecto.UUID.cast!() |> Ecto.UUID.version() == 7
    assert deactivated_actor.current_state == "inactive"
    assert deactivated_actor.current_state_version == 1

    assert {:ok, %{event: activated_event, resource: activated_actor}} =
             Accounts.activate_actor(performing_actor, deactivated_actor)

    assert activated_event.transitioning_actor_id == transitioning_actor.id
    assert activated_event.actor_id == performing_actor.id
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
end
