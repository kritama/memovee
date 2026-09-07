defmodule Memovee.Memory.ProjectionJob.Transitions do
  @moduledoc false
  @behaviour Eventful.Handler
  use Eventful.Transition, repo: Memovee.Repo
  alias Memovee.Memory.ProjectionJob
  alias Memovee.Memory.ProjectionJob.Manager

  ProjectionJob
  |> transition([from: "pending", to: "processing", via: "claim"], &Manager.worker_transition/1)

  ProjectionJob
  |> transition([from: "processing", to: "ready", via: "complete"], &Manager.worker_transition/1)

  ProjectionJob
  |> transition([from: "processing", to: "failed", via: "fail"], &Manager.worker_transition/1)

  ProjectionJob
  |> transition([from: "failed", to: "pending", via: "retry"], &Manager.worker_transition/1)

  ProjectionJob
  |> transition(
    [from: "pending", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )

  ProjectionJob
  |> transition(
    [from: "processing", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )

  ProjectionJob
  |> transition(
    [from: "failed", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )

  ProjectionJob
  |> transition(
    [from: "ready", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )
end
