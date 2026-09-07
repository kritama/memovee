defmodule Memovee.Projections.Indexing.Transitions do
  @moduledoc false
  @behaviour Eventful.Handler
  use Eventful.Transition, repo: Memovee.Repo
  alias Memovee.Projections.Indexing
  alias Memovee.Projections.Indexing.Manager

  Indexing
  |> transition([from: "pending", to: "processing", via: "claim"], &Manager.worker_transition/1)

  Indexing
  |> transition([from: "processing", to: "ready", via: "complete"], &Manager.worker_transition/1)

  Indexing
  |> transition([from: "processing", to: "failed", via: "fail"], &Manager.worker_transition/1)

  Indexing
  |> transition([from: "failed", to: "pending", via: "retry"], &Manager.worker_transition/1)

  Indexing
  |> transition(
    [from: "pending", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )

  Indexing
  |> transition(
    [from: "processing", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )

  Indexing
  |> transition(
    [from: "failed", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )

  Indexing
  |> transition(
    [from: "ready", to: "obsolete", via: "invalidate"],
    &Manager.invalidate_transition/1
  )
end
