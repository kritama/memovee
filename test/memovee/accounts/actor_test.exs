defmodule Memovee.Accounts.ActorTest do
  use ExUnit.Case, async: true

  alias Memovee.Accounts.Actor

  test "actors are active credential-neutral principals" do
    changeset =
      Actor.changeset(%Actor{}, %{
        "current_state" => "inactive",
        "current_state_version" => 99
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :current_state) == "active"
    assert Ecto.Changeset.get_field(changeset, :current_state_version) == 0
    refute Ecto.Changeset.get_change(changeset, :current_state)
    refute Ecto.Changeset.get_change(changeset, :current_state_version)
  end
end
