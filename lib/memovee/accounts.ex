defmodule Memovee.Accounts do
  @moduledoc """
  The Accounts context.

  Actors are stable account principals. Credentials, provider identities, and
  profiles will be modeled as related schemas.
  """

  alias __MODULE__.Actor

  defdelegate get_actor!(id), to: Actor.Manager, as: :get!

  defdelegate create_actor(), to: Actor.Manager, as: :create

  defdelegate change_actor(actor), to: Actor.Manager, as: :change
end
