defmodule MemoveeWeb.Tama.Memory.PostReplayTest do
  use MemoveeWeb.ConnCase, async: false
  import Memovee.AccountsFixtures
  import OpenApiSpex.TestAssertions

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    service = agent_fixture(owner)
    credential = api_token_fixture(owner, service)
    ordinary = api_token_fixture(owner, agent)
    previous = Application.get_env(:memovee, :memory_tama_actor_id)
    Application.put_env(:memovee, :memory_tama_actor_id, service.id)
    on_exit(fn -> Application.put_env(:memovee, :memory_tama_actor_id, previous) end)

    %{
      credential: credential,
      ordinary: ordinary,
      context: %{"actor_id" => agent.id, "origin_identifier" => "mcp-app:message:v1:test"}
    }
  end

  test "direct save and replay publish the documented envelopes", %{
    credential: credential,
    context: context
  } do
    attrs = %{
      context: context,
      title: nil,
      body: "Use Req.",
      tags: [],
      metadata: %{
        kind: "preference",
        epistemic_status: "user_stated",
        approval: "unspecified",
        source: %{channel: "agent", reference: nil},
        occurred_at: nil,
        effective_at: nil,
        derived_from_post_ids: []
      }
    }

    conn = request(credential, "/tama/memory/posts", attrs)
    assert_operation_response(conn, "memory_post_create")

    assert %{"data" => %{"id" => post_id, "receipt" => %{"replayed" => false}}} =
             json_response(conn, 201)

    conn =
      request(credential, "/tama/memory/posts", %{context: context, body: nil})

    assert %{"data" => %{"id" => ^post_id, "receipt" => %{"replayed" => true}}} =
             json_response(conn, 200)
  end

  test "ordinary context assertions are rejected before validation", %{ordinary: ordinary} do
    assert %{"error" => %{"code" => "forbidden_context"}} =
             request(ordinary, "/tama/memory/posts", %{context: nil}) |> json_response(403)
  end

  test "the OpenAPI exposes only the direct save operation", %{
    credential: credential,
    context: context
  } do
    assert request(credential, "/tama/memory/posts", %{
             context: Map.put(context, "actor_id", "bad")
           }).status == 422

    spec = build_conn() |> get("/tama/openapi") |> json_response(200)
    assert Map.has_key?(spec["paths"], "/tama/memory/posts")
    refute Map.has_key?(spec["paths"], "/tama/memory/ingestions")
    refute Map.has_key?(spec["paths"], "/tama/memory/ingestions/status")
  end

  defp request(credential, path, attrs) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header(
      "authorization",
      "Bearer #{credential.client_id}.#{credential.client_secret}"
    )
    |> post(path, attrs)
  end
end
