defmodule Memovee.Accounts.Actor.Manager do
  @moduledoc """
  Owns Actor lookup, locking, and trusted lifecycle transitions.
  """

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Relationship}
  alias Memovee.Repo

  def get_or_create_agent(identifier) when is_binary(identifier) do
    changeset = Actor.agent_changeset(%Actor{}, %{identifier: identifier})

    if changeset.valid? do
      normalized_identifier = Ecto.Changeset.get_field(changeset, :identifier)
      insert_or_reload_agent(changeset, normalized_identifier)
    else
      {:error, changeset}
    end
  end

  def get_or_create_system_agent("system:" <> suffix = identifier) when suffix != "" do
    with {:ok, actor} <- get_or_create_agent(identifier),
         false <- owned?(actor) do
      {:ok, actor}
    else
      true -> {:error, :system_identifier_owned}
      {:error, _reason} = error -> error
    end
  end

  def get_or_create_system_agent(_identifier), do: {:error, :invalid_system_identifier}

  def get(id, opts \\ []) do
    Actor
    |> where([actor], actor.id == ^id)
    |> maybe_lock(opts)
    |> Repo.one()
    |> case do
      %Actor{} = actor -> {:ok, actor}
      nil -> {:error, :invalid_actor}
    end
  end

  def get_active_user(id, opts \\ []) do
    Actor
    |> where(
      [actor],
      actor.id == ^id and actor.type == :user and actor.current_state == "active"
    )
    |> maybe_lock(opts)
    |> Repo.one()
    |> case do
      %Actor{} = actor -> {:ok, actor}
      nil -> {:error, :inactive_actor}
    end
  end

  def transition(%Actor{} = actor, %Actor{} = transitioning_actor, event) when is_atom(event) do
    Eventful.Transit.perform(actor, transitioning_actor, Atom.to_string(event))
  end

  defp maybe_lock(query, opts) do
    case Keyword.get(opts, :lock) do
      :share -> lock(query, "FOR SHARE")
      :update -> lock(query, "FOR UPDATE")
      nil -> query
    end
  end

  defp insert_or_reload_agent(changeset, identifier) do
    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:identifier]) do
      {:ok, _actor} -> reload_agent(identifier)
      {:error, _changeset} = error -> error
    end
  end

  defp reload_agent(identifier) do
    case Repo.get_by(Actor, identifier: identifier, type: :agent) do
      %Actor{} = actor -> {:ok, actor}
      nil -> {:error, :invalid_actor}
    end
  end

  defp owned?(%Actor{id: actor_id}) do
    Relationship
    |> where([relationship], relationship.target_actor_id == ^actor_id)
    |> Repo.exists?()
  end
end
