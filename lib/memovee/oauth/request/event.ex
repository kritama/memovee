defmodule Memovee.OAuth.Request.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.OAuth.Request

  use Eventful,
    parent: {:oauth_request, Request},
    actor: {:actor, Actor},
    table_name: "oauth_request_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Request.Transitions

  handle(:transitions, using: Transitions)
end
