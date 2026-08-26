defmodule Memovee.Accounts.Actor.Manager do
  @moduledoc """
  Performs trusted Actor lifecycle transitions.
  """

  alias Memovee.Accounts.Actor

  def transition(%Actor{} = actor, %Actor{} = transitioning_actor, event) when is_atom(event) do
    Eventful.Transit.perform(actor, transitioning_actor, Atom.to_string(event))
  end
end
