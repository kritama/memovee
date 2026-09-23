defmodule Memovee.Memory.Scope.Manager do
  @moduledoc false
  import Ecto.Query
  alias Memovee.Accounts.{Actor, Relationship}
  alias Memovee.Memory.{Context, Scope}
  alias Memovee.Repo

  def resolve_ingestion(actor, attrs) do
    with {:ok, scope} <- resolve(actor, attrs) do
      if scope.structured?, do: {:ok, scope}, else: {:error, :invalid_context}
    end
  end

  def resolve(%Actor{id: token_id}, attrs) do
    case Map.fetch(attrs, "context") do
      {:ok, context} -> resolve_context(token_id, context)
      :error -> resolve_actor(token_id, nil)
    end
  end

  def refresh(%Scope{} = scope) do
    if Repo.in_transaction?(), do: lock_principals(scope)

    with {:ok, _token_actor, token_owner} <- owner(scope.token_actor_id),
         true <- scope.structured? or scope.token_actor_id == scope.actor.id,
         {:ok, actor, owner} <- owner(scope.actor.id),
         true <- token_owner.id == owner.id,
         true <- owner.id == scope.owner.id do
      {:ok, %{scope | actor: actor, owner: owner}}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp resolve_context(token_id, attrs) do
    case %Context{} |> Context.changeset(attrs) |> Ecto.Changeset.apply_action(:validate) do
      {:ok, context} -> resolve_actor(token_id, context)
      {:error, _changeset} -> {:error, :invalid_context}
    end
  end

  defp lock_principals(scope) do
    ids = Enum.uniq([scope.token_actor_id, scope.actor.id, scope.owner.id])
    Repo.all(from actor in Actor, where: actor.id in ^ids, order_by: actor.id, lock: "FOR SHARE")
  end

  defp resolve_actor(token_id, context) do
    actor_id = if context, do: context.actor_id, else: token_id

    with {:ok, _token_actor, token_owner} <- owner(token_id),
         {:ok, actor, owner} <- owner(actor_id),
         true <- token_owner.id == owner.id do
      {:ok,
       %Scope{
         actor: actor,
         owner: owner,
         token_actor_id: token_id,
         structured?: not is_nil(context),
         origin_identifier: if(context, do: context.origin_identifier)
       }}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp owner(id) do
    case Repo.get(Actor, id) do
      %Actor{type: :user, current_state: "active"} = actor ->
        {:ok, actor, actor}

      %Actor{type: :agent, current_state: "active"} = actor ->
        query =
          from owner in Actor,
            join: relationship in Relationship,
            on: relationship.actor_id == owner.id,
            where:
              relationship.target_actor_id == ^id and relationship.type == :owner and
                owner.type == :user and owner.current_state == "active"

        case Repo.one(query) do
          %Actor{} = owner -> {:ok, actor, owner}
          nil -> {:error, :forbidden}
        end

      _ ->
        {:error, :forbidden}
    end
  end
end
