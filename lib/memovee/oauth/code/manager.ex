defmodule Memovee.OAuth.Code.Manager do
  @moduledoc "Owns OAuth authorization-code persistence, locking, consumption, and cleanup."

  import Ecto.Query

  alias Memovee.OAuth
  alias Memovee.OAuth.{Code, Grant, Request}
  alias Memovee.Repo

  def issue(%Grant{} = grant, %Request{} = request, digest) do
    expires_at =
      OAuth.now()
      |> DateTime.add(OAuth.config(:authorization_code_lifetime_seconds), :second)

    %Code{oauth_grant_id: grant.id}
    |> Code.changeset(%{
      code_digest: digest,
      redirect_uri: request.redirect_uri,
      resource: request.resource,
      scope: request.scope,
      code_challenge: request.code_challenge,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  def grant_identity(digest) when is_binary(digest) do
    case Repo.one(
           from code in Code,
             join: grant in Grant,
             on: grant.id == code.oauth_grant_id,
             where: code.code_digest == ^digest,
             select: {grant.id, grant.actor_id}
         ) do
      nil -> {:error, :invalid_grant}
      identity -> {:ok, identity}
    end
  end

  def lock(digest) when is_binary(digest) do
    Code
    |> where([code], code.code_digest == ^digest)
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      %Code{} = code -> {:ok, code}
      nil -> {:error, :invalid_grant}
    end
  end

  def consume(%Code{} = code, now) do
    code
    |> Ecto.Changeset.change(consumed_at: now)
    |> Repo.update()
  end

  def cleanup_candidates(now, batch_size) when is_integer(batch_size) and batch_size > 0 do
    from(code in Code,
      where: code.expires_at <= ^now or not is_nil(code.consumed_at),
      order_by: [asc: code.expires_at, asc: code.id],
      limit: ^batch_size,
      select: {code.id, code.oauth_grant_id}
    )
    |> Repo.all()
  end

  def delete_if_expired(code_id, now) do
    Repo.delete_all(
      from(code in Code,
        where:
          code.id == ^code_id and
            (code.expires_at <= ^now or not is_nil(code.consumed_at))
      )
    )

    :ok
  end

  def delete_for_grant(grant_id) do
    Repo.delete_all(from code in Code, where: code.oauth_grant_id == ^grant_id)
    :ok
  end
end
