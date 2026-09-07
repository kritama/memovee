defmodule Memovee.Projections.IndexingTest do
  use Memovee.DataCase, async: false
  import Memovee.AccountsFixtures
  alias Memovee.Memory.{Post, Scope}
  alias Memovee.Projections.Indexing

  test "job declarations require the configured active service and cannot claim readiness yet" do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    service = agent_fixture(owner)
    previous = Application.get_env(:memovee, :memory_tama_actor_id)
    Application.put_env(:memovee, :memory_tama_actor_id, service.id)
    on_exit(fn -> Application.put_env(:memovee, :memory_tama_actor_id, previous) end)
    {:ok, scope} = Scope.resolve(agent, %{})
    {:ok, result} = Post.Manager.create(scope, %{"body" => "source"})
    job = Repo.get_by!(Indexing, post_id: result.post.id)

    assert Enum.sort(Indexing.Transitions.valid_states()) ==
             ~w(failed obsolete pending processing ready)

    assert {:error, %Eventful.Error{code: :worker_not_implemented}} =
             Eventful.Transit.perform(job, service, "claim", [])

    assert {:error, %Eventful.Error{code: :forbidden}} =
             Eventful.Transit.perform(job, agent, "invalidate", [])

    assert {:error, %Eventful.Error{code: :revision, message: :current_revision}} =
             Eventful.Transit.perform(job, service, "invalidate", [])

    assert {:error, %Eventful.Error{code: :revision, message: :current_revision}} =
             Eventful.Transit.perform(%{job | revision: 0}, service, "invalidate", [])

    assert Repo.reload!(job).current_state == "pending"
    assert Repo.aggregate(Indexing.Event, :count) == 0

    assert {:ok, _} = Post.Manager.update(scope, result.post, %{body: "revised"})

    assert {:ok, %{resource: obsolete}} = Eventful.Transit.perform(job, service, "invalidate", [])
    assert obsolete.current_state == "obsolete"
    event = Repo.one!(Indexing.Event)
    assert event.actor_id == service.id
    assert <<_::48, 7::4, _::76>> = Ecto.UUID.dump!(event.id)
  end

  test "Oban insertion participates in save rollback and revision transactions" do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    {:ok, scope} = Scope.resolve(agent, %{})

    assert {:error, :forced_rollback} =
             Repo.transaction(fn ->
               {:ok, _} = Post.Manager.create(scope, %{"body" => "rolled back"})
               Repo.rollback(:forced_rollback)
             end)

    assert Repo.aggregate(Indexing, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0

    {:ok, result} = Post.Manager.create(scope, %{"body" => "saved"})
    job = Repo.one!(Oban.Job)
    projection = Repo.get_by!(Indexing, post_id: result.post.id)
    assert projection.indexing_version == 1
    assert projection.revision == result.post.memory_revision
    assert job.args == %{"projection_id" => projection.id}
    assert job.worker == "Memovee.Projections.Indexing.Worker"
    assert job.queue == "memory_projection"
    assert job.max_attempts == 5
    assert job.state == "available"
    assert {:ok, _} = Memovee.Memory.Post.Manager.update(scope, result.post, %{body: "revised"})
    assert Repo.aggregate(Oban.Job, :count) == 2
    assert Repo.aggregate(Indexing, :count) == 2
  end

  test "revision bumps reload stale structs" do
    {:ok, scope} = Scope.resolve(user_fixture().actor, %{})
    {:ok, result} = Post.Manager.create(scope, %{"body" => "source"})
    assert {:ok, first} = Indexing.Manager.bump(scope, result.post)
    assert first.memory_revision == 2
    assert {:ok, second} = Indexing.Manager.bump(scope, result.post)
    assert second.memory_revision == 3
    assert Repo.aggregate(Indexing, :count) == 3
    assert Repo.aggregate(Oban.Job, :count) == 3
  end

  test "all public indexing operations reject foreign and inactive scopes" do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    {:ok, scope} = Scope.resolve(agent, %{})
    {:ok, result} = Post.Manager.create(scope, %{"body" => "Private"})
    {:ok, other} = Scope.resolve(user_fixture().actor, %{})
    forged = %Post{id: result.post.id, owner_actor_id: other.owner.id}

    for operation <- [
          &Memovee.Projections.create_indexing/2,
          &Memovee.Projections.get_post_indexing/2,
          &Memovee.Projections.bump_indexing_revision/2
        ] do
      assert {:error, :not_found} = operation.(other, forged)
    end

    assert {:ok, _} = Eventful.Transit.perform(agent, owner, "deactivate")

    for operation <- [
          &Memovee.Projections.create_indexing/2,
          &Memovee.Projections.get_post_indexing/2,
          &Memovee.Projections.bump_indexing_revision/2
        ] do
      assert {:error, :forbidden} = operation.(scope, result.post)
    end

    assert Repo.reload!(result.post).memory_revision == 1
    assert Repo.aggregate(Indexing, :count) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "indexing reads reload current revisions rather than trusting supplied structs" do
    {:ok, scope} = Scope.resolve(user_fixture().actor, %{})
    {:ok, result} = Post.Manager.create(scope, %{"body" => "source"})
    assert {:ok, _} = Memovee.Projections.bump_indexing_revision(scope, result.post)
    assert {:ok, projection} = Memovee.Projections.get_post_indexing(scope, result.post)
    assert projection.revision == 2
  end
end
