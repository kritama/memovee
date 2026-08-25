defmodule Memovee.Memory.Tag.Manager do
  @moduledoc """
  Creates, retrieves, and updates memory tags.
  """

  import Ecto.Query

  alias Memovee.Memory.{Post, Tag, Tagging}
  alias Memovee.Repo

  def list, do: Repo.all(from tag in Tag, order_by: [asc: tag.namespace, asc: tag.key])

  def get!(id), do: Repo.get!(Tag, id)

  def get_by_namespace_and_key(namespace, key) do
    Repo.get_by(Tag,
      namespace: normalize_key(namespace),
      key: normalize_key(key)
    )
  end

  def create(attrs) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  def update(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  def change(%Tag{} = tag, attrs \\ %{}), do: Tag.changeset(tag, attrs)

  def list_for_post(%Post{} = post) do
    Tag
    |> join(:inner, [tag], tagging in Tagging, on: tagging.tag_id == tag.id)
    |> where([_tag, tagging], tagging.post_id == ^post.id)
    |> order_by([tag], asc: tag.namespace, asc: tag.key)
    |> Repo.all()
  end

  defp normalize_key(value), do: value |> String.trim() |> String.downcase()
end
