defmodule Memovee.Accounts.Actor.Manager do
  @moduledoc """
  Creates and retrieves account actors.
  """

  alias Memovee.Accounts.Actor
  alias Memovee.Repo

  def get!(id), do: Repo.get!(Actor, id)

  def create do
    %Actor{}
    |> Actor.changeset()
    |> Repo.insert()
  end

  def change(%Actor{} = actor), do: Actor.changeset(actor)

  def activate(%Actor{} = actor, %Actor{} = transitioning_actor) do
    Eventful.Transit.perform(transitioning_actor, actor, "activate")
  end

  def deactivate(%Actor{} = actor, %Actor{} = transitioning_actor) do
    Eventful.Transit.perform(transitioning_actor, actor, "deactivate")
  end
end
