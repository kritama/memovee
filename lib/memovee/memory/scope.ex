defmodule Memovee.Memory.Scope do
  @moduledoc "Trusted memory ownership resolved from persisted Accounts Actors."
  defstruct [:actor, :owner, :token_actor_id, :origin_identifier, service?: false]

  defdelegate resolve(actor, attrs), to: __MODULE__.Manager
  defdelegate resolve_service(actor, attrs), to: __MODULE__.Manager
  defdelegate refresh(scope), to: __MODULE__.Manager
end
