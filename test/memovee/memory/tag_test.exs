defmodule Memovee.Memory.TagTest do
  use ExUnit.Case, async: true

  alias Memovee.Memory.Tag

  test "normalizes namespace and key while retaining the display name" do
    changeset =
      Tag.changeset(%Tag{}, %{
        "namespace" => " Project ",
        "key" => " Memovee.Core ",
        "name" => "Memovee Core"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :namespace) == "project"
    assert Ecto.Changeset.get_change(changeset, :key) == "memovee.core"
    assert Ecto.Changeset.get_change(changeset, :name) == "Memovee Core"
  end

  test "rejects invalid machine keys" do
    changeset =
      Tag.changeset(%Tag{}, %{
        "namespace" => "topic names",
        "key" => "elixir",
        "name" => "Elixir"
      })

    refute changeset.valid?
    assert {"has invalid format", _options} = changeset.errors[:namespace]
  end
end
