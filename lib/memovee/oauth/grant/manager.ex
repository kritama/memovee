defmodule Memovee.OAuth.Grant.Manager do
  @moduledoc "Persistence and lifecycle orchestration for OAuth grants."

  import Ecto.Query

  alias Memovee.Accounts.Actor
  alias Memovee.OAuth.{Grant, Request}
  alias Memovee.Repo

  def resolve_for_approval(%Actor{} = actor, %Request{} = request) do
    query =
      from grant in Grant,
        where:
          grant.actor_id == ^actor.id and grant.oauth_client_id == ^request.client_id and
            grant.resource == ^request.resource and grant.current_state == "active",
        lock: "FOR UPDATE"

    case Repo.one(query) do
      %Grant{scope: scope} = grant when scope == request.scope -> {:ok, grant}
      %Grant{} = grant -> replace(grant, actor, request)
      nil -> create(actor, request)
    end
  end

  def lock(id) do
    Grant
    |> where([grant], grant.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %Grant{} = grant -> {:ok, grant}
      nil -> {:error, :invalid_grant}
    end
  end

  def revoke(%Grant{current_state: "active"} = grant, %Actor{} = actor) do
    transition(grant, actor, "revoke")
  end

  def revoke(%Grant{} = grant, %Actor{}), do: {:ok, grant}

  def active_client_ids_query do
    from grant in Grant,
      where: grant.current_state == "active",
      distinct: true,
      select: %{client_id: grant.oauth_client_id}
  end

  def active_for_client?(client_id) do
    Repo.exists?(
      from(grant in Grant,
        where: grant.oauth_client_id == ^client_id and grant.current_state == "active"
      )
    )
  end

  defp replace(grant, actor, request) do
    with {:ok, _grant} <- revoke(grant, actor) do
      create(actor, request)
    end
  end

  defp create(actor, request) do
    %Grant{actor_id: actor.id}
    |> Grant.changeset(%{
      oauth_client_id: request.client_id,
      resource: request.resource,
      scope: request.scope
    })
    |> Repo.insert()
    |> case do
      {:ok, grant} -> transition(grant, actor, "approve")
      error -> error
    end
  end

  defp transition(grant, actor, event_name) do
    case Eventful.Transit.perform(grant, actor, event_name) do
      {:ok, %{resource: transitioned}} -> {:ok, transitioned}
      error -> error
    end
  end
end
