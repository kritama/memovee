defmodule Memovee.Memory.Projection.Transitions do
  @moduledoc false

  @behaviour Eventful.Handler

  use Eventful.Transition, repo: Memovee.Repo

  alias Memovee.Memory.Projection
  alias Memovee.Memory.Projection.Manager

  Projection
  |> transition(
    [from: "pending", to: "syncing", via: "sync"],
    &Manager.transition/1
  )

  Projection
  |> transition(
    [from: "syncing", to: "synced", via: "complete"],
    fn changes -> Manager.complete_transition(changes) end
  )

  Projection
  |> transition(
    [from: "syncing", to: "failed", via: "fail"],
    &Manager.transition/1
  )

  Projection
  |> transition(
    [from: "failed", to: "syncing", via: "retry"],
    &Manager.transition/1
  )

  Projection
  |> transition(
    [from: "synced", to: "pending", via: "invalidate"],
    &Manager.transition/1
  )

  Projection
  |> transition(
    [from: "failed", to: "pending", via: "invalidate"],
    &Manager.transition/1
  )

  Projection
  |> transition(
    [from: "syncing", to: "pending", via: "invalidate"],
    &Manager.transition/1
  )
end
