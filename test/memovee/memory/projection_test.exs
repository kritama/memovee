defmodule Memovee.Memory.ProjectionTest do
  use ExUnit.Case, async: true

  alias Memovee.Accounts.Actor
  alias Memovee.Memory.Projection

  test "casts target identity without permitting lifecycle or remote result updates" do
    space_id = Ecto.UUID.generate(version: 7)
    class_id = Ecto.UUID.generate(version: 7)

    changeset =
      Projection.changeset(%Projection{}, %{
        "identifier" => "post-id",
        "tama_space_id" => space_id,
        "tama_class_id" => class_id,
        "tama_entity_id" => Ecto.UUID.generate(version: 7),
        "synced_body_hash" => String.duplicate("a", 64),
        "current_state" => "synced",
        "current_state_version" => 99
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :current_state) == "pending"
    assert Ecto.Changeset.get_field(changeset, :current_state_version) == 0
    assert is_nil(Ecto.Changeset.get_field(changeset, :tama_entity_id))
    assert is_nil(Ecto.Changeset.get_field(changeset, :synced_body_hash))
  end

  test "declares the Eventful projection state graph" do
    assert Enum.sort(Projection.Transitions.valid_states()) ==
             ~w(failed pending synced syncing)

    pending_events = Projection.Transitions.possible_events(%Projection{current_state: "pending"})

    assert [%{from: "pending", to: "syncing", via: "sync"}] = pending_events
  end

  test "rejects invalid completion parameters" do
    projection = %Projection{current_state: "syncing"}

    assert {:error,
            %Eventful.Error{
              code: :invalid_transition_parameters,
              message: :invalid_tama_entity_id
            }} = Projection.Manager.complete(%Actor{}, projection, "invalid", "invalid")
  end
end
