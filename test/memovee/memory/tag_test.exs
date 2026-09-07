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

  test "generated keys, explicit keys and normalized deduplication" do
    attrs = %{
      "body" => "source",
      "tags" => [
        %{"namespace" => " Tool ", "name" => "Org/Tool Name"},
        %{"namespace" => "project", "key" => " Kritama.Memovee ", "name" => "Memovee"},
        %{"namespace" => "project", "key" => "kritama.memovee", "name" => "Duplicate"},
        %{"namespace" => "topic", "name" => "🙂"}
      ]
    }

    assert {:ok, tags} = Tag.prepare(attrs["tags"], %{}, false)
    assert length(tags) == 3
    assert Enum.any?(tags, &(&1["key"] == "org.tool-name"))
    assert Enum.any?(tags, &(&1["key"] == "kritama.memovee"))

    expected =
      "tag-" <> String.slice(:crypto.hash(:sha256, "🙂") |> Base.encode16(case: :lower), 0, 12)

    assert Enum.any?(tags, &(&1["key"] == expected))
  end

  test "preparation rejects invalid tag attributes through the changeset" do
    for attrs <- [
          %{"namespace" => "tool", "key" => nil, "name" => "Req"},
          %{"namespace" => "tool", "key" => "req", "name" => " "},
          %{
            "namespace" => "tool",
            "key" => "req",
            "name" => "Req",
            "metadata" => %{"actor_id" => "forged"}
          }
        ] do
      assert {:error, :invalid_tags} = Tag.prepare([attrs], %{}, false)
    end
  end

  test "rejects NUL in display text and nested metadata" do
    for attrs <- [
          %{name: "bad\u0000name"},
          %{description: "bad\u0000description"},
          %{metadata: %{"nested" => [%{"value" => "bad\u0000value"}]}},
          %{metadata: %{"nested" => [%{"bad\u0000key" => nil}]}}
        ] do
      attrs = Map.merge(%{namespace: "topic", key: "elixir", name: "Elixir"}, attrs)
      refute Tag.changeset(%Tag{}, attrs).valid?
    end
  end

  test "name limits count Unicode code points" do
    attrs = %{namespace: "topic", key: "elixir"}

    for name <- [String.duplicate("😀", 255), String.duplicate("e\u0301", 127) <> "e"] do
      assert Tag.changeset(%Tag{}, Map.put(attrs, :name, name)).valid?
    end

    refute Tag.changeset(%Tag{}, Map.put(attrs, :name, String.duplicate("e\u0301", 128))).valid?
  end
end
