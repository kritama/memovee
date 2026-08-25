defmodule Memovee.Eventful.UUIDv7Test do
  use ExUnit.Case, async: true

  alias Memovee.Eventful.UUIDv7
  alias Memovee.Memory.Projection.Event

  setup do
    {:ok, _} = Application.ensure_all_started(:ecto)
    :ok
  end

  test "autogenerates strictly monotonic UUIDv7 values" do
    ids = for _ <- 1..10, do: UUIDv7.autogenerate()

    assert Enum.all?(ids, &(Ecto.UUID.version(&1) == 7))
    assert Enum.all?(Enum.zip(ids, tl(ids)), fn {left, right} -> left < right end)
  end

  test "configures Eventful event and foreign keys as PostgreSQL UUIDs" do
    assert Event.__schema__(:source) == "memory_projection_events"
    assert Ecto.Type.type(Event.__schema__(:type, :id)) == :uuid
    assert Ecto.Type.type(Event.__schema__(:type, :projection_id)) == :uuid
    assert Ecto.Type.type(Event.__schema__(:type, :actor_id)) == :uuid

    assert {[:id], {UUIDv7, :autogenerate, []}} in Event.__schema__(:autogenerate)
  end
end
