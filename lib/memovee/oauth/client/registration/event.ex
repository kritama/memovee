defmodule Memovee.OAuth.Client.Registration.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.OAuth.Client.Registration

  use Eventful,
    parent: {:oauth_client_registration, Registration},
    actor: {:actor, Actor},
    table_name: "oauth_client_registration_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Registration.Transitions

  handle(:transitions, using: Transitions)
end
