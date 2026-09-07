defmodule Memovee.Memory.Tag.Manager do
  @moduledoc """
  Creates, retrieves, and updates memory tags.
  """

  import Ecto.Query

  alias Memovee.Memory.{Post, Revision, Scope, Tag, Tagging}
  alias Memovee.Repo

  def list(%Scope{} = scope) do
    with {:ok, scope} <- Scope.refresh(scope) do
      {:ok,
       Repo.all(
         from tag in Tag,
           where: tag.owner_actor_id == ^scope.owner.id,
           order_by: [asc: tag.namespace, asc: tag.key]
       )}
    end
  end

  def get(%Scope{} = scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id), {:ok, scope} <- Scope.refresh(scope) do
      case Repo.get_by(Tag, id: id, owner_actor_id: scope.owner.id) do
        nil -> {:error, :not_found}
        tag -> {:ok, tag}
      end
    else
      :error -> {:error, :invalid_id}
      error -> error
    end
  end

  def get_by_namespace_and_key(%Scope{} = scope, namespace, key) do
    with {:ok, scope} <- Scope.refresh(scope) do
      {:ok,
       Repo.get_by(Tag,
         owner_actor_id: scope.owner.id,
         namespace: normalize_key(namespace),
         key: normalize_key(key)
       )}
    end
  end

  def create(%Scope{} = scope, attrs) do
    Repo.transaction(fn ->
      with {:ok, scope} <- Scope.refresh(scope),
           {:ok, tag} <-
             %Tag{owner_actor_id: scope.owner.id} |> Tag.changeset(attrs) |> Repo.insert() do
        tag
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update(%Scope{} = scope, %Tag{} = tag, attrs) do
    Repo.transaction(fn ->
      scope =
        case Scope.refresh(scope) do
          {:ok, refreshed} -> refreshed
          {:error, reason} -> Repo.rollback(reason)
        end

      current =
        Repo.one(
          from row in Tag,
            where: row.id == ^tag.id and row.owner_actor_id == ^scope.owner.id,
            lock: "FOR UPDATE"
        ) || Repo.rollback(:not_found)

      ids =
        Repo.all(
          from tagging in Tagging, where: tagging.tag_id == ^tag.id, select: tagging.post_id
        )

      posts = Revision.lock_posts(ids)
      changeset = Tag.changeset(current, attrs)

      updated =
        case Repo.update(changeset) do
          {:ok, value} -> value
          {:error, error} -> Repo.rollback(error)
        end

      if Enum.any?([:name, :description, :namespace, :key], &Map.has_key?(changeset.changes, &1)),
        do: Revision.bump_posts(scope, posts)

      updated
    end)
  end

  def change(%Tag{} = tag, attrs \\ %{}), do: Tag.changeset(tag, attrs)

  def list_for_post(%Scope{} = scope, %Post{} = post) do
    with {:ok, post} <- Post.Manager.get(scope, post.id) do
      {:ok, tags_for_post(post)}
    end
  end

  defp tags_for_post(post) do
    Tag
    |> join(:inner, [tag], tagging in Tagging, on: tagging.tag_id == tag.id)
    |> where([_tag, tagging], tagging.post_id == ^post.id)
    |> order_by([tag], asc: tag.namespace, asc: tag.key)
    |> Repo.all()
  end

  defp normalize_key(value), do: value |> String.trim() |> String.downcase()
end
