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

  test "source identifiers are assigned by trusted code, never cast from input" do
    post = %Post{origin_identifier: "trusted:source"}
    changeset = Post.changeset(post, %{"body" => "source", "origin_identifier" => "forged"})
    assert Ecto.Changeset.get_field(changeset, :origin_identifier) == "trusted:source"
  end

  test "UTF-8 byte limits preserve exact text" do
    assert Post.changeset(%Post{}, %{"body" => String.duplicate("🙂", 8192)}).valid?

    refute Post.changeset(%Post{}, %{"body" => String.duplicate("🙂", 8193)}).valid?

    refute Post.changeset(%Post{}, %{"body" => String.duplicate("a", 32_769)}).valid?
  end

  test "reserved metadata keys are rejected at any nesting depth" do
    for key <-
          ~w(owner_actor_id actor_id created_by_actor_id current_state current_state_version origin_identifier) do
      attrs = %{"body" => "source", "metadata" => %{"nested" => [%{key => "forged"}]}}
      refute Post.changeset(%Post{}, attrs).valid?
    end

    assert Post.changeset(%Post{}, %{
             "body" => "source",
             "metadata" => %{"arbitrary" => [1, true, nil]}
           }).valid?
  end
end
