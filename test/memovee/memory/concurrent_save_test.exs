defmodule Memovee.Memory.ConcurrentSaveTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Memovee.Accounts.Actor
  alias Memovee.Memory.{Post, Scope, Tag, Tagging}
  alias Memovee.Projections.Indexing
  alias Memovee.Repo

  test "twenty independent database transactions save one source exactly once" do
    {owner, service} =
      Sandbox.unboxed_run(Repo, fn ->
        owner = Repo.insert!(Actor.user_changeset(%Actor{}))

        service =
          Repo.insert!(
            Actor.agent_changeset(%Actor{}, %{
              identifier: "concurrency-#{System.unique_integer([:positive])}"
            })
          )

        {owner, service}
      end)

    previous = Application.get_env(:memovee, :memory_tama_actor_id)
    Application.put_env(:memovee, :memory_tama_actor_id, service.id)

    on_exit(fn ->
      Application.put_env(:memovee, :memory_tama_actor_id, previous)
      Sandbox.unboxed_run(Repo, fn -> cleanup(owner, service) end)
    end)

    context = %{
      "context" => %{"actor_id" => owner.id, "origin_identifier" => "concurrent:source"}
    }

    results =
      1..20
      |> Task.async_stream(
        fn attempt ->
          Sandbox.unboxed_run(Repo, fn ->
            {:ok, scope} = Scope.resolve(service, context)

            Post.Manager.create(scope, %{
              "title" => nil,
              "body" => "Canonical wording #{attempt}",
              "tags" => [],
              "metadata" => %{
                "kind" => "fact",
                "epistemic_status" => "reported",
                "approval" => "unspecified",
                "source" => %{"channel" => "agent", "reference" => nil},
                "occurred_at" => nil,
                "effective_at" => nil,
                "derived_from_post_ids" => []
              }
            })
          end)
        end,
        max_concurrency: 20,
        timeout: :infinity
      )
      |> Enum.to_list()

    assert length(results) == 20
    receipts = Enum.map(results, fn {:ok, {:ok, result}} -> result.receipt end)
    assert length(Enum.uniq_by(receipts, & &1.post_id)) == 1
    assert length(Enum.uniq_by(receipts, & &1.body_hash)) == 1
    assert Enum.count(receipts, &(not &1.replayed)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      projection = Repo.get_by!(Indexing, post_id: hd(receipts).post_id)

      assert Repo.aggregate(
               from(job in Oban.Job,
                 where: fragment("?->>'projection_id'", job.args) == ^projection.id
               ),
               :count
             ) == 1
    end)

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(from(post in Post, where: post.owner_actor_id == ^owner.id), :count) ==
               1

      assert Repo.aggregate(
               from(job in Indexing, where: job.owner_actor_id == ^owner.id),
               :count
             ) == 1
    end)
  end

  defp cleanup(owner, service) do
    posts = from post in Post, where: post.owner_actor_id == ^owner.id, select: post.id

    projection_ids =
      Repo.all(from job in Indexing, where: job.owner_actor_id == ^owner.id, select: job.id)

    Repo.delete_all(
      from job in Oban.Job, where: fragment("?->>'projection_id'", job.args) in ^projection_ids
    )

    Repo.delete_all(from tagging in Tagging, where: tagging.post_id in subquery(posts))
    Repo.delete_all(from job in Indexing, where: job.owner_actor_id == ^owner.id)
    Repo.delete_all(from post in Post, where: post.owner_actor_id == ^owner.id)
    Repo.delete_all(from tag in Tag, where: tag.owner_actor_id == ^owner.id)
    Repo.delete_all(from actor in Actor, where: actor.id in ^[owner.id, service.id])
  end
end
