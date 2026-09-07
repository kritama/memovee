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

  test "body limits count Unicode code points" do
    assert Post.changeset(%Post{}, %{"body" => String.duplicate("🙂", 32_768)}).valid?

    refute Post.changeset(%Post{}, %{"body" => String.duplicate("🙂", 32_769)}).valid?

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

  test "rejects NUL in text and nested metadata strings or keys" do
    for attrs <- [
          %{"title" => "bad\u0000title"},
          %{"body" => "bad\u0000body"},
          %{"metadata" => %{"nested" => [%{"value" => "bad\u0000value"}]}},
          %{"metadata" => %{"nested" => [%{"bad\u0000key" => true}]}}
        ] do
      refute Post.changeset(%Post{}, Map.merge(%{"body" => "source"}, attrs)).valid?
    end
  end

  test "title limits count Unicode code points" do
    for title <- [String.duplicate("😀", 255), String.duplicate("e\u0301", 127) <> "e"] do
      assert Post.changeset(%Post{}, %{body: "source", title: title}).valid?
    end

    refute Post.changeset(%Post{}, %{body: "source", title: String.duplicate("e\u0301", 128)}).valid?
  end
end
