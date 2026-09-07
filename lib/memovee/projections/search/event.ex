defmodule Memovee.Projections.Search.Event do
  @moduledoc false

  alias Memovee.Accounts.Actor
  alias Memovee.Projections.Search

  use Eventful,
    parent: {:search, Search},
    actor: {:actor, Actor},
    table_name: "projections_search_events",
    binary_id: Memovee.Eventful.UUIDv7

  alias Search.Transitions

  handle(:transitions, using: Transitions)
end
