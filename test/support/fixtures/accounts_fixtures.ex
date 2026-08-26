defmodule Memovee.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Memovee.Accounts` context.
  """

  import Ecto.Query

  alias Memovee.Accounts
  alias Memovee.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def unique_agent_identifier, do: "agent-#{System.unique_integer([:positive])}"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def agent_fixture(owner, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{identifier: unique_agent_identifier()})
    {:ok, agent} = Accounts.create_agent(owner, attrs)
    agent
  end

  def api_token_fixture(owner, agent, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        label: "test credential",
        expires_at: DateTime.utc_now(:microsecond) |> DateTime.add(30, :day)
      })

    {:ok, credential} = Accounts.create_agent_api_token(owner, agent.id, attrs)
    credential
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Memovee.Repo.update_all(
      from(t in Accounts.Token,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.Token.build_email_token(user, "login")
    Memovee.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Memovee.Repo.update_all(
      from(ut in Accounts.Token, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
