defmodule Memovee.Accounts.Actor.Manager do
  @moduledoc """
  Creates and retrieves account actors.
  """

  alias Memovee.Accounts.Actor
  alias Memovee.Repo

  def get!(id), do: Repo.get!(Actor, id)

  def create_user do
    %Actor{}
    |> Actor.user_changeset()
    |> Repo.insert()
  end

  def change(%Actor{} = actor), do: Actor.changeset(actor)

  def activate(%Actor{} = actor, %Actor{} = transitioning_actor) do
    Eventful.Transit.perform(actor, transitioning_actor, "activate")
  end

  def deactivate(%Actor{} = actor, %Actor{} = transitioning_actor) do
    Eventful.Transit.perform(actor, transitioning_actor, "deactivate")
  end
end
