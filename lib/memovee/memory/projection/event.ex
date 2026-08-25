defmodule Memovee.Memory.Projection.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.Memory.Projection

  use Eventful,
    parent: {:projection, Projection},
    actor: {:actor, Actor},
    table_name: "memory_projection_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Projection.Transitions

  handle(:transitions, using: Transitions)
end
