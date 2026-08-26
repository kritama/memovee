defmodule MemoveeWeb.Console.AgentLiveTest do
  use MemoveeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Memovee.AccountsFixtures

  alias Memovee.Accounts
  alias Memovee.Accounts.{Actor, Agent, Relationship, Token}
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

    [agent] = Agent.list_owned(scope.actor)
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

    assert has_element?(view, "#api-secret")
    assert has_element?(view, "#api-client-id")
    assert has_element?(view, "#api-client-secret")

    plaintext_secret =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#api-client-secret")
      |> LazyHTML.text()
      |> String.trim()

    assert plaintext_secret =~ ~r/\A[A-Za-z0-9_-]{43}\z/

    stored = Repo.get_by!(Token, actor_id: agent.id, context: "api")
    refute stored.token == plaintext_secret
    assert has_element?(view, "#tokens-#{stored.id}")

    {:ok, reconnected_view, reconnected_html} =
      live(conn, ~p"/console/agents/#{agent.id}")

    refute has_element?(reconnected_view, "#api-secret")

    reconnected_text =
      reconnected_html
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()

    refute reconnected_text =~ plaintext_secret
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

  test "rejects token creation when the agent became inactive after mount", %{
    conn: conn,
    scope: scope
  } do
    agent = agent_fixture(scope.actor)
    {:ok, view, _html} = live(conn, ~p"/console/agents/#{agent.id}")
    token_count = Repo.aggregate(Token, :count)

    assert {:ok, %{resource: _inactive_agent}} =
             Agent.transition(scope.actor, agent.id, :deactivate)

    view
    |> form("#token-form", token: %{label: "stale-view", expires_in_days: "90"})
    |> render_submit()

    assert has_element?(view, "#token-form")
    assert Repo.aggregate(Token, :count) == token_count
  end

  test "deactivates and reactivates an owned agent", %{conn: conn, scope: scope} do
    agent = agent_fixture(scope.actor)
    {:ok, view, _html} = live(conn, ~p"/console/agents/#{agent.id}")

    view
    |> element("#deactivate-agent-button")
    |> render_click()

    assert Repo.get!(Actor, agent.id).current_state == "inactive"
    assert has_element?(view, "#activate-agent-button")

    view
    |> element("#activate-agent-button")
    |> render_click()

    assert Repo.get!(Actor, agent.id).current_state == "active"
    assert has_element?(view, "#deactivate-agent-button")
  end

  test "a stale LiveView cannot reactivate an agent after its owner is deactivated", %{
    conn: conn,
    scope: scope
  } do
    agent = agent_fixture(scope.actor)
    credential = api_token_fixture(scope.actor, agent)

    assert {:ok, %{resource: inactive_agent}} =
             Agent.transition(scope.actor, agent.id, :deactivate)

    assert inactive_agent.current_state == "inactive"

    {:ok, view, _html} = live(conn, ~p"/console/agents/#{agent.id}")
    transitioning_actor = user_fixture().actor

    assert {:ok, %{resource: inactive_owner}} =
             Accounts.transition_actor(scope.actor, transitioning_actor, :deactivate)

    assert inactive_owner.current_state == "inactive"

    view
    |> element("#activate-agent-button")
    |> render_click()

    assert Repo.get!(Actor, agent.id).current_state == "inactive"
    assert has_element?(view, "#activate-agent-button")

    view
    |> element("#revoke-token-#{credential.client_id}")
    |> render_click()

    refute Repo.get!(Token, credential.client_id).revoked_at
    assert has_element?(view, "#revoke-token-#{credential.client_id}")

    assert {:error, :unauthorized} =
             Accounts.verify_api_token(
               credential.client_id,
               credential.client_secret
             )
  end

  test "does not expose another owner's agent page", %{conn: conn} do
    other_owner = user_fixture().actor
    agent = agent_fixture(other_owner)

    assert {:error, {:live_redirect, %{to: "/console/agents"}}} =
             live(conn, ~p"/console/agents/#{agent.id}")
  end
end
