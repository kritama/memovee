defmodule Memovee.Memory.ProjectionJob.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.Memory.ProjectionJob

  use Eventful,
    parent: {:projection_job, ProjectionJob},
    actor: {:actor, Actor},
    table_name: "memory_projection_job_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias ProjectionJob.Transitions

  handle(:transitions, using: Transitions)
end
