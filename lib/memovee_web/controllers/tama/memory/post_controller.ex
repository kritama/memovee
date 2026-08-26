defmodule MemoveeWeb.Tama.Memory.PostController do
  use MemoveeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Memovee.Memory, as: MemoryContext
  alias Memovee.Memory.Post

  alias MemoveeWeb.Tama.Memory.Schemas.{
    CreatePostRequest,
    MemoryPostResponse,
    UnauthorizedResponse
  }

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback MemoveeWeb.FallbackController

  tags ["memory"]

  operation :create,
    summary: "Create a memory post",
    description: "Creates a canonical memory post and derives its body hash.",
    request_body:
      {"Memory post attributes", "application/json", CreatePostRequest, required: true},
    responses: [
      created: {"Created memory post", "application/json", MemoryPostResponse},
      unauthorized:
        {"Invalid or missing API credential", "application/json", UnauthorizedResponse},
      unprocessable_entity: OpenApiSpex.JsonErrorResponse.response()
    ]

  def create(conn, _params) do
    attrs = Map.from_struct(conn.body_params)

    with {:ok, %Post{} = post} <- MemoryContext.create_post(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, post: post)
    end
  end
end
