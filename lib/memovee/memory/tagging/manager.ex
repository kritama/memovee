defmodule Memovee.Memory.Tagging.Manager do
  @moduledoc "Maintains owner-consistent tag assignments and indexing revisions atomically."
  import Ecto.Query
  alias Memovee.Memory.{Post, Revision, Tag, Tagging}
  alias Memovee.Repo

  def create(%Post{} = post, %Tag{} = tag) do
    Repo.transaction(fn ->
      {post, tag} = lock_records(post, tag)

      tagging =
        case %Tagging{} |> Tagging.changeset(post, tag) |> Repo.insert() do
          {:ok, value} -> value
          {:error, error} -> Repo.rollback(error)
        end

      Revision.bump_posts([post])
      tagging
    end)
  end

  def delete(%Post{} = post, %Tag{} = tag) do
    Repo.transaction(fn ->
      {post, tag} = lock_records(post, tag)

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

  defp lock_records(post, tag) do
    tag = Repo.one!(from row in Tag, where: row.id == ^tag.id, lock: "FOR UPDATE")
    [post] = Revision.lock_posts([post.id])
    if post.owner_actor_id != tag.owner_actor_id, do: Repo.rollback(:owner_mismatch)
    {post, tag}
  end
end
