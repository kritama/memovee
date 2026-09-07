defmodule Memovee.Memory.MetadataTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Memovee.Memory.Metadata

  setup do
    post =
      File.read!("tama/graph/schemas/memory-fixtures.v1.json")
      |> Jason.decode!()
      |> get_in(["extraction", Access.at(0), "expected", "post"])

    %{post: post, metadata: post["metadata"]}
  end

  test "accepts nullable values and an empty reference list", %{metadata: metadata} do
    assert Metadata.changeset(%Metadata{}, metadata).valid?
  end

  test "rejects invalid field types, enums and reference lists", %{metadata: metadata} do
    for {key, value} <- [
          {"kind", "unknown"},
          {"epistemic_status", "certain"},
          {"approval", "approved"},
          {"occurred_at", "2026-09-07"},
          {"effective_at", ""},
          {"source", nil},
          {"source", []},
          {"derived_from_post_ids", nil},
          {"derived_from_post_ids", ["invalid"]},
          {"derived_from_post_ids", List.duplicate("01990000-0000-7000-8000-000000000001", 2)}
        ] do
      refute Metadata.changeset(%Metadata{}, Map.put(metadata, key, value)).valid?
    end
  end

  test "requires all metadata keys and rejects unknown fields", %{metadata: metadata} do
    for key <- Map.keys(metadata) do
      refute Metadata.changeset(%Metadata{}, Map.delete(metadata, key)).valid?
    end

    refute Metadata.changeset(%Metadata{}, Map.put(metadata, "extra", true)).valid?
  end

  test "retains original timestamp text when casting", %{metadata: metadata} do
    timestamp = "2026-09-07T12:00:00+07:00"
    attrs = Map.put(metadata, "occurred_at", timestamp)

    assert {:ok, metadata} =
             %Metadata{} |> Metadata.changeset(attrs) |> Changeset.apply_action(:validate)

    assert metadata.occurred_at == timestamp
  end
end
