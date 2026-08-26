defmodule Memovee.Accounts.Token.Manager do
  @moduledoc """
  Persists, verifies, and revokes Actor-owned credentials.
  """

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Relationship, Token, User}
  alias Memovee.Accounts.Actor.Manager, as: ActorManager
  alias Memovee.Repo

  @api_context "api"

  def generate_session_token(%User{} = user) do
    {token, credential} = Token.build_session_token(user)
    Repo.insert!(credential)
    token
  end

  def get_user_by_session_token(token) do
    with {:ok, query} <- Token.verify_session_token_query(token),
         {%User{} = user, inserted_at, %Actor{} = actor, authenticated_at} <- Repo.one(query) do
      {%{user | actor: actor, authenticated_at: authenticated_at}, inserted_at}
    else
      _ -> nil
    end
  end

  def delete_session_token(token) do
    Repo.delete_all(from(Token, where: [token: ^token, context: "session"]))
    :ok
  end

  def create_api_token(%Actor{} = owner, agent_id, attrs) do
    with {:ok, agent} <- ActorManager.get_owned_agent(owner, agent_id),
         {client_secret, changeset} <- Token.build_api_token(agent, attrs),
         {:ok, credential} <- Repo.insert(changeset) do
      {:ok,
       %{
         client_id: credential.id,
         client_secret: client_secret,
         expires_at: credential.expires_at
       }}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_api_tokens(%Actor{} = owner, agent_id) do
    with {:ok, agent} <- ActorManager.get_owned_agent(owner, agent_id) do
      tokens =
        from(credential in Token,
          where: credential.actor_id == ^agent.id and credential.context == @api_context,
          order_by: [desc: credential.inserted_at]
        )
        |> Repo.all()

      {:ok, tokens}
    end
  end

  def revoke_api_token(%Actor{id: owner_id}, agent_id, token_id) do
    now = DateTime.utc_now(:microsecond)

    query =
      from credential in Token,
        join: relationship in Relationship,
        on:
          relationship.target_actor_id == credential.actor_id and
            relationship.actor_id == ^owner_id and relationship.type == :owner,
        where:
          credential.id == ^token_id and credential.actor_id == ^agent_id and
            credential.context == @api_context and is_nil(credential.revoked_at)

    case Repo.update_all(query, set: [revoked_at: now]) do
      {1, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  def verify_api_token(client_id, client_secret, @api_context)
      when is_binary(client_id) and is_binary(client_secret) do
    with {:ok, token_id} <- Ecto.UUID.cast(client_id),
         {:ok, secret} <- Base.url_decode64(client_secret, padding: false),
         32 <- byte_size(secret),
         {%Token{} = credential, %Actor{} = actor} <- active_api_credential(token_id),
         true <- secure_digest_match?(credential.token, Token.hash_api_secret(secret)),
         {1, _} <-
           Repo.update_all(
             from(token in Token, where: token.id == ^credential.id),
             set: [authenticated_at: DateTime.utc_now(:microsecond)]
           ) do
      {:ok, actor}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify_api_token(_client_id, _client_secret, _context), do: {:error, :unauthorized}

  defp active_api_credential(token_id) do
    now = DateTime.utc_now(:microsecond)

    from(credential in Token,
      join: actor in assoc(credential, :actor),
      where:
        credential.id == ^token_id and credential.context == @api_context and
          is_nil(credential.revoked_at) and credential.expires_at > ^now and
          actor.type == :agent and actor.current_state == "active",
      select: {credential, actor}
    )
    |> Repo.one()
  end

  defp secure_digest_match?(stored, presented)
       when is_binary(stored) and byte_size(stored) == byte_size(presented) do
    Plug.Crypto.secure_compare(stored, presented)
  end

  defp secure_digest_match?(_stored, _presented), do: false
end
