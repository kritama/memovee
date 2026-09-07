defmodule Memovee.Memory.Tagging.Manager do
  @moduledoc "Maintains owner-consistent tag assignments and indexing revisions atomically."
  import Ecto.Query
  alias Memovee.Memory.{Post, Revision, Scope, Tag, Tagging}
  alias Memovee.Repo

  def create(%Scope{} = scope, %Post{} = post, %Tag{} = tag) do
    Repo.transaction(fn ->
      {post, tag} = lock_records(scope, post, tag)

      if Repo.aggregate(from(row in Tagging, where: row.post_id == ^post.id), :count) >= 12,
        do: Repo.rollback(:tag_limit)

      tagging =
        case %Tagging{} |> Tagging.changeset(post, tag) |> Repo.insert() do
          {:ok, value} -> value
          {:error, error} -> Repo.rollback(error)
        end

      Revision.bump_posts([post])
      tagging
    end)
  end

  def delete(%Scope{} = scope, %Post{} = post, %Tag{} = tag) do
    Repo.transaction(fn ->
      {post, tag} = lock_records(scope, post, tag)

      {count, _} =
        Repo.delete_all(
          from tagging in Tagging,
            where: tagging.post_id == ^post.id and tagging.tag_id == ^tag.id
        )

      if count > 0, do: Revision.bump_posts([post])
      {count, nil}
    end)
    |> case do
      {:ok, result} -> result
      error -> error
    end
  end

  defp lock_records(scope, post, tag) do
    scope =
      case Scope.refresh(scope) do
        {:ok, refreshed} -> refreshed
        {:error, reason} -> Repo.rollback(reason)
      end

    tag =
      Repo.one(
        from row in Tag,
          where: row.id == ^tag.id and row.owner_actor_id == ^scope.owner.id,
          lock: "FOR UPDATE"
      ) || Repo.rollback(:not_found)

    post =
      Repo.one(
        from row in Post,
          where: row.id == ^post.id and row.owner_actor_id == ^scope.owner.id,
          lock: "FOR UPDATE"
      ) || Repo.rollback(:not_found)

    {post, tag}
  end
end
