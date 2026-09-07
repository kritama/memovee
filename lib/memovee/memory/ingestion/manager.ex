defmodule Memovee.Memory.Ingestion.Manager do
  @moduledoc "Serializes source submissions and atomic memory saves by owner and origin."
  import Ecto.Query
  alias Ecto.{Changeset, Multi}
  alias Memovee.Memory.{Candidate, Ingestion, Post, ProjectionJob, Scope, Tag, Tagging}
  alias Memovee.Repo

  def open(%Scope{service?: true} = scope, content) when is_binary(content) do
    transaction(fn ->
      scope = unwrap(Scope.refresh(scope))
      ingestion = open_locked(scope, content)
      %{data: response(ingestion.record, ingestion.replayed), replayed: ingestion.replayed}
    end)
  end

  def open(_, _), do: {:error, :forbidden}

  def status(%Scope{service?: true} = scope) do
    transaction(fn ->
      scope = unwrap(Scope.refresh(scope))
      ingestion = Repo.one(query(scope)) || abort(:not_found)
      response(ingestion, true)
    end)
  end

  def status(_), do: {:error, :forbidden}

  def save(%Scope{} = scope, attrs) do
    Multi.new()
    |> Multi.run(:result, fn _repo, _ ->
      try do
        scope = unwrap(Scope.refresh(scope))
        ingestion = save_ingestion(scope, attrs)

        result =
          if ingestion.post_id,
            do: saved(ingestion, scope, true),
            else: persist(scope, ingestion, attrs)

        {:ok, result}
      catch
        {:memory_error, reason} -> {:error, reason}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, _step, reason, _} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def response(%Ingestion{} = ingestion, replayed) do
    %{
      ingestion_id: ingestion.id,
      state: if(ingestion.post_id, do: "saved", else: "open"),
      source_hash: ingestion.source_hash,
      receipt: if(ingestion.post_id, do: receipt(ingestion, replayed), else: nil)
    }
  end

  defp open_locked(scope, content) do
    if not String.valid?(content) or String.trim(content) == "", do: abort(:invalid_content)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.insert_all(
        Ingestion,
        [
          %{
            id: Ecto.UUID.generate(version: 7, precision: :monotonic),
            owner_actor_id: scope.owner.id,
            created_by_actor_id: scope.actor.id,
            origin_identifier: scope.origin_identifier,
            original_content: content,
            source_hash: Candidate.hash(content),
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:owner_actor_id, :origin_identifier]
      )

    ingestion = Repo.one!(from ingestion in query(scope), lock: "FOR UPDATE")
    if ingestion.original_content != content, do: abort(:ingestion_conflict)
    %{record: ingestion, replayed: count == 0}
  end

  defp save_ingestion(%Scope{service?: true} = scope, attrs) do
    id =
      case Ecto.UUID.cast(attrs["ingestion_id"]) do
        {:ok, id} -> id
        :error -> abort(:invalid_ingestion_id)
      end

    Repo.one(from ingestion in query(scope), where: ingestion.id == ^id, lock: "FOR UPDATE") ||
      abort(:not_found)
  end

  defp save_ingestion(scope, attrs) do
    if Map.has_key?(attrs, "ingestion_id"), do: abort(:invalid_ingestion_id)

    scope = %{
      scope
      | origin_identifier: "direct:" <> Ecto.UUID.generate(version: 7, precision: :monotonic)
    }

    content = Map.get(attrs, "body")
    if not is_binary(content), do: abort(:invalid_candidate)
    open_locked(scope, content).record
  end

  defp persist(scope, ingestion, attrs) do
    {post_attrs, tags} = unwrap(Candidate.validate(attrs, scope.service?))
    authorize_references!(scope, post_attrs["metadata"])

    post =
      %Post{owner_actor_id: scope.owner.id, created_by_actor_id: scope.actor.id}
      |> Post.changeset(post_attrs)
      |> Repo.insert()
      |> unwrap()

    Enum.each(tags, fn attrs ->
      changeset = Tag.changeset(%Tag{owner_actor_id: scope.owner.id}, attrs)

      unwrap(
        Repo.insert(changeset,
          on_conflict: :nothing,
          conflict_target: [:owner_actor_id, :namespace, :key]
        )
      )

      tag =
        Repo.one!(
          from tag in Tag,
            where:
              tag.owner_actor_id == ^scope.owner.id and tag.namespace == ^attrs["namespace"] and
                tag.key == ^attrs["key"],
            lock: "FOR SHARE"
        )

      unwrap(%Tagging{} |> Tagging.changeset(post, tag) |> Repo.insert())
    end)

    unwrap(ProjectionJob.Manager.create_pending(post))
    snapshot = %{"body_hash" => post.body_hash, "tag_ids" => tag_ids(post.id)}

    ingestion =
      ingestion
      |> Changeset.change(post_id: post.id, saved_receipt: snapshot)
      |> Repo.update()
      |> unwrap()

    saved(ingestion, scope, false)
  end

  defp saved(ingestion, scope, replayed) do
    post =
      Repo.get_by(Post, id: ingestion.post_id, owner_actor_id: scope.owner.id) ||
        abort(:not_found)

    %{post: post, receipt: receipt(ingestion, replayed), replayed: replayed}
  end

  defp receipt(ingestion, replayed) do
    post =
      Repo.one!(
        from post in Post,
          where:
            post.id == ^ingestion.post_id and post.owner_actor_id == ^ingestion.owner_actor_id,
          lock: "FOR SHARE"
      )

    job =
      Repo.get_by!(ProjectionJob,
        post_id: post.id,
        revision: post.memory_revision,
        profile: "memory-v1"
      )

    %{
      post_id: post.id,
      ingestion_id: ingestion.id,
      body_hash: ingestion.saved_receipt["body_hash"],
      tag_ids: ingestion.saved_receipt["tag_ids"],
      indexing_status: job.current_state,
      replayed: replayed
    }
  end

  defp tag_ids(post_id) do
    Repo.all(
      from tagging in Tagging,
        where: tagging.post_id == ^post_id,
        order_by: tagging.tag_id,
        select: tagging.tag_id
    )
  end

  defp authorize_references!(scope, metadata) do
    ids = Map.get(metadata, "derived_from_post_ids", [])
    # Arbitrary ordinary-agent metadata is not interpreted as typed provenance.
    if scope.service? and ids != [] do
      count =
        Repo.aggregate(
          from(post in Post, where: post.id in ^ids and post.owner_actor_id == ^scope.owner.id),
          :count
        )

      if count != length(ids), do: abort(:invalid_candidate)
    end
  end

  defp query(scope) do
    from ingestion in Ingestion,
      where:
        ingestion.owner_actor_id == ^scope.owner.id and
          ingestion.origin_identifier == ^scope.origin_identifier
  end

  defp abort(reason), do: throw({:memory_error, reason})

  defp transaction(fun) do
    Repo.transaction(fn ->
      try do
        fun.()
      catch
        {:memory_error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: abort(reason)
end
