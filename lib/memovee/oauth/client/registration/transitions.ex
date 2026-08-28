defmodule Memovee.OAuth.Client.Registration.Transitions do
  @moduledoc false

  @behaviour Eventful.Handler

  use Eventful.Transition, repo: Memovee.Repo

  alias Memovee.OAuth.Client.Registration

  Registration
  |> transition([from: "pending", to: "active", via: "activate"], fn changes ->
    transit(changes)
  end)

  Registration
  |> transition([from: "active", to: "inactive", via: "deactivate"], fn changes ->
    transit(changes)
  end)
end
