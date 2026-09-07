defmodule Memovee.Projections.Indexing.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.Projections.Indexing

  use Eventful,
    parent: {:indexing, Indexing},
    actor: {:actor, Actor},
    table_name: "projections_indexing_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Indexing.Transitions

  handle(:transitions, using: Transitions)
end
