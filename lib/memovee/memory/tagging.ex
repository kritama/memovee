defmodule Memovee.Memory.Tagging do
  @moduledoc """
  Assignment of a tag to a memory post.
  """

  use Memovee.Schema

  alias Memovee.Memory.{Post, Tag}

  schema "memory_taggings" do
    belongs_to :post, Post
    belongs_to :tag, Tag

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(tagging, %Post{} = post, %Tag{} = tag) do
    tagging
    |> change()
    |> put_change(:post_id, post.id)
    |> put_change(:tag_id, tag.id)
    |> validate_owner(post, tag)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:tag_id)
    |> unique_constraint([:post_id, :tag_id], name: :memory_taggings_post_id_tag_id_index)
  end

  defp validate_owner(changeset, post, tag) do
    if post.owner_actor_id == tag.owner_actor_id,
      do: changeset,
      else: add_error(changeset, :tag_id, "must belong to the same owner")
  end
end
