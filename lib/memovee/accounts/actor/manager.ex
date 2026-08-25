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
end
