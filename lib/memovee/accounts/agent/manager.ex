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
    case Repo.one(owned_query(owner_id, agent_id)) do
      {%Actor{} = agent, %Actor{}} -> {:ok, agent}
      nil -> {:error, :not_found}
    end
  end

  def transition(%Actor{id: owner_id}, agent_id, event) when is_atom(event) do
    transition_owned(owner_id, agent_id, Atom.to_string(event))
  end

  def change(%Actor{} = actor, attrs \\ %{}), do: Actor.agent_changeset(actor, attrs)

  defp transition_owned(owner_id, agent_id, transition) do
    Repo.transaction(fn ->
      owner_id
      |> owned_query(agent_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        {%Actor{} = agent, %Actor{} = owner} ->
          perform_transition(agent, owner, transition)

        nil ->
          Repo.rollback(:not_found)
      end
    end)
  end

  defp perform_transition(agent, owner, transition) do
    case Eventful.Transit.perform(agent, owner, transition) do
      {:ok, result} -> result
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc false
  def owned_query(owner_id, agent_id) do
    from agent in Actor,
      join: relationship in Relationship,
      on:
        relationship.target_actor_id == agent.id and relationship.actor_id == ^owner_id and
          relationship.type == :owner,
      join: owner in Actor,
      on: owner.id == relationship.actor_id,
      where:
        agent.id == ^agent_id and agent.type == :agent and owner.type == :user and
          owner.current_state == "active",
      select: {agent, owner}
  end
end
