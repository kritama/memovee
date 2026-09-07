defmodule Memovee.Memory.Post.Manager do
  @moduledoc """
  Creates, retrieves, and updates canonical memory posts.
  """

  import Ecto.Query, only: [from: 2]

  alias Memovee.Accounts.Actor
  alias Memovee.Memory.{Candidate, Post, Projection, Scope, Tag, Tagging}
  alias Memovee.Projections
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

  def create(%Scope{} = scope, attrs) do
    Repo.transaction(fn ->
      scope = unwrap(Scope.refresh(scope))
      origin = if scope.service?, do: scope.origin_identifier
      lock_origin(scope.owner.id, origin)

      case existing_post(scope.owner.id, origin) do
        nil -> persist(scope, origin, attrs)
        post -> saved(post, true)
      end
    end)
  end

  defp lock_origin(_owner_id, nil), do: :ok

  defp lock_origin(owner_id, origin) do
    # Serialize absent-row creation too; the unique index remains the final invariant.
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      owner_id <> ":" <> origin
    ])
  end

  defp existing_post(_owner_id, nil), do: nil

  defp existing_post(owner_id, origin) do
    Repo.one(
      from post in Post,
        where: post.owner_actor_id == ^owner_id and post.origin_identifier == ^origin,
        lock: "FOR UPDATE"
    )
  end

  defp persist(scope, origin, attrs) do
    {post_attrs, tags} = unwrap(Candidate.validate(attrs, scope.service?))
    authorize_references!(scope, post_attrs["metadata"])

    post =
      %Post{
        owner_actor_id: scope.owner.id,
        created_by_actor_id: scope.actor.id,
        origin_identifier: origin
      }
      |> Post.changeset(post_attrs)
      |> Repo.insert()
      |> unwrap()

    Enum.each(tags, &attach_tag(post, &1))
    unwrap(Projections.create_pending_indexing(post))
    saved(post, false)
  end

  defp attach_tag(post, attrs) do
    %Tag{owner_actor_id: post.owner_actor_id}
    |> Tag.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:owner_actor_id, :namespace, :key])
    |> unwrap()

    tag =
      Repo.one!(
        from tag in Tag,
          where:
            tag.owner_actor_id == ^post.owner_actor_id and tag.namespace == ^attrs["namespace"] and
              tag.key == ^attrs["key"],
          lock: "FOR SHARE"
      )

    unwrap(%Tagging{} |> Tagging.changeset(post, tag) |> Repo.insert())
  end

  defp saved(post, replayed) do
    projection = Projections.get_post_indexing!(post)

    tag_ids =
      Repo.all(
        from tagging in Tagging,
          where: tagging.post_id == ^post.id,
          order_by: tagging.tag_id,
          select: tagging.tag_id
      )

    receipt = %{
      post_id: post.id,
      body_hash: post.body_hash,
      tag_ids: tag_ids,
      indexing_status: projection.current_state,
      replayed: replayed
    }

    %{post: post, receipt: receipt, replayed: replayed}
  end

  defp authorize_references!(scope, metadata) do
    ids = Map.get(metadata, "derived_from_post_ids", [])

    if scope.service? and ids != [] do
      count =
        Repo.aggregate(
          from(post in Post,
            where: post.id in ^ids and post.owner_actor_id == ^scope.owner.id
          ),
          :count
        )

      if count != length(ids), do: Repo.rollback(:invalid_candidate)
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
        do: unwrap(Projections.bump_indexing_revision(updated)),
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
