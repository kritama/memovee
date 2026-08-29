defmodule Memovee.Accounts.Actor.Manager do
  @moduledoc """
  Owns Actor lookup, locking, and trusted lifecycle transitions.
  """

  import Ecto.Query

  alias Memovee.Accounts.Actor
  alias Memovee.Repo

  def get_or_create_agent(identifier) when is_binary(identifier) do
    changeset = Actor.agent_changeset(%Actor{}, %{identifier: identifier})

    if changeset.valid? do
      normalized_identifier = Ecto.Changeset.get_field(changeset, :identifier)

      case Repo.get_by(Actor, identifier: normalized_identifier, type: :agent) do
        %Actor{} = actor -> {:ok, actor}
        nil -> insert_or_reload_agent(changeset, normalized_identifier)
      end
    else
      {:error, changeset}
    end
  end

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
    case Repo.insert(changeset) do
      {:ok, actor} ->
        {:ok, actor}

      {:error, _changeset} = error ->
        case Repo.get_by(Actor, identifier: identifier, type: :agent) do
          %Actor{} = actor -> {:ok, actor}
          nil -> error
        end
    end
  end
end
