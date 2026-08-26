defmodule Memovee.Accounts.Actor.Transitions do
  @moduledoc false

  @behaviour Eventful.Handler

  use Eventful.Transition, repo: Memovee.Repo

  alias Memovee.Accounts.Actor

  Actor
  |> transition(
    [from: "active", to: "inactive", via: "deactivate"],
    fn changes -> transit(changes) end
  )

  Actor
  |> transition(
    [from: "inactive", to: "active", via: "activate"],
    fn changes -> transit(changes) end
  )
end
