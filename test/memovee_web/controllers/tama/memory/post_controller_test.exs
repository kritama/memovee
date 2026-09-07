defmodule MemoveeWeb.Tama.Memory.PostControllerTest do
  use MemoveeWeb.ConnCase, async: false

  import Memovee.AccountsFixtures
  import OpenApiSpex.TestAssertions

  alias Memovee.Memory.Post
  alias Memovee.Repo
  alias MemoveeWeb.Schemas.Tama.ApiSpec

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    service = agent_fixture(owner)
    credential = api_token_fixture(owner, service)
    previous = Application.get_env(:memovee, :memory_tama_actor_id)
    Application.put_env(:memovee, :memory_tama_actor_id, service.id)
    on_exit(fn -> Application.put_env(:memovee, :memory_tama_actor_id, previous) end)
    context = %{"actor_id" => agent.id, "origin_identifier" => "mcp-app:message:v1:test"}

    %{credential: credential, context: context}
  end

  test "creates a canonical memory post", %{conn: conn, credential: credential, context: context} do
    attrs =
      File.read!("tama/graph/schemas/memory-fixtures.v1.json")
      |> Jason.decode!()
      |> get_in(["extraction", Access.at(0), "expected", "post"])

    assert_request_schema(
      %{"context" => context, "post" => attrs},
      "CreateMemoryPostRequest",
      ApiSpec.spec()
    )

    conn =
      conn
      |> authorize(credential)
      |> post(~p"/tama/memory/posts", %{"context" => context, "post" => attrs})

    assert_operation_response(conn, "memory_post_create")

    assert %{
             "data" => %{
               "id" => id,
               "title" => "Memovee HTTP preference",
               "body" => body,
               "body_hash" => body_hash,
               "metadata" => metadata,
               "inserted_at" => inserted_at,
               "updated_at" => updated_at
             }
           } = json_response(conn, 201)

    assert metadata == attrs["metadata"]
    assert body == attrs["body"]
    assert body_hash == sha256(body)
    assert is_binary(inserted_at)
    assert is_binary(updated_at)

    post = Repo.get!(Post, id)
    assert post.title == attrs["title"]
    assert post.body == body
    assert post.body_hash == body_hash
    assert post.metadata == attrs["metadata"]
  end

  test "rejects missing structured metadata", %{
    conn: conn,
    credential: credential,
    context: context
  } do
    conn =
      conn
      |> authorize(credential)
      |> post(~p"/tama/memory/posts", %{
        "context" => context,
        "post" => %{"body" => "A memory without metadata."}
      })

    assert %{"error" => %{"code" => "invalid_request"}} = json_response(conn, 422)
  end

  test "rejects invalid and server-owned attributes", %{credential: credential, context: context} do
    invalid_requests = [
      %{},
      %{"body" => " \n\t "},
      %{"body" => "Valid body", "body_hash" => String.duplicate("0", 64)}
    ]

    for request <- invalid_requests do
      conn =
        build_conn()
        |> authorize(credential)
        |> post(~p"/tama/memory/posts", %{"context" => context, "post" => request})

      assert %{"error" => %{"code" => "invalid_request"}} = json_response(conn, 422)
      assert_operation_response(conn, "memory_post_create")
    end

    assert Repo.aggregate(Post, :count) == 0
  end

  test "requires a post object and rejects misplaced or unexpected fields", %{
    credential: credential,
    context: context
  } do
    for attrs <- [
          %{},
          %{"post" => nil},
          %{"post" => []},
          %{"body" => "unnested"},
          %{"post" => %{"body" => "valid"}, "title" => "misplaced"},
          %{"post" => %{"body" => "valid", "context" => %{}}}
        ] do
      conn =
        build_conn()
        |> authorize(credential)
        |> post(~p"/tama/memory/posts", Map.put(attrs, "context", context))

      assert %{"error" => %{"code" => "invalid_request"}} = json_response(conn, 422)
    end

    assert Repo.aggregate(Post, :count) == 0
  end

  test "requires an active API credential", %{conn: conn} do
    conn = post(conn, ~p"/tama/memory/posts", %{"body" => "Unauthorized memory"})

    assert json_response(conn, 401) == %{"error" => "unauthorized"}
    assert Repo.aggregate(Post, :count) == 0
  end

  test "serves the OpenAPI document", %{conn: conn} do
    spec =
      conn
      |> get(~p"/tama/openapi")
      |> json_response(200)

    assert %{"post" => operation} = spec["paths"]["/tama/memory/posts"]
    assert operation["operationId"] == "memory_post_create"
    assert operation["security"] == nil
    assert Map.has_key?(operation["responses"], "201")
    assert spec["security"] == [%{"bearer_auth" => []}]

    assert spec["components"]["securitySchemes"]["bearer_auth"] == %{
             "type" => "http",
             "scheme" => "bearer",
             "bearerFormat" => "<client-id>.<client-secret>"
           }
  end

  defp authorize(conn, credential) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header(
      "authorization",
      "Bearer #{credential.client_id}.#{credential.client_secret}"
    )
  end

  defp sha256(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end
end
