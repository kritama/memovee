defmodule Memovee.OAuth.Grant.Transitions do
  @moduledoc false

  @behaviour Eventful.Handler

  use Eventful.Transition, repo: Memovee.Repo

  alias Memovee.OAuth.Grant

  Grant
  |> transition([from: "pending", to: "active", via: "approve"], fn changes ->
    transit(changes)
  end)

  Grant
  |> transition([from: "active", to: "revoked", via: "revoke"], fn changes ->
    transit(changes)
  end)
end
