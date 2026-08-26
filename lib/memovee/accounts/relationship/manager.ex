defmodule Memovee.Accounts.Relationship.Manager do
  @moduledoc """
  Persists trusted Actor relationships.
  """

  alias Memovee.Accounts.{Actor, Relationship}
  alias Memovee.Repo

  def create_owner(%Actor{} = owner, %Actor{} = target) do
    %Relationship{}
    |> Relationship.owner_changeset(owner, target)
    |> Repo.insert()
  end
end
