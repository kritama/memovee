defmodule MemoveeWeb.Tama.Memory.IngestionControllerTest do
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

  test "open, save, status and replay publish the documented envelopes", %{
    credential: credential,
    context: context
  } do
    conn =
      request(credential, "/tama/memory/ingestions", %{context: context, content: "Use Req."})

    assert_operation_response(conn, "memory_ingestion_open")
    assert %{"data" => %{"ingestion_id" => id, "receipt" => nil}} = json_response(conn, 201)

    attrs = %{
      context: context,
      ingestion_id: id,
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
      request(credential, "/tama/memory/posts", %{context: context, ingestion_id: id, body: nil})

    assert %{"data" => %{"id" => ^post_id, "receipt" => %{"replayed" => true}}} =
             json_response(conn, 200)

    conn = request(credential, "/tama/memory/ingestions/status", %{context: context})
    assert_operation_response(conn, "memory_ingestion_status")
    assert %{"data" => %{"state" => "saved"}} = json_response(conn, 200)
  end

  test "ordinary context assertions are rejected before shape validation", %{ordinary: ordinary} do
    for path <- [
          "/tama/memory/posts",
          "/tama/memory/ingestions",
          "/tama/memory/ingestions/status"
        ] do
      assert %{"error" => %{"code" => "forbidden_context"}} =
               request(ordinary, path, %{context: nil}) |> json_response(403)
    end
  end

  test "status never creates and source conflicts do not leak raw content", %{
    credential: credential,
    context: context
  } do
    assert %{"error" => %{"code" => "not_found"}} =
             request(credential, "/tama/memory/ingestions/status", %{context: context})
             |> json_response(404)

    request(credential, "/tama/memory/ingestions", %{context: context, content: "private source"})

    conn =
      request(credential, "/tama/memory/ingestions", %{
        context: context,
        content: "changed-private-payload-913"
      })

    assert %{"error" => %{"code" => "ingestion_conflict"}} = json_response(conn, 409)
    assert_operation_response(conn, "memory_ingestion_open")
    refute conn.resp_body =~ "private source"
    refute conn.resp_body =~ "changed-private-payload-913"

    assert request(credential, "/tama/memory/ingestions/status", %{
             context: Map.put(context, "actor_id", "bad")
           }).status == 422
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
