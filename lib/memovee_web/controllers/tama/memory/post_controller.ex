defmodule MemoveeWeb.Tama.Memory.PostController do
  use MemoveeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Ecto.Changeset
  alias Memovee.Memory, as: MemoryContext

  alias MemoveeWeb.Tama.Memory.Schemas.{
    CreatePostRequest,
    MemoryPostResponse,
    UnauthorizedResponse
  }

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

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

    case MemoryContext.create_post(attrs) do
      {:ok, post} ->
        conn
        |> put_status(:created)
        |> json(%{data: post_json(post)})

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Enum.map(changeset.errors, &changeset_error/1)})
    end
  end

  defp post_json(post) do
    %{
      id: post.id,
      title: post.title,
      body: post.body,
      body_hash: post.body_hash,
      metadata: post.metadata,
      inserted_at: post.inserted_at,
      updated_at: post.updated_at
    }
  end

  defp changeset_error({field, {message, options}}) do
    detail =
      Enum.reduce(options, message, fn {key, value}, translated ->
        String.replace(translated, "%{#{key}}", to_string(value))
      end)

    %{
      title: "Invalid value",
      source: %{pointer: "/#{field}"},
      detail: detail
    }
  end
end
