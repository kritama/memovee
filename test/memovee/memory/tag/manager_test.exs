defmodule Memovee.Memory.Tag.ManagerTest do
  use Memovee.DataCase, async: false
  import Memovee.AccountsFixtures
  alias Memovee.Memory
  alias Memovee.Memory.{Scope, Tag}
  alias Memovee.Projections.Indexing

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    {:ok, scope} = Scope.resolve(agent, %{})

    {:ok, result} =
      Memory.create_post(scope, %{
        "body" => "Private memory",
        "tags" => [%{"namespace" => "topic", "name" => "Original"}]
      })

    tag = Repo.one!(Tag)
    %{owner: owner, agent: agent, scope: scope, post: result.post, tag: tag}
  end

  test "another owner's scope cannot update a tag by ID", %{tag: tag, post: post} do
    {:ok, other_scope} = Scope.resolve(user_fixture().actor, %{})

    assert {:error, :not_found} =
             Memory.update_tag(other_scope, %Tag{id: tag.id}, %{name: "Forged"})

    assert Repo.reload!(tag).name == "Original"
    assert Repo.reload!(post).memory_revision == 1
    assert Repo.aggregate(Indexing, :count) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "updates refresh scopes after the actor or owner becomes inactive", %{
    owner: owner,
    agent: agent,
    scope: scope,
    tag: tag,
    post: post
  } do
    assert {:ok, %{resource: inactive}} = Eventful.Transit.perform(agent, owner, "deactivate")
    assert {:error, :forbidden} = Memory.update_tag(scope, tag, %{name: "Forged"})
    assert {:ok, _} = Eventful.Transit.perform(inactive, owner, "activate")
    assert {:ok, _} = Eventful.Transit.perform(owner, owner, "deactivate")
    assert {:error, :forbidden} = Memory.update_tag(scope, tag, %{name: "Forged"})
    assert Repo.reload!(tag).name == "Original"
    assert Repo.reload!(post).memory_revision == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "another active agent of the same owner can update and enqueue a revision", %{
    owner: owner,
    tag: tag,
    post: post
  } do
    {:ok, scope} = Scope.resolve(agent_fixture(owner), %{})
    assert {:ok, updated} = Memory.update_tag(scope, tag, %{name: "Updated"})
    assert updated.name == "Updated"
    assert Repo.reload!(post).memory_revision == 2
    assert Repo.aggregate(Indexing, :count) == 2
    assert Repo.aggregate(Oban.Job, :count) == 2
  end
end
