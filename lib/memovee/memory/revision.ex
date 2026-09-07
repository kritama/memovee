defmodule Memovee.Memory.Revision do
  @moduledoc false
  import Ecto.Query
  alias Memovee.Memory.Post
  alias Memovee.Projections.Indexing
  alias Memovee.Repo

  def lock_posts(ids) do
    Repo.all(from post in Post, where: post.id in ^ids, order_by: post.id, lock: "FOR UPDATE")
  end

  def bump_posts(posts) do
    Enum.each(posts, fn post ->
      case Indexing.Manager.bump(post) do
        {:ok, _} -> :ok
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end
end
