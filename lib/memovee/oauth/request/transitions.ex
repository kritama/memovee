defmodule Memovee.OAuth.Request.Transitions do
  @moduledoc false

  @behaviour Eventful.Handler

  use Eventful.Transition, repo: Memovee.Repo

  alias Memovee.OAuth.Request

  Request
  |> transition([from: "pending", to: "approved", via: "approve"], fn changes ->
    transit(changes)
  end)

  Request
  |> transition([from: "pending", to: "denied", via: "deny"], fn changes ->
    transit(changes)
  end)

  Request
  |> transition([from: "pending", to: "expired", via: "expire"], fn changes ->
    transit(changes)
  end)
end
