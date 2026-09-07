defmodule MemoveeWeb.Tama.Memory.PostController do
  use MemoveeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Memovee.Memory.{Post, Scope}

  alias MemoveeWeb.Schemas.Tama.Memory.{
    CreatePostRequest,
    MemoryErrorResponse,
    MemoryPostResponse,
    UnauthorizedResponse
  }

  action_fallback MemoveeWeb.FallbackController

  tags ["memory"]

  operation :create,
    operation_id: "memory_post_create",
    summary: "Create a memory post",
    description: "Creates a canonical memory post from the trusted Tama remember flow.",
    request_body:
      {"Memory post attributes", "application/json", CreatePostRequest, required: true},
    responses: [
      created: {"Created memory post", "application/json", MemoryPostResponse},
      ok: {"Replayed memory post", "application/json", MemoryPostResponse},
      unauthorized:
        {"Invalid or missing API credential", "application/json", UnauthorizedResponse},
      forbidden: {"Forbidden memory scope", "application/json", MemoryErrorResponse},
      unprocessable_entity: {"Invalid memory request", "application/json", MemoryErrorResponse}
    ]

  def create(conn, attrs) do
    with {:ok, scope} <- Scope.resolve_service(conn.assigns.current_scope.actor, attrs),
         true <-
           Enum.all?(Map.keys(attrs), &(&1 in ~w(context post))),
         post_attrs when is_map(post_attrs) <- Map.get(attrs, "post"),
         true <- Enum.all?(Map.keys(post_attrs), &(&1 in ~w(title body metadata tags))),
         {:ok, result} <- Post.Manager.create(scope, post_attrs) do
      conn
      |> put_status(if(result.replayed, do: 200, else: 201))
      |> render(:show, post: result.post, receipt: result.receipt)
    else
      {:error, reason} -> {:error, {:memory, reason}}
      _ -> {:error, {:memory, :invalid_request}}
    end
  end
end
