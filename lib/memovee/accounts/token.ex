defmodule Memovee.Accounts.Token do
  @moduledoc """
  Actor-owned credentials with purpose-specific constructors and verifiers.
  """

  use Memovee.Schema

  import Ecto.Query

  alias Memovee.Accounts.{Actor, Token, User}

  @hash_algorithm :sha256
  @rand_size 32
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14

  schema "actor_tokens" do
    field :token, :binary, redact: true
    field :context, :string
    field :sent_to, :string
    field :label, :string
    field :authenticated_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :actor, Actor
    has_one :user, through: [:actor, :user]

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_session_token(%User{actor_id: actor_id} = user) when not is_nil(actor_id) do
    token = :crypto.strong_rand_bytes(@rand_size)
    authenticated_at = normalize_usec(user.authenticated_at || DateTime.utc_now(:microsecond))

    {token,
     %Token{
       actor_id: actor_id,
       token: token,
       context: "session",
       authenticated_at: authenticated_at
     }}
  end

  def verify_session_token_query(token) do
    query =
      from credential in by_token_and_context_query(token, "session"),
        join: actor in assoc(credential, :actor),
        join: user in assoc(actor, :user),
        where:
          actor.type == :user and actor.current_state == "active" and
            credential.inserted_at > ago(@session_validity_in_days, "day"),
        select: {user, credential.inserted_at, actor, credential.authenticated_at}

    {:ok, query}
  end

  def build_email_token(%User{} = user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(%User{actor_id: actor_id}, context, sent_to)
       when not is_nil(actor_id) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Token{
       actor_id: actor_id,
       token: hashed_token,
       context: context,
       sent_to: sent_to
     }}
  end

  def verify_magic_link_token_query(token) do
    with {:ok, decoded_token} <- Base.url_decode64(token, padding: false) do
      hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

      query =
        from credential in by_token_and_context_query(hashed_token, "login"),
          join: actor in assoc(credential, :actor),
          join: user in assoc(actor, :user),
          where:
            actor.type == :user and actor.current_state == "active" and
              credential.inserted_at > ago(^@magic_link_validity_in_minutes, "minute") and
              credential.sent_to == user.email,
          select: {user, credential, actor}

      {:ok, query}
    end
  end

  def verify_change_email_token_query(token, "change:" <> _ = context) do
    with {:ok, decoded_token} <- Base.url_decode64(token, padding: false) do
      hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

      query =
        from credential in by_token_and_context_query(hashed_token, context),
          join: actor in assoc(credential, :actor),
          where:
            actor.type == :user and actor.current_state == "active" and
              credential.inserted_at > ago(@change_email_validity_in_days, "day"),
          select: {credential, actor}

      {:ok, query}
    end
  end

  def build_api_token(%Actor{type: :agent, current_state: "active", id: actor_id}, attrs) do
    secret = :crypto.strong_rand_bytes(@rand_size)
    encoded_secret = Base.url_encode64(secret, padding: false)

    changeset =
      %Token{
        actor_id: actor_id,
        token: :crypto.hash(@hash_algorithm, secret),
        context: "api"
      }
      |> cast(attrs, [:label, :expires_at])
      |> validate_required([:label, :expires_at])
      |> validate_length(:label, max: 160)
      |> validate_expiry()
      |> unique_constraint([:context, :token])

    {:ok, encoded_secret, changeset}
  end

  def build_api_token(%Actor{}, _attrs), do: {:error, :inactive_actor}

  def hash_api_secret(secret) when is_binary(secret), do: :crypto.hash(@hash_algorithm, secret)

  defp normalize_usec(datetime) do
    datetime
    |> DateTime.to_unix(:microsecond)
    |> DateTime.from_unix!(:microsecond)
  end

  defp validate_expiry(changeset) do
    validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if DateTime.after?(expires_at, DateTime.utc_now(:microsecond)) do
        []
      else
        [expires_at: "must be in the future"]
      end
    end)
  end

  defp by_token_and_context_query(token, context) do
    from Token, where: [token: ^token, context: ^context]
  end
end
