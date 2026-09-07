defmodule Memovee.Memory.Metadata.SourceTest do
  use ExUnit.Case, async: true

  alias Memovee.Memory.Metadata.Source

  test "requires exact source keys and an agent channel" do
    for attrs <- [
          nil,
          [],
          %{},
          %{"channel" => "agent"},
          %{"channel" => "user", "reference" => nil},
          %{"channel" => "agent", "reference" => nil, "extra" => true}
        ] do
      refute Source.changeset(%Source{}, attrs).valid?
    end
  end

  test "distinguishes null references from empty strings" do
    assert Source.changeset(%Source{}, %{"channel" => "agent", "reference" => nil}).valid?
    refute Source.changeset(%Source{}, %{"channel" => "agent", "reference" => ""}).valid?
  end
end
