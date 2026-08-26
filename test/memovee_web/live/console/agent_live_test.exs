defmodule MemoveeWeb.Console.AgentLiveTest do
  use MemoveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Memovee.AccountsFixtures

  alias Memovee.Accounts
  alias Memovee.Accounts.{Relationship, Token}
  alias Memovee.Repo

  setup :register_and_log_in_user

  test "lists an empty state and creates an owned agent", %{conn: conn, scope: scope} do
    {:ok, index_view, _html} = live(conn, ~p"/console/agents")
    assert has_element?(index_view, "#agents-index")
    assert has_element?(index_view, "#agents-empty")
    assert has_element?(index_view, "#new-agent-link")

    {:ok, new_view, _html} = live(conn, ~p"/console/agents/new")
    assert has_element?(new_view, "#agent-form")

    new_view
    |> form("#agent-form", agent: %{identifier: "release-runner"})
    |> render_submit()

    {path, _flash} = assert_redirect(new_view)
    assert String.starts_with?(path, "/console/agents/")

    [agent] = Accounts.list_owned_agents(scope.actor)
    assert agent.identifier == "release-runner"
    assert Repo.get_by!(Relationship, target_actor_id: agent.id).actor_id == scope.actor.id
  end

  test "shows a generated secret once and never includes it in the token list", %{
    conn: conn,
    scope: scope
  } do
    agent = agent_fixture(scope.actor)
    {:ok, view, _html} = live(conn, ~p"/console/agents/#{agent.id}")

    html =
      view
      |> form("#token-form", token: %{label: "production", expires_in_days: "90"})
      |> render_submit()

    assert html =~ ~s(id="api-secret")
    assert html =~ ~s(id="api-client-id")
    assert html =~ ~s(id="api-client-secret")

    [_, plaintext_secret] =
      Regex.run(
        ~r/id="api-client-secret"[^>]*>\s*([A-Za-z0-9_-]{43})/s,
        html
      )

    stored = Repo.get_by!(Token, actor_id: agent.id, context: "api")
    refute stored.token == plaintext_secret

    {:ok, reconnected_view, reconnected_html} =
      live(conn, ~p"/console/agents/#{agent.id}")

    refute reconnected_html =~ ~s(id="api-secret")
    refute reconnected_html =~ plaintext_secret
    assert has_element?(reconnected_view, "#tokens-#{stored.id}")
    assert has_element?(reconnected_view, "#revoke-token-#{stored.id}")
  end

  test "revokes a token from its stable row action", %{conn: conn, scope: scope} do
    agent = agent_fixture(scope.actor)
    credential = api_token_fixture(scope.actor, agent)
    {:ok, view, _html} = live(conn, ~p"/console/agents/#{agent.id}")

    view
    |> element("#revoke-token-#{credential.client_id}")
    |> render_click()

    assert Repo.get!(Token, credential.client_id).revoked_at
    refute has_element?(view, "#revoke-token-#{credential.client_id}")
  end

  test "does not expose another owner's agent page", %{conn: conn} do
    other_owner = user_fixture().actor
    agent = agent_fixture(other_owner)

    assert {:error, {:live_redirect, %{to: "/console/agents"}}} =
             live(conn, ~p"/console/agents/#{agent.id}")
  end
end
