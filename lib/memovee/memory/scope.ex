defmodule Memovee.Memory.Scope do
  @moduledoc "Trusted memory ownership resolved from persisted Accounts Actors."
  defstruct [:actor, :owner, :token_actor_id, :origin_identifier, structured?: false]

  defdelegate resolve(actor, attrs), to: __MODULE__.Manager
  defdelegate resolve_ingestion(actor, attrs), to: __MODULE__.Manager
  defdelegate refresh(scope), to: __MODULE__.Manager
end
