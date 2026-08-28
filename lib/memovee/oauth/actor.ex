defmodule Memovee.OAuth.Actor do
  @moduledoc "Provides the explicit Actor used for automated OAuth lifecycle transitions."

  alias Memovee.Accounts.Actor, as: AccountActor
  alias Memovee.Repo

  @identifier "system:oauth"

  def get do
    case Repo.get_by(AccountActor, identifier: @identifier) do
      %AccountActor{} = actor -> {:ok, actor}
      nil -> create()
    end
  end

  defp create do
    case %AccountActor{}
         |> AccountActor.agent_changeset(%{identifier: @identifier})
         |> Repo.insert() do
      {:ok, actor} -> {:ok, actor}
      {:error, _changeset} -> reload()
    end
  end

  defp reload do
    case Repo.get_by(AccountActor, identifier: @identifier) do
      %AccountActor{} = actor -> {:ok, actor}
      nil -> {:error, :system_actor_unavailable}
    end
  end
end
