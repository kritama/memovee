defmodule Memovee.OAuth.ActorTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures

  alias Memovee.Accounts.Actor.Manager, as: ActorManager
  alias Memovee.OAuth.Actor

  test "gets or creates the stable OAuth lifecycle Actor through the account manager" do
    assert {:ok, actor} = Actor.get()
    assert actor.identifier == "system:oauth"
    assert actor.type == :agent

    assert {:ok, same_actor} = Actor.get()
    assert same_actor.id == actor.id
  end

  test "does not resolve an invalid agent identifier to a user Actor" do
    _scope = user_scope_fixture()

    assert {:error, %Ecto.Changeset{valid?: false}} = ActorManager.get_or_create_agent(" ")
  end
end
