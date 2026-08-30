defmodule Memovee.OAuth.ActorTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures

  alias Memovee.Accounts.Actor, as: AccountActor
  alias Memovee.Accounts.Actor.Manager, as: ActorManager
  alias Memovee.Accounts.Relationship
  alias Memovee.OAuth.Actor

  test "gets or creates the stable OAuth lifecycle Actor through the account manager" do
    assert {:ok, actor} = Actor.get()
    assert actor.identifier == "system:oauth"
    assert actor.type == :agent

    assert {:ok, same_actor} = Actor.get()
    assert same_actor.id == actor.id
  end

  test "reuses an existing agent without aborting its enclosing transaction" do
    assert {:ok, existing_actor} = ActorManager.get_or_create_agent("system:oauth")

    assert {:ok, same_actor} =
             Repo.transact(fn -> ActorManager.get_or_create_agent("system:oauth") end)

    assert same_actor.id == existing_actor.id
  end

  test "rejects a reserved identifier that is already owned by a user" do
    owner = user_fixture().actor

    owned_actor =
      %AccountActor{}
      |> AccountActor.agent_changeset(%{identifier: "system:oauth"})
      |> Repo.insert!()

    %Relationship{}
    |> Relationship.owner_changeset(owner, owned_actor)
    |> Repo.insert!()

    assert {:error, :system_actor_unavailable} = Actor.get()
  end

  test "does not resolve an invalid agent identifier to a user Actor" do
    _scope = user_scope_fixture()

    assert {:error, %Ecto.Changeset{valid?: false}} = ActorManager.get_or_create_agent(" ")

    assert {:error, :invalid_system_identifier} =
             ActorManager.get_or_create_system_agent("ordinary-agent")
  end
end
