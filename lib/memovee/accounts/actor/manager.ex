defmodule Memovee.Accounts.Actor.Manager do
  @moduledoc """
  Creates and retrieves account actors.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Memovee.Accounts.{Actor, Relationship}
  alias Memovee.Repo

  def get!(id), do: Repo.get!(Actor, id)

  def create_user do
    %Actor{}
    |> Actor.user_changeset()
    |> Repo.insert()
  end

  def create_agent(%Actor{id: owner_id}, attrs) do
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

  def list_owned_agents(%Actor{id: owner_id}) do
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

  def get_owned_agent(%Actor{id: owner_id}, agent_id) do
    query =
      from agent in Actor,
        join: relationship in Relationship,
        on:
          relationship.target_actor_id == agent.id and relationship.actor_id == ^owner_id and
            relationship.type == :owner,
        where: agent.id == ^agent_id and agent.type == :agent

    case Repo.one(query) do
      %Actor{} = agent -> {:ok, agent}
      nil -> {:error, :not_found}
    end
  end

  def change(%Actor{} = actor), do: Actor.changeset(actor)

  def change_agent(%Actor{} = actor, attrs \\ %{}), do: Actor.agent_changeset(actor, attrs)

  def activate(%Actor{} = actor, %Actor{} = transitioning_actor) do
    Eventful.Transit.perform(actor, transitioning_actor, "activate")
  end

  def deactivate(%Actor{} = actor, %Actor{} = transitioning_actor) do
    Eventful.Transit.perform(actor, transitioning_actor, "deactivate")
  end
end
