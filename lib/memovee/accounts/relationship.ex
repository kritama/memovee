defmodule Memovee.Accounts.Relationship do
  @moduledoc """
  A trusted relationship between an owning Actor and an agent Actor.
  """

  use Memovee.Schema

  alias Memovee.Accounts.Actor

  schema "actor_relationships" do
    field :type, Ecto.Enum, values: [:owner]

    belongs_to :actor, Actor
    belongs_to :target_actor, Actor

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def owner_changeset(relationship, %Actor{} = owner, %Actor{} = target) do
    relationship
    |> cast(%{}, [])
    |> put_change(:actor_id, owner.id)
    |> put_change(:target_actor_id, target.id)
    |> put_change(:type, :owner)
    |> validate_required([:actor_id, :target_actor_id, :type])
    |> check_constraint(:target_actor_id, name: :actor_relationships_distinct_actors_check)
    |> unique_constraint(:target_actor_id)
  end
end
