defmodule Memovee.Memory.TaggingTest do
  use ExUnit.Case, async: true

  alias Memovee.Memory.{Post, Tag, Tagging}

  test "assigns relationships from structs rather than client attributes" do
    post = %Post{id: Ecto.UUID.generate(version: 7)}
    tag = %Tag{id: Ecto.UUID.generate(version: 7)}

    changeset = Tagging.changeset(%Tagging{}, post, tag)

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :post_id) == post.id
    assert Ecto.Changeset.get_field(changeset, :tag_id) == tag.id
  end
end
