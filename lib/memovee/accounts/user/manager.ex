defmodule Memovee.Accounts.User.Manager do
  @moduledoc """
  Owns human authentication persistence and account transactions.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Memovee.Accounts.{Actor, Token, User}
  alias Memovee.Accounts.User.Notifier
  alias Memovee.Repo

  def get_by_email(email) when is_binary(email) do
    active_user_query()
    |> where([user, _actor], user.email == ^email)
    |> preload([_user, actor], actor: actor)
    |> Repo.one()
  end

  def get_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def get!(id), do: User |> Repo.get!(id) |> Repo.preload(:actor)

  def register(attrs) do
    Multi.new()
    |> Multi.insert(:actor, Actor.user_changeset(%Actor{}))
    |> Multi.insert(:user, fn %{actor: actor} ->
      User.email_changeset(%User{actor_id: actor.id}, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, actor: actor}} -> {:ok, %{user | actor: actor}}
      {:error, :user, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def sudo_mode?(user, minutes \\ -10)

  def sudo_mode?(%User{authenticated_at: timestamp}, minutes)
      when is_struct(timestamp, DateTime) do
    DateTime.after?(timestamp, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  def change_email(%User{} = user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  def update_email(%User{} = user, encoded_token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- Token.verify_change_email_token_query(encoded_token, context),
           {%Token{sent_to: email, actor_id: actor_id}, %Actor{id: actor_id}} <- Repo.one(query),
           ^actor_id <- user.actor_id,
           {:ok, updated_user} <- Repo.update(User.email_changeset(user, %{email: email})) do
        tokens_to_expire = delete_all_tokens(actor_id)
        {:ok, {%{updated_user | actor: user.actor}, tokens_to_expire}}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  def change_password(%User{} = user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  def update_password(%User{} = user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  def get_by_magic_link_token(encoded_token) do
    with {:ok, query} <- Token.verify_magic_link_token_query(encoded_token),
         {%User{} = user, _credential, %Actor{} = actor} <- Repo.one(query) do
      %{user | actor: actor}
    else
      _ -> nil
    end
  end

  def login_by_magic_link(encoded_token) do
    with {:ok, query} <- Token.verify_magic_link_token_query(encoded_token) do
      case Repo.one(query) do
        {%User{confirmed_at: nil, hashed_password: hash}, _credential, _actor}
        when not is_nil(hash) ->
          raise """
          magic link log in is not allowed for unconfirmed users with a password set!

          This cannot happen with the default implementation, which indicates that you
          might have adapted the code to a different use case. Please make sure to read the
          "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
          """

        {%User{confirmed_at: nil} = user, _credential, actor} ->
          user
          |> Map.put(:actor, actor)
          |> User.confirm_changeset()
          |> update_user_and_delete_all_tokens()

        {%User{} = user, %Token{} = credential, actor} ->
          Repo.delete!(credential)
          {:ok, {%{user | actor: actor}, []}}

        nil ->
          {:error, :not_found}
      end
    end
  end

  def deliver_update_email_instructions(
        %User{} = user,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, credential} = Token.build_email_token(user, "change:#{current_email}")
    Repo.insert!(credential)
    Notifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, credential} = Token.build_email_token(user, "login")
    Repo.insert!(credential)
    Notifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  defp active_user_query do
    from user in User,
      join: actor in assoc(user, :actor),
      where: actor.type == :user and actor.current_state == "active"
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = delete_all_tokens(user.actor_id)
        {:ok, {%{user | actor: changeset.data.actor}, tokens_to_expire}}
      end
    end)
  end

  defp delete_all_tokens(actor_id) do
    {_count, tokens} =
      Repo.delete_all(
        from credential in Token, where: credential.actor_id == ^actor_id, select: credential
      )

    tokens
  end
end
