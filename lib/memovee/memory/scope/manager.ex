defmodule Memovee.Memory.Scope.Manager do
  @moduledoc false
  import Ecto.Query
  alias Memovee.Accounts.{Actor, Relationship}
  alias Memovee.Memory.{Context, Scope}
  alias Memovee.Repo

  def resolve_service(actor, attrs) do
    with {:ok, scope} <- resolve(actor, attrs) do
      if scope.service?, do: {:ok, scope}, else: {:error, :forbidden}
    end
  end

  def resolve(%Actor{id: token_id}, attrs) do
    service? = token_id == Application.get_env(:memovee, :memory_tama_actor_id)
    context = Map.get(attrs, "context")

    cond do
      Map.has_key?(attrs, "context") and not service? -> {:error, :forbidden_context}
      service? -> resolve_context(token_id, context)
      true -> resolve_actor(token_id, service?, context)
    end
  end

  def refresh(%Scope{} = scope) do
    if Repo.in_transaction?(), do: lock_principals(scope)

    with %Actor{current_state: "active"} <- Repo.get(Actor, scope.token_actor_id),
         true <- scope.service? or scope.token_actor_id == scope.actor.id,
         true <-
           not scope.service? or
             scope.token_actor_id == Application.get_env(:memovee, :memory_tama_actor_id),
         {:ok, actor, owner} <- owner(scope.actor.id),
         true <- owner.id == scope.owner.id do
      {:ok, %{scope | actor: actor, owner: owner}}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp resolve_context(token_id, attrs) do
    case %Context{} |> Context.changeset(attrs) |> Ecto.Changeset.apply_action(:validate) do
      {:ok, context} -> resolve_actor(token_id, true, context)
      {:error, _changeset} -> {:error, :invalid_context}
    end
  end

  defp lock_principals(scope) do
    ids = Enum.uniq([scope.token_actor_id, scope.actor.id, scope.owner.id])
    Repo.all(from actor in Actor, where: actor.id in ^ids, order_by: actor.id, lock: "FOR SHARE")
  end

  defp resolve_actor(token_id, service?, context) do
    actor_id = if service?, do: context.actor_id, else: token_id

    with %Actor{current_state: "active"} <- Repo.get(Actor, token_id),
         {:ok, actor, owner} <- owner(actor_id) do
      {:ok,
       %Scope{
         actor: actor,
         owner: owner,
         token_actor_id: token_id,
         service?: service?,
         origin_identifier: if(service?, do: context.origin_identifier)
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
