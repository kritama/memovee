defmodule MemoveeWeb.Tama.HealthControllerTest do
  use MemoveeWeb.ConnCase, async: true

  import Memovee.AccountsFixtures
  import OpenApiSpex.TestAssertions

  setup do
    owner = user_fixture().actor
    first_agent = agent_fixture(owner)
    second_agent = agent_fixture(owner)

    %{
      first_token: api_token_fixture(owner, first_agent),
      second_token: api_token_fixture(owner, second_agent)
    }
  end

  test "validates credentials for any active Agent", %{first_token: first, second_token: second} do
    for token <- [first, second] do
      conn = token |> authorize() |> get(~p"/tama/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
      assert_operation_response(conn, "tama_health_show")
    end
  end

  test "rejects missing and invalid credentials" do
    assert build_conn() |> get(~p"/tama/health") |> json_response(401) ==
             %{"error" => "unauthorized"}

    assert build_conn()
           |> put_req_header("authorization", "Bearer invalid")
           |> get(~p"/tama/health")
           |> json_response(401) == %{"error" => "unauthorized"}
  end

  defp authorize(token) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token.client_id}.#{token.client_secret}")
  end
end
