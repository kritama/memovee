defmodule Memovee.Memory.Post.Manager do
  @moduledoc """
  Creates, retrieves, and updates canonical memory posts.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Memovee.Accounts.Actor
  alias Memovee.Memory.{Post, Projection}
  alias Memovee.Repo

  def list, do: Repo.all(from post in Post, order_by: [desc: post.id])

  def get!(id), do: Repo.get!(Post, id)

  def create(attrs) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  def update(%Actor{} = actor, %Post{} = post, attrs) do
    Multi.new()
    |> Multi.update(:post, Post.changeset(post, attrs))
    |> Multi.run(:projections, fn _repo, %{post: updated_post} ->
      if updated_post.body_hash == post.body_hash do
        {:ok, []}
      else
        Projection.Manager.invalidate_for_post(actor, updated_post)
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{post: updated_post}} -> {:ok, updated_post}
      {:error, :post, changeset, _changes} -> {:error, changeset}
      {:error, :projections, error, _changes} -> {:error, error}
    end
  end

  def change(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)
end
