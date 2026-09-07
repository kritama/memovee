defmodule Memovee.Memory.Projection.ManagerTest do
  use Memovee.DataCase, async: false
  import Memovee.AccountsFixtures
  alias Memovee.Memory
  alias Memovee.Memory.{Post, Projection, Scope}

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    {:ok, scope} = Scope.resolve(agent, %{})
    {:ok, result} = Memory.create_post(scope, %{"body" => "Private"})

    attrs = %{
      tama_space_id: Ecto.UUID.generate(version: 7),
      tama_class_id: Ecto.UUID.generate(version: 7)
    }

    {:ok, projection} = Memory.create_projection(scope, result.post, attrs)

    %{
      owner: owner,
      agent: agent,
      scope: scope,
      post: result.post,
      projection: projection,
      attrs: attrs
    }
  end

  test "projection reads and creation are owner scoped", %{
    post: post,
    projection: projection,
    attrs: attrs,
    scope: scope
  } do
    {:ok, other} = Scope.resolve(user_fixture().actor, %{})
    assert {:error, :not_found} = Memory.get_projection(other, projection.id)
    assert {:error, :not_found} = Memory.list_post_projections(other, %Post{id: post.id})
    assert {:ok, []} = Memory.list_pending_projections(other)
    assert {:error, :not_found} = Memory.create_projection(other, %Post{id: post.id}, attrs)
    assert {:error, :not_found} = Memory.list_post_tags(other, %Post{id: post.id})
    assert {:ok, [^projection]} = Memory.list_post_projections(scope, post)
    assert {:ok, [^projection]} = Memory.list_pending_projections(scope)
    assert {:ok, ^projection} = Memory.get_projection(scope, projection.id)
  end

  test "direct Eventful transitions enforce persisted ownership and active actors", %{
    owner: owner,
    agent: agent,
    scope: scope,
    projection: projection
  } do
    other = user_fixture().actor
    forged = %{projection | post_id: Ecto.UUID.generate(version: 7)}

    assert {:error, %Eventful.Error{code: :authorization}} =
             Eventful.Transit.perform(forged, other, "sync")

    assert Repo.aggregate(Projection.Event, :count) == 0
    assert {:ok, _} = Eventful.Transit.perform(agent, owner, "deactivate")

    assert {:error, :forbidden} = Memory.start_projection_sync(scope, projection)

    assert Repo.reload!(projection).current_state == "pending"
  end

  test "projection lifecycle mutations are owner scoped", %{projection: projection} do
    {:ok, other_scope} = Scope.resolve(user_fixture().actor, %{})
    forged = %Projection{id: projection.id}

    assert {:error, :not_found} = Memory.start_projection_sync(other_scope, forged)

    assert {:error, :not_found} =
             Memory.complete_projection_sync(
               other_scope,
               forged,
               Ecto.UUID.generate(version: 7),
               String.duplicate("a", 64)
             )

    assert {:error, :not_found} = Memory.fail_projection_sync(other_scope, forged, :failed)
    assert {:error, :not_found} = Memory.retry_projection_sync(other_scope, forged)
    assert {:error, :not_found} = Memory.invalidate_projection(other_scope, forged)
    assert Repo.aggregate(Projection.Event, :count) == 0
    assert Repo.reload!(projection).current_state == "pending"
  end

  test "completion rejects invalid parameters", %{scope: scope, projection: projection} do
    assert {:ok, %{resource: syncing}} = Memory.start_projection_sync(scope, projection)

    assert {:error,
            %Eventful.Error{
              code: :invalid_transition_parameters,
              message: :invalid_tama_entity_id
            }} = Memory.complete_projection_sync(scope, syncing, "invalid", "invalid")
  end

  test "authorized lifecycle verifies body hash and invalidates on post edit", %{
    projection: projection,
    post: post,
    scope: scope
  } do
    assert {:ok, %{resource: syncing}} = Memory.start_projection_sync(scope, projection)

    assert {:error, %Eventful.Error{code: :stale_body}} =
             Memory.complete_projection_sync(
               scope,
               syncing,
               Ecto.UUID.generate(version: 7),
               String.duplicate("a", 64)
             )

    assert {:ok, %{resource: synced}} =
             Memory.complete_projection_sync(
               scope,
               syncing,
               Ecto.UUID.generate(version: 7),
               post.body_hash
             )

    assert synced.current_state == "synced"
    assert {:ok, _} = Memory.update_post(scope, post, %{body: "Updated"})
    assert Repo.reload!(projection).current_state == "pending"
  end
end
