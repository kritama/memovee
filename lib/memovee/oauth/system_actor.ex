defmodule Memovee.OAuth.SystemActor do
  @moduledoc "Provides the explicit Actor used for automated OAuth lifecycle transitions."

  alias Memovee.Accounts.Actor
  alias Memovee.Repo

  @identifier "system:oauth"

  def get do
    case Repo.get_by(Actor, identifier: @identifier) do
      %Actor{} = actor -> {:ok, actor}
      nil -> create()
    end
  end

  defp create do
    case %Actor{} |> Actor.agent_changeset(%{identifier: @identifier}) |> Repo.insert() do
      {:ok, actor} -> {:ok, actor}
      {:error, _changeset} -> reload()
    end
  end

  defp reload do
    case Repo.get_by(Actor, identifier: @identifier) do
      %Actor{} = actor -> {:ok, actor}
      nil -> {:error, :system_actor_unavailable}
    end
  end
end
