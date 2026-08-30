defmodule Memovee.OAuth.Actor do
  @moduledoc "Provides the explicit Actor used for automated OAuth lifecycle transitions."

  alias Memovee.Accounts.Actor.Manager, as: ActorManager

  @identifier "system:oauth"

  def get do
    case ActorManager.get_or_create_system_agent(@identifier) do
      {:ok, actor} -> {:ok, actor}
      {:error, _reason} -> {:error, :system_actor_unavailable}
    end
  end
end
