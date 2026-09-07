defmodule Memovee.Memory.Tagging.ManagerTest do
  use Memovee.DataCase, async: false
  import Memovee.AccountsFixtures
  alias Memovee.Memory
  alias Memovee.Memory.{Post, Scope, Tag, Tagging}
  alias Memovee.Projections.Indexing

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    {:ok, scope} = Scope.resolve(agent, %{})
    {:ok, result} = Memory.create_post(scope, %{"body" => "Private"})
    {:ok, tag} = Memory.create_tag(scope, %{namespace: "topic", key: "private", name: "Private"})
    %{owner: owner, agent: agent, scope: scope, post: result.post, tag: tag}
  end

  test "foreign scopes cannot assign or remove tags using forged structs", %{
    scope: scope,
    post: post,
    tag: tag
  } do
    {:ok, other} = Scope.resolve(user_fixture().actor, %{})
    assert {:error, :not_found} = Memory.tag_post(other, %Post{id: post.id}, %Tag{id: tag.id})
    assert Repo.aggregate(Tagging, :count) == 0
    assert Repo.reload!(post).memory_revision == 1
    assert {:ok, _} = Memory.tag_post(scope, post, tag)
    assert {:error, :not_found} = Memory.untag_post(other, %Post{id: post.id}, %Tag{id: tag.id})
    assert Repo.aggregate(Tagging, :count) == 1
    assert Repo.reload!(post).memory_revision == 2
    assert Repo.aggregate(Indexing, :count) == 2
    assert Repo.aggregate(Oban.Job, :count) == 2
  end

  test "assignment mutations refresh inactive actor and owner scopes", %{
    owner: owner,
    agent: agent,
    scope: scope,
    post: post,
    tag: tag
  } do
    assert {:ok, _} = Memory.tag_post(scope, post, tag)
    assert {:ok, %{resource: inactive}} = Eventful.Transit.perform(agent, owner, "deactivate")
    assert {:error, :forbidden} = Memory.tag_post(scope, post, tag)
    assert {:error, :forbidden} = Memory.untag_post(scope, post, tag)
    assert {:ok, _} = Eventful.Transit.perform(inactive, owner, "activate")
    assert {:ok, _} = Eventful.Transit.perform(owner, owner, "deactivate")
    assert {:error, :forbidden} = Memory.tag_post(scope, post, tag)
    assert {:error, :forbidden} = Memory.untag_post(scope, post, tag)
    assert Repo.aggregate(Tagging, :count) == 1
    assert Repo.reload!(post).memory_revision == 2
    assert Repo.aggregate(Oban.Job, :count) == 2
  end

  test "same-owner agents can assign and remove tags", %{owner: owner, post: post, tag: tag} do
    {:ok, scope} = Scope.resolve(agent_fixture(owner), %{})
    assert {:ok, _} = Memory.tag_post(scope, post, tag)
    assert {1, nil} = Memory.untag_post(scope, post, tag)
    assert Repo.aggregate(Tagging, :count) == 0
    assert Repo.reload!(post).memory_revision == 3
    assert Repo.aggregate(Oban.Job, :count) == 3
  end
end
