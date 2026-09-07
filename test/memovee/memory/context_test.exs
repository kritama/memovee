defmodule Memovee.Memory.ContextTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Memovee.Memory.Context

  @actor_id "01990000-0000-7000-8000-000000000001"

  test "casts context without changing the source identifier" do
    attrs = %{"actor_id" => @actor_id, "origin_identifier" => " message:1 "}

    assert {:ok, context} =
             %Context{} |> Context.changeset(attrs) |> Changeset.apply_action(:validate)

    assert context.actor_id == @actor_id
    assert context.origin_identifier == " message:1 "
  end

  test "rejects missing fields, invalid UUIDs and blank identifiers" do
    for attrs <- [
          %{},
          %{actor_id: "invalid", origin_identifier: "message:1"},
          %{actor_id: @actor_id, origin_identifier: " \n\t "},
          %{actor_id: @actor_id, origin_identifier: nil}
        ] do
      refute Context.changeset(%Context{}, attrs).valid?
    end
  end

  test "rejects non-object contexts and unexpected fields instead of ignoring them" do
    for attrs <- [
          nil,
          [],
          "context",
          %{
            "actor_id" => @actor_id,
            "origin_identifier" => "message:1",
            "owner_actor_id" => @actor_id
          }
        ] do
      refute Context.changeset(%Context{}, attrs).valid?
    end
  end
end
