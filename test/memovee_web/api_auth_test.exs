defmodule MemoveeWeb.ApiAuthTest do
  use MemoveeWeb.ConnCase, async: true

  import Memovee.AccountsFixtures

  alias Memovee.Accounts

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    credential = api_token_fixture(owner, agent)

    %{owner: owner, agent: agent, credential: credential}
  end

  test "assigns an Actor-only scope for a valid Bearer credential", %{
    conn: conn,
    agent: agent,
    credential: credential
  } do
    conn =
      conn
      |> put_req_header("authorization", bearer(credential))
      |> get(~p"/api/principal")

    assert %{
             "data" => %{
               "id" => id,
               "identifier" => identifier,
               "type" => "agent"
             }
           } = json_response(conn, 200)

    assert id == agent.id
    assert identifier == agent.identifier
    assert conn.assigns.current_scope.actor.id == agent.id
    assert is_nil(conn.assigns.current_scope.user)
  end

  test "returns the same JSON 401 for missing, malformed, and incorrect credentials", %{
    conn: conn,
    credential: credential
  } do
    invalid_headers = [
      nil,
      "Basic anything",
      "Bearer malformed",
      "Bearer #{credential.client_id}.short",
      "Bearer #{credential.client_id}.#{Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)}"
    ]

    responses =
      Enum.map(invalid_headers, fn header ->
        request_conn =
          if header do
            put_req_header(conn, "authorization", header)
          else
            conn
          end

        request_conn
        |> get(~p"/api/principal")
        |> json_response(401)
      end)

    assert Enum.uniq(responses) == [%{"error" => "unauthorized"}]
  end

  test "Actor deactivation invalidates a previously valid Bearer credential", %{
    conn: conn,
    owner: owner,
    agent: agent,
    credential: credential
  } do
    assert {:ok, %{resource: _inactive_agent}} =
             Accounts.transition_actor(agent, owner, :deactivate)

    conn =
      conn
      |> put_req_header("authorization", bearer(credential))
      |> get(~p"/api/principal")

    assert json_response(conn, 401) == %{"error" => "unauthorized"}
  end

  defp bearer(credential) do
    "Bearer #{credential.client_id}.#{credential.client_secret}"
  end
end
