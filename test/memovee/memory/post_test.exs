defmodule Memovee.Memory.PostTest do
  use ExUnit.Case, async: true

  alias Memovee.Memory.Post

  test "preserves canonical body text and derives its hash" do
    body = "  Dense memory text.\n"
    changeset = Post.changeset(%Post{}, %{"body" => body})

    expected_hash =
      :sha256
      |> :crypto.hash(body)
      |> Base.encode16(case: :lower)

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :body) == body
    assert Ecto.Changeset.get_change(changeset, :body_hash) == expected_hash
    assert Ecto.Changeset.get_field(changeset, :metadata) == %{}
  end

  test "rejects whitespace-only bodies" do
    changeset = Post.changeset(%Post{}, %{"body" => " \n\t "})

    refute changeset.valid?
    assert {"can't be blank", _options} = changeset.errors[:body]
  end
end
