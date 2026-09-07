defmodule Memovee.Memory.PostPersistenceTest do
  use Memovee.DataCase, async: false
  import Memovee.AccountsFixtures
  alias Memovee.Memory.{Post, Scope, Tag, Tagging}
  alias Memovee.Projections.Indexing

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    service = agent_fixture(owner)
    previous = Application.get_env(:memovee, :memory_tama_actor_id)
    Application.put_env(:memovee, :memory_tama_actor_id, service.id)
    on_exit(fn -> Application.put_env(:memovee, :memory_tama_actor_id, previous) end)

    {:ok, scope} =
      Scope.resolve(service, %{
        "context" => %{"actor_id" => agent.id, "origin_identifier" => "test:source"}
      })

    %{owner: owner, agent: agent, service: service, scope: scope}
  end

  test "atomic save and changed-candidate replay", %{scope: scope} do
    assert {:ok, result} = Post.Manager.create(scope, candidate())
    assert result.receipt.indexing_status == "pending"
    assert result.post.owner_actor_id == scope.owner.id
    assert result.post.created_by_actor_id == scope.actor.id
    assert result.post.origin_identifier == scope.origin_identifier
    assert Repo.aggregate(Post, :count) == 1
    assert Repo.aggregate(Tag, :count) == 2
    assert Repo.aggregate(Tagging, :count) == 2
    assert Repo.aggregate(Indexing, :count) == 1
    assert {:ok, replay} = Post.Manager.create(scope, %{"body" => nil})
    assert replay.post == result.post
    assert replay.receipt == %{result.receipt | replayed: true}
  end

  test "invalid tags roll back all saved records and allow a corrected retry", %{scope: scope} do
    attrs =
      candidate()
      |> Map.put("tags", [%{"namespace" => "project", "key" => "!", "name" => "Invalid"}])

    assert {:error, :invalid_tags} = Post.Manager.create(scope, attrs)

    for schema <- [Post, Tag, Tagging, Indexing, Oban.Job],
        do: assert(Repo.aggregate(schema, :count) == 0)

    assert {:ok, %{replayed: false}} = Post.Manager.create(scope, candidate())
  end

  test "two agents share an owner but another owner cannot hydrate a post", %{
    owner: owner,
    agent: agent
  } do
    other_agent = agent_fixture(owner)
    other_owner = user_fixture().actor
    other = agent_fixture(other_owner)
    {:ok, first} = Scope.resolve(agent, %{})
    {:ok, second} = Scope.resolve(other_agent, %{})
    {:ok, third} = Scope.resolve(other, %{})

    {:ok, result} =
      Post.Manager.create(first, %{
        "body" => "private",
        "tags" => [%{"namespace" => "project", "name" => "Shared"}]
      })

    assert {:ok, _} = Post.Manager.get(second, result.post.id)
    assert {:error, :not_found} = Post.Manager.get(third, result.post.id)
    assert {:ok, []} = Post.Manager.list(third)

    {:ok, other_result} =
      Post.Manager.create(third, %{
        "body" => "other",
        "tags" => [%{"namespace" => "project", "name" => "Shared"}]
      })

    assert result.receipt.tag_ids != other_result.receipt.tag_ids
    [other_tag] = Repo.all(from tag in Tag, where: tag.owner_actor_id == ^other_owner.id)
    assert {:error, :owner_mismatch} = Tagging.Manager.create(result.post, other_tag)
  end

  test "forged context and inactive owners or actors cannot access memory", %{
    agent: agent,
    scope: scope,
    owner: owner
  } do
    assert {:error, :forbidden_context} = Scope.resolve(agent, %{"context" => %{}})
    {:ok, _} = Memovee.Accounts.Actor.Manager.transition(owner, owner, :deactivate)
    assert {:error, :forbidden} = Post.Manager.create(scope, candidate())
    assert {:error, :forbidden} = Scope.resolve(agent, %{})
  end

  test "tags are reused without replacing descriptions and edits enqueue revisions", %{
    scope: scope,
    agent: agent
  } do
    {:ok, direct} = Scope.resolve(agent, %{})

    attrs = %{
      "body" => "first",
      "tags" => [
        %{
          "namespace" => "project",
          "key" => "memovee",
          "name" => "Memovee",
          "description" => "Original"
        }
      ]
    }

    {:ok, first} = Post.Manager.create(direct, attrs)

    {:ok, _} =
      Post.Manager.create(
        direct,
        put_in(attrs, ["tags", Access.at(0), "description"], "Replacement")
      )

    [tag] = Repo.all(Tag)
    assert tag.description == "Original"
    assert {:ok, _} = Tag.Manager.update(direct, tag, %{description: "Explicit edit"})
    assert Repo.get!(Post, first.post.id).memory_revision == 2
    assert Repo.aggregate(Indexing, :count) == 4
    assert {:ok, updated} = Post.Manager.update(agent, first.post, %{title: "New title"})
    assert updated.memory_revision == 3
    assert updated.owner_actor_id == scope.owner.id
  end

  test "fingerprint matches the published canonical JSON vector" do
    fixture =
      File.read!("tama/graph/schemas/memory-fixtures.v1.json")
      |> Jason.decode!()
      |> Map.fetch!("fingerprint")

    assert Indexing.Manager.canonical_json(fixture["input"]) == fixture["canonical_json"]
    assert Indexing.Manager.fingerprint(fixture["input"]) == fixture["sha256"]
  end

  test "replay receipts reflect current canonical data without overwriting edits", %{
    scope: scope,
    agent: agent
  } do
    {:ok, result} = Post.Manager.create(scope, candidate())
    {:ok, updated} = Post.Manager.update(agent, result.post, %{body: "Changed canonical body"})
    {:ok, replay} = Post.Manager.create(scope, candidate())
    assert replay.post == updated
    assert replay.receipt.body_hash == updated.body_hash
    assert replay.receipt.replayed
  end

  test "inactive agents, inactive service and unowned agents cannot resolve", %{
    scope: scope,
    owner: owner,
    agent: agent,
    service: service
  } do
    {:ok, _} = Eventful.Transit.perform(agent, owner, "deactivate")
    assert {:error, :forbidden} = Post.Manager.create(scope, candidate())

    {:ok, _} =
      Eventful.Transit.perform(Repo.get!(Memovee.Accounts.Actor, agent.id), owner, "activate")

    {:ok, _} = Eventful.Transit.perform(service, owner, "deactivate")
    assert {:error, :forbidden} = Post.Manager.create(scope, candidate())
    {:ok, unowned} = Memovee.Accounts.Actor.Manager.get_or_create_agent("unowned-test")
    assert {:error, :forbidden} = Scope.resolve(unowned, %{})
  end

  test "idempotency is owner and origin scoped and provenance stays authorized", %{
    scope: scope,
    service: service
  } do
    {:ok, first} = Post.Manager.create(scope, candidate())
    {:ok, second} = Post.Manager.create(%{scope | origin_identifier: "another"}, candidate())
    refute first.post.id == second.post.id
    other_owner = user_fixture().actor

    {:ok, other_scope} =
      Scope.resolve(service, %{
        "context" => %{
          "actor_id" => other_owner.id,
          "origin_identifier" => scope.origin_identifier
        }
      })

    {:ok, other} = Post.Manager.create(other_scope, candidate())
    refute first.post.id == other.post.id
    attrs = put_in(candidate(), ["metadata", "derived_from_post_ids"], [first.post.id])

    assert {:error, :invalid_candidate} =
             Post.Manager.create(%{other_scope | origin_identifier: "new"}, attrs)

    assert Repo.aggregate(Post, :count) == 3
  end

  test "tagging changes enqueue revisions and unchanged updates do not", %{agent: agent} do
    {:ok, scope} = Scope.resolve(agent, %{})
    attrs = %{"body" => "source", "tags" => [%{"namespace" => "project", "name" => "One"}]}
    {:ok, first} = Post.Manager.create(scope, attrs)

    {:ok, second} =
      Post.Manager.create(scope, put_in(attrs, ["tags", Access.at(0), "name"], "Two"))

    [tag_id] = second.receipt.tag_ids
    tag = Repo.get!(Tag, tag_id)
    assert {:ok, _} = Tagging.Manager.create(first.post, tag)
    assert Repo.get!(Post, first.post.id).memory_revision == 2
    assert {1, nil} = Tagging.Manager.delete(first.post, tag)
    assert Repo.get!(Post, first.post.id).memory_revision == 3
    assert {:ok, updated} = Post.Manager.update(agent, first.post, %{body: "source"})
    assert updated.memory_revision == 3
    assert Repo.aggregate(Indexing, :count) == 4
  end

  defp candidate do
    %{
      "title" => "Preference",
      "body" => "Use Req.",
      "metadata" => %{
        "kind" => "preference",
        "epistemic_status" => "user_stated",
        "approval" => "unspecified",
        "source" => %{"channel" => "agent", "reference" => nil},
        "occurred_at" => nil,
        "effective_at" => nil,
        "derived_from_post_ids" => []
      },
      "tags" => [%{"namespace" => "tool", "key" => "req", "name" => "Req"}]
    }
  end
end
