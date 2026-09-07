defmodule Memovee.Memory.ProjectionJobTest do
  use Memovee.DataCase, async: false
  import Memovee.AccountsFixtures
  alias Memovee.Memory.{Ingestion, ProjectionJob, Scope}

  test "job declarations require the configured active service and cannot claim readiness yet" do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    service = agent_fixture(owner)
    previous = Application.get_env(:memovee, :memory_tama_actor_id)
    Application.put_env(:memovee, :memory_tama_actor_id, service.id)
    on_exit(fn -> Application.put_env(:memovee, :memory_tama_actor_id, previous) end)
    {:ok, scope} = Scope.resolve(agent, %{})
    {:ok, result} = Ingestion.Manager.save(scope, %{"body" => "source"})
    job = Repo.get_by!(ProjectionJob, post_id: result.post.id)

    assert Enum.sort(ProjectionJob.Transitions.valid_states()) ==
             ~w(failed obsolete pending processing ready)

    assert {:error, %Eventful.Error{code: :worker_not_implemented}} =
             Eventful.Transit.perform(job, service, "claim", [])

    assert {:error, %Eventful.Error{code: :forbidden}} =
             Eventful.Transit.perform(job, agent, "invalidate", [])

    assert {:ok, %{resource: obsolete}} = Eventful.Transit.perform(job, service, "invalidate", [])
    assert obsolete.current_state == "obsolete"
    event = Repo.one!(ProjectionJob.Event)
    assert event.actor_id == service.id
    assert <<_::48, 7::4, _::76>> = Ecto.UUID.dump!(event.id)
  end

  test "Oban insertion participates in save rollback and revision transactions" do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    {:ok, scope} = Scope.resolve(agent, %{})

    assert {:error, :forced_rollback} =
             Repo.transaction(fn ->
               {:ok, _} = Ingestion.Manager.save(scope, %{"body" => "rolled back"})
               Repo.rollback(:forced_rollback)
             end)

    assert Repo.aggregate(ProjectionJob, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0

    {:ok, result} = Ingestion.Manager.save(scope, %{"body" => "saved"})
    job = Repo.one!(Oban.Job)
    projection = Repo.get_by!(ProjectionJob, post_id: result.post.id)
    assert job.args == %{"projection_id" => projection.id}
    assert job.worker == "Memovee.Workers.MemoryProjection"
    assert job.queue == "memory_projection"
    assert job.max_attempts == 5
    assert job.state == "available"
    assert {:ok, _} = Memovee.Memory.Post.Manager.update(agent, result.post, %{body: "revised"})
    assert Repo.aggregate(Oban.Job, :count) == 2
    assert Repo.aggregate(ProjectionJob, :count) == 2
  end
end
