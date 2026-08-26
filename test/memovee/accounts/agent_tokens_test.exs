defmodule Memovee.Accounts.AgentTokensTest do
  use Memovee.DataCase, async: true

  import Memovee.AccountsFixtures

  alias Memovee.Accounts
  alias Memovee.Accounts.{Actor, Relationship, Token, User}

  describe "Actor classification and registration" do
    test "registration atomically creates one user Actor" do
      actor_count = Repo.aggregate(Actor, :count)

      assert {:ok, user} = Accounts.register_user(%{email: unique_user_email()})
      assert user.actor.type == :user
      assert user.actor.current_state == "active"
      assert is_nil(user.actor.identifier)
      assert Repo.aggregate(Actor, :count) == actor_count + 1
      assert Repo.get_by!(User, actor_id: user.actor.id).id == user.id
    end

    test "invalid and conflicting registrations leave no orphan Actor" do
      existing = user_fixture()
      actor_count = Repo.aggregate(Actor, :count)

      assert {:error, _changeset} = Accounts.register_user(%{email: "invalid"})
      assert {:error, _changeset} = Accounts.register_user(%{email: existing.email})
      assert Repo.aggregate(Actor, :count) == actor_count
    end

    test "public changesets cannot alter Actor type or lifecycle state" do
      changeset =
        Accounts.change_agent(%Actor{}, %{
          "identifier" => "  INDEXER  ",
          "type" => "user",
          "current_state" => "inactive",
          "current_state_version" => 99
        })

      assert changeset.valid?
      assert get_field(changeset, :identifier) == "indexer"
      assert get_field(changeset, :type) == :agent
      assert get_field(changeset, :current_state) == "active"
      assert get_field(changeset, :current_state_version) == 0
    end

    test "deactivating a user Actor immediately blocks session and email credentials" do
      user = user_fixture()
      transitioning_actor = user_fixture().actor
      session_token = Accounts.generate_user_session_token(user)
      {magic_token, _digest} = generate_user_magic_link_token(user)

      assert Accounts.get_user_by_session_token(session_token)
      assert Accounts.get_user_by_magic_link_token(magic_token)

      assert {:ok, %{resource: _inactive_actor}} =
               Accounts.deactivate_actor(user.actor, transitioning_actor)

      refute Accounts.get_user_by_session_token(session_token)
      refute Accounts.get_user_by_magic_link_token(magic_token)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(magic_token)
    end
  end

  describe "agent ownership" do
    setup do
      owner = user_fixture().actor
      other_owner = user_fixture().actor
      %{owner: owner, other_owner: other_owner}
    end

    test "creates an agent and its sole owner atomically", %{owner: owner} do
      assert {:ok, agent} = Accounts.create_agent(owner, %{identifier: "  Media-Indexer  "})
      assert agent.type == :agent
      assert agent.identifier == "media-indexer"
      refute Repo.get_by(User, actor_id: agent.id)

      assert %Relationship{
               actor_id: owner_id,
               target_actor_id: agent_id,
               type: :owner
             } = Repo.get_by!(Relationship, target_actor_id: agent.id)

      assert owner_id == owner.id
      assert agent_id == agent.id
    end

    test "lists and loads only agents owned by the caller", %{
      owner: owner,
      other_owner: other_owner
    } do
      agent = agent_fixture(owner)

      assert [owned_agent] = Accounts.list_owned_agents(owner)
      assert owned_agent.id == agent.id
      assert {:ok, %{id: id}} = Accounts.get_owned_agent(owner, agent.id)
      assert id == agent.id

      assert Accounts.list_owned_agents(other_owner) == []
      assert {:error, :not_found} = Accounts.get_owned_agent(other_owner, agent.id)
    end

    test "enforces case-insensitive identifiers and an active human owner", %{
      owner: owner,
      other_owner: other_owner
    } do
      assert {:ok, _agent} = Accounts.create_agent(owner, %{identifier: "Worker"})
      assert {:error, changeset} = Accounts.create_agent(other_owner, %{identifier: "worker"})
      assert "has already been taken" in errors_on(changeset).identifier

      assert {:ok, %{resource: inactive_owner}} =
               Accounts.deactivate_actor(owner, other_owner)

      assert {:error, :unauthorized} =
               Accounts.create_agent(inactive_owner, %{identifier: "another-worker"})
    end
  end

  describe "agent API tokens" do
    setup do
      owner = user_fixture().actor
      agent = agent_fixture(owner)
      %{owner: owner, agent: agent}
    end

    test "creates distinct one-time secrets and stores only SHA-256 digests", %{
      owner: owner,
      agent: agent
    } do
      first = api_token_fixture(owner, agent, %{label: "primary"})
      second = api_token_fixture(owner, agent, %{label: "rotation"})

      refute first.client_id == second.client_id
      refute first.client_secret == second.client_secret
      assert byte_size(first.client_secret) == 43

      stored = Repo.get!(Token, first.client_id)
      {:ok, decoded_secret} = Base.url_decode64(first.client_secret, padding: false)

      assert stored.actor_id == agent.id
      assert stored.context == "api"
      assert stored.token == :crypto.hash(:sha256, decoded_secret)
      refute stored.token == first.client_secret

      assert {:ok, tokens} = Accounts.list_agent_api_tokens(owner, agent.id)

      assert Enum.map(tokens, & &1.id) |> Enum.sort() ==
               [first.client_id, second.client_id] |> Enum.sort()
    end

    test "verifies a valid secret and updates last use", %{owner: owner, agent: agent} do
      credential = api_token_fixture(owner, agent)

      assert {:ok, authenticated_actor} =
               Accounts.verify_api_token(
                 credential.client_id,
                 credential.client_secret,
                 "api"
               )

      assert authenticated_actor.id == agent.id
      assert Repo.get!(Token, credential.client_id).authenticated_at
    end

    test "returns uniform unauthorized results for malformed, wrong, expired, and revoked tokens",
         %{
           owner: owner,
           agent: agent
         } do
      credential = api_token_fixture(owner, agent)

      assert {:error, :unauthorized} = Accounts.verify_api_token("bad", "bad", "api")

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(
                 credential.client_id,
                 Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false),
                 "api"
               )

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(
                 credential.client_id,
                 credential.client_secret,
                 "other"
               )

      token = Repo.get!(Token, credential.client_id)

      token
      |> change(expires_at: DateTime.utc_now(:microsecond) |> DateTime.add(-1, :second))
      |> Repo.update!()

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(
                 credential.client_id,
                 credential.client_secret,
                 "api"
               )

      replacement = api_token_fixture(owner, agent)
      assert :ok = Accounts.revoke_agent_api_token(owner, agent.id, replacement.client_id)

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(
                 replacement.client_id,
                 replacement.client_secret,
                 "api"
               )
    end

    test "rejects human Actors and inactive agents on the next request", %{
      owner: owner,
      agent: agent
    } do
      secret = :crypto.strong_rand_bytes(32)

      human_token =
        Repo.insert!(%Token{
          actor_id: owner.id,
          token: :crypto.hash(:sha256, secret),
          context: "api",
          label: "invalid human token",
          expires_at: DateTime.utc_now(:microsecond) |> DateTime.add(1, :day)
        })

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(
                 human_token.id,
                 Base.url_encode64(secret, padding: false),
                 "api"
               )

      credential = api_token_fixture(owner, agent)
      assert {:ok, %{resource: _inactive_agent}} = Accounts.deactivate_actor(agent, owner)

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(
                 credential.client_id,
                 credential.client_secret,
                 "api"
               )
    end

    test "an unrelated owner cannot list, create, or revoke credentials", %{
      owner: owner,
      agent: agent
    } do
      unrelated = user_fixture().actor
      credential = api_token_fixture(owner, agent)

      assert {:error, :not_found} = Accounts.list_agent_api_tokens(unrelated, agent.id)

      assert {:error, :not_found} =
               Accounts.create_agent_api_token(unrelated, agent.id, %{
                 label: "forbidden",
                 expires_at: DateTime.utc_now(:microsecond) |> DateTime.add(1, :day)
               })

      assert {:error, :not_found} =
               Accounts.revoke_agent_api_token(unrelated, agent.id, credential.client_id)
    end

    test "rotation keeps the replacement valid after the old token is revoked", %{
      owner: owner,
      agent: agent
    } do
      old = api_token_fixture(owner, agent, %{label: "old"})
      replacement = api_token_fixture(owner, agent, %{label: "replacement"})

      assert :ok = Accounts.revoke_agent_api_token(owner, agent.id, old.client_id)

      assert {:error, :unauthorized} =
               Accounts.verify_api_token(old.client_id, old.client_secret, "api")

      assert {:ok, %{id: agent_id}} =
               Accounts.verify_api_token(
                 replacement.client_id,
                 replacement.client_secret,
                 "api"
               )

      assert agent_id == agent.id
    end
  end
end
