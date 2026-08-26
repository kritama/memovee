defmodule Memovee.Accounts.Actor.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor

  use Eventful,
    parent: {:transitioning_actor, Actor},
    actor: {:actor, Actor},
    binary_id: Memovee.Eventful.UUIDv7

  alias Actor.Transitions

  handle(:transitions, using: Transitions)
end
