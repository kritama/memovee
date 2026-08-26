defmodule Memovee.Accounts.Agent.Manager do
  @moduledoc """
  Persists and queries agent Actors through their owners.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Memovee.Accounts.{Actor, Relationship}
  alias Memovee.Repo

  def create(%Actor{id: owner_id}, attrs) do
    Multi.new()
    |> Multi.run(:owner, fn repo, _changes ->
      query =
        from actor in Actor,
          where:
            actor.id == ^owner_id and actor.type == :user and actor.current_state == "active",
          lock: "FOR UPDATE"

      case repo.one(query) do
        %Actor{} = owner -> {:ok, owner}
        nil -> {:error, :unauthorized}
      end
    end)
    |> Multi.insert(:agent, Actor.agent_changeset(%Actor{}, attrs))
    |> Multi.insert(:relationship, fn %{owner: owner, agent: agent} ->
      Relationship.owner_changeset(%Relationship{}, owner, agent)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{agent: agent}} -> {:ok, agent}
      {:error, :agent, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def list_owned(%Actor{id: owner_id}) do
    from(agent in Actor,
      join: relationship in Relationship,
      on:
        relationship.target_actor_id == agent.id and relationship.actor_id == ^owner_id and
          relationship.type == :owner,
      where: agent.type == :agent,
      order_by: [asc: agent.identifier]
    )
    |> Repo.all()
  end

  def get_owned(%Actor{id: owner_id}, agent_id) do
    query =
      from agent in Actor,
        join: relationship in Relationship,
        on:
          relationship.target_actor_id == agent.id and relationship.actor_id == ^owner_id and
            relationship.type == :owner,
        join: owner in Actor,
        on: owner.id == relationship.actor_id,
        where:
          agent.id == ^agent_id and agent.type == :agent and owner.type == :user and
            owner.current_state == "active"

    case Repo.one(query) do
      %Actor{} = agent -> {:ok, agent}
      nil -> {:error, :not_found}
    end
  end

  def change(%Actor{} = actor, attrs \\ %{}), do: Actor.agent_changeset(actor, attrs)
end
