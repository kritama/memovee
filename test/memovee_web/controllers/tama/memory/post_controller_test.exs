defmodule MemoveeWeb.Tama.Memory.PostControllerTest do
  use MemoveeWeb.ConnCase, async: true

  import Memovee.AccountsFixtures
  import OpenApiSpex.TestAssertions

  alias Memovee.Memory.Post
  alias Memovee.Repo

  setup do
    owner = user_fixture().actor
    agent = agent_fixture(owner)
    credential = api_token_fixture(owner, agent)

    %{credential: credential}
  end

  test "creates a canonical memory post", %{conn: conn, credential: credential} do
    attrs = %{
      "title" => "Launch notes",
      "body" => "The launch is scheduled for Friday.",
      "metadata" => %{"source" => "agent"}
    }

    conn =
      conn
      |> authorize(credential)
      |> post(~p"/tama/memory/posts", attrs)

    assert_operation_response(conn)

    assert %{
             "data" => %{
               "id" => id,
               "title" => "Launch notes",
               "body" => body,
               "body_hash" => body_hash,
               "metadata" => %{"source" => "agent"},
               "inserted_at" => inserted_at,
               "updated_at" => updated_at
             }
           } = json_response(conn, 201)

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

  test "defaults metadata when it is omitted", %{conn: conn, credential: credential} do
    conn =
      conn
      |> authorize(credential)
      |> post(~p"/tama/memory/posts", %{"body" => "A memory without metadata."})

    assert %{"data" => %{"metadata" => %{}}} = json_response(conn, 201)
  end

  test "rejects invalid and server-owned attributes", %{credential: credential} do
    invalid_requests = [
      %{},
      %{"body" => " \n\t "},
      %{"body" => "Valid body", "body_hash" => String.duplicate("0", 64)}
    ]

    for request <- invalid_requests do
      conn =
        build_conn()
        |> authorize(credential)
        |> post(~p"/tama/memory/posts", request)

      assert %{"errors" => [_error | _]} = json_response(conn, 422)
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
    assert operation["operationId"] == "MemoveeWeb.Tama.Memory.PostController.create"
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
