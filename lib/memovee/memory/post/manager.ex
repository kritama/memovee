defmodule Memovee.Memory.Post.Manager do
  @moduledoc """
  Creates, retrieves, and updates canonical memory posts.
  """

  import Ecto.Query, only: [from: 2]

  alias Memovee.Accounts.Actor
  alias Memovee.Memory.{Post, Projection, Scope}
  alias Memovee.Projections.Search
  alias Memovee.Repo

  def list(%Scope{} = scope) do
    with {:ok, scope} <- Scope.refresh(scope) do
      {:ok,
       Repo.all(
         from post in Post,
           where: post.owner_actor_id == ^scope.owner.id,
           order_by: [desc: post.id]
       )}
    end
  end

  def get(%Scope{} = scope, id) do
    with {:ok, id} <- Ecto.UUID.cast(id), {:ok, scope} <- Scope.refresh(scope) do
      case Repo.get_by(Post, id: id, owner_actor_id: scope.owner.id) do
        nil -> {:error, :not_found}
        post -> {:ok, post}
      end
    else
      :error -> {:error, :invalid_id}
      error -> error
    end
  end

  def update(%Actor{} = actor, %Post{} = post, attrs) do
    Repo.transaction(fn ->
      current = Repo.one!(from row in Post, where: row.id == ^post.id, lock: "FOR UPDATE")

      authorize_update!(actor, current)

      changeset = Post.changeset(current, attrs)

      updated = unwrap(Repo.update(changeset))
      invalidate_sync(actor, current, updated)

      if Enum.any?([:title, :body, :metadata], &Map.has_key?(changeset.changes, &1)),
        do: unwrap(Search.Manager.bump(updated)),
        else: updated
    end)
  end

  defp authorize_update!(actor, post) do
    case Scope.resolve(actor, %{}) do
      {:ok, %{owner: %{id: owner_id}}} when owner_id == post.owner_actor_id -> :ok
      _ -> Repo.rollback(:not_found)
    end
  end

  defp invalidate_sync(actor, current, updated) do
    if updated.body_hash != current.body_hash,
      do: unwrap(Projection.Manager.invalidate_for_post(actor, updated))
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, error}), do: Repo.rollback(error)

  def change(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)
end
