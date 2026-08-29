defmodule Memovee.OAuth.CleanupTest do
  use Memovee.DataCase, async: false

  import Memovee.AccountsFixtures
  import Memovee.OAuthFixtures

  alias Memovee.Accounts.Token
  alias Memovee.OAuth
  alias Memovee.OAuth.{Access, Cleanup, Client, Code, Grant}
  alias Memovee.OAuth.Grant.Event, as: GrantEvent
  alias Memovee.Repo

  test "credential cleanup uses bounded batches" do
    original_config = Application.fetch_env!(:memovee, OAuth)
    on_exit(fn -> Application.put_env(:memovee, OAuth, original_config) end)

    Application.put_env(
      :memovee,
      OAuth,
      Keyword.put(original_config, :credential_cleanup_batch_size, 1)
    )

    now = OAuth.now()
    expired_at = DateTime.add(now, -1, :second)
    scope = user_scope_fixture()

    authorize(scope)
    authorize(scope)
    Repo.update_all(Code, set: [expires_at: expired_at])

    Enum.each(["first", "second"], fn value ->
      %Client.Replay{}
      |> Client.Replay.changeset(:crypto.hash(:sha256, value), expired_at)
      |> Repo.insert!()
    end)

    grant = Repo.one!(Grant)

    Enum.each(1..2, fn _index ->
      token =
        scope.actor
        |> Token.build_oauth_access_reference(expired_at)
        |> Repo.insert!()

      token
      |> Access.changeset(grant, %{family_id: Ecto.UUID.generate()})
      |> Repo.insert!()
    end)

    assert {:ok, :ok} = Cleanup.run_once()
    assert Repo.aggregate(Client.Replay, :count) == 1
    assert Repo.aggregate(Code, :count) == 1

    assert Repo.aggregate(from(token in Token, where: token.context == "oauth_access"), :count) ==
             1
  end

  test "cleanup removes retained revoked grants, credentials, codes, and events" do
    scope = user_scope_fixture()

    first = authorize_and_revoke(scope)
    second = authorize_and_revoke(scope)
    old = DateTime.add(OAuth.now(), -91, :day)

    Repo.update_all(
      from(event in GrantEvent,
        where:
          event.oauth_grant_id == ^first.grant.id and event.name == "revoke" and
            event.domain == "transitions"
      ),
      set: [inserted_at: old]
    )

    assert Repo.get!(Grant, first.grant.id)
    assert Repo.get!(Grant, second.grant.id)

    assert {:ok, :ok} = Cleanup.run_once()

    refute Repo.get(Grant, first.grant.id)
    refute Repo.get_by(GrantEvent, oauth_grant_id: first.grant.id)
    refute Repo.exists?(from access in Access, where: access.oauth_grant_id == ^first.grant.id)
    refute Repo.exists?(from code in Code, where: code.oauth_grant_id == ^first.grant.id)
    assert Repo.get!(Grant, second.grant.id)
    assert Repo.get_by!(GrantEvent, oauth_grant_id: second.grant.id, name: "revoke")
  end

  defp authorize_and_revoke(scope) do
    %{code: code} = authorize(scope)
    assert {:ok, tokens} = exchange_code(code)
    grant = Repo.one!(from grant in Grant, where: grant.current_state == "active")

    assert {:ok, :ok} =
             OAuth.revoke(%{
               "token" => tokens["access_token"],
               "client_id" => client_id(),
               "token_type_hint" => "access_token"
             })

    %{grant: grant, tokens: tokens}
  end
end
