defmodule Memovee.OAuth.Access.Manager do
  @moduledoc "Owns OAuth access associations, refresh families, and binding queries."

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Token}
  alias Memovee.OAuth.{Access, Grant}
  alias Memovee.Repo

  def create(%Token{} = token, %Grant{} = grant, attrs) do
    token
    |> Access.changeset(grant, attrs)
    |> Repo.insert()
  end

  def refresh_grant_identity(digest) when is_binary(digest) do
    case Repo.one(
           from token in Token,
             join: access in Access,
             on: access.actor_token_id == token.id,
             join: grant in Grant,
             on: grant.id == access.oauth_grant_id,
             where: token.context == "oauth_refresh" and token.token == ^digest,
             select: {grant.id, grant.actor_id}
         ) do
      nil -> {:error, :invalid_grant}
      identity -> {:ok, identity}
    end
  end

  def grant_identity_for_access(token_id, claims) when is_map(claims) do
    subject = claims["sub"]
    client_id = claims["client_id"]
    audience = claims["aud"]
    scope = claims["scope"]

    Repo.one(
      from token in Token,
        join: access in Access,
        on: access.actor_token_id == token.id,
        join: grant in Grant,
        on: grant.id == access.oauth_grant_id,
        where:
          token.id == ^token_id and token.context == "oauth_access" and
            token.actor_id == ^subject and grant.oauth_client_id == ^client_id and
            grant.resource == ^audience and grant.scope == ^scope,
        select: {grant.id, grant.actor_id}
    )
  end

  def lock_for_token(token_id) do
    Access
    |> where([access], access.actor_token_id == ^token_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %Access{} = access -> {:ok, access}
      nil -> {:error, :invalid_grant}
    end
  end

  def rotate(%Access{} = access, now) do
    access
    |> Ecto.Changeset.change(rotated_at: now)
    |> Repo.update()
  end

  def active_reference(token_id, now) do
    from(token in Token,
      join: access in Access,
      on: access.actor_token_id == token.id,
      join: grant in Grant,
      on: grant.id == access.oauth_grant_id,
      join: actor in Actor,
      on: actor.id == token.actor_id,
      where:
        token.id == ^token_id and token.context == "oauth_access" and
          is_nil(token.revoked_at) and token.expires_at > ^now and grant.current_state == "active" and
          actor.type == :user and actor.current_state == "active",
      select: {token, access, grant, actor}
    )
    |> Repo.one()
  end

  def active_refresh_token_ids_query(grant_id) do
    from access in Access,
      join: token in Token,
      on: token.id == access.actor_token_id,
      where:
        access.oauth_grant_id == ^grant_id and token.context == "oauth_refresh" and
          is_nil(token.revoked_at),
      select: token.id
  end

  def token_cleanup_candidates(now, batch_size)
      when is_integer(batch_size) and batch_size > 0 do
    active_refresh_families =
      from(refresh_access in Access,
        join: refresh_token in Token,
        on: refresh_token.id == refresh_access.actor_token_id,
        where:
          refresh_token.context == "oauth_refresh" and is_nil(refresh_token.revoked_at) and
            refresh_token.expires_at > ^now,
        distinct: true,
        select: refresh_access.family_id
      )

    from(token in Token,
      join: access in Access,
      on: access.actor_token_id == token.id,
      where:
        ((token.context == "oauth_refresh" and token.expires_at <= ^now) or
           (token.context == "oauth_access" and
              (token.expires_at <= ^now or not is_nil(token.revoked_at)))) and
          access.family_id not in subquery(active_refresh_families),
      order_by: [asc: token.expires_at, asc: token.id],
      limit: ^batch_size,
      select: {token.id, access.oauth_grant_id}
    )
    |> Repo.all()
  end

  def family_token_ids_query(family_id) do
    from access in Access,
      where: access.family_id == ^family_id,
      select: access.actor_token_id
  end

  def grant_token_ids_query(grant_id) do
    from access in Access,
      where: access.oauth_grant_id == ^grant_id,
      select: access.actor_token_id
  end
end
