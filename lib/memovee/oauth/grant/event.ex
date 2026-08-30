defmodule Memovee.OAuth.Grant.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.OAuth.Grant

  use Eventful,
    parent: {:oauth_grant, Grant},
    actor: {:actor, Actor},
    table_name: "oauth_grant_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Grant.Transitions

  handle(:transitions, using: Transitions)
end
