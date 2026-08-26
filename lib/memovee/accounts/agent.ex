defmodule Memovee.Accounts.Agent do
  @moduledoc """
  Manages agent Actors and their ownership relationships.

  Agents are represented by `Memovee.Accounts.Actor` records with type `:agent`.
  """

  alias __MODULE__.Manager

  defdelegate create(owner, attrs), to: Manager
  defdelegate list_owned(owner), to: Manager
  defdelegate get_owned(owner, id), to: Manager
  defdelegate change(actor, attrs \\ %{}), to: Manager
end
