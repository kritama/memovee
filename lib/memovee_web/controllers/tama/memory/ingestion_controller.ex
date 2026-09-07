defmodule MemoveeWeb.Tama.Memory.IngestionController do
  use MemoveeWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Memovee.Memory.{Ingestion, Scope}
  alias MemoveeWeb.Tama.Memory.Error

  alias MemoveeWeb.Tama.Memory.Schemas.{
    IngestionRequest,
    IngestionResponse,
    IngestionStatusRequest,
    MemoryErrorResponse,
    UnauthorizedResponse
  }

  tags ["memory"]

  operation :create,
    operation_id: "memory_ingestion_open",
    summary: "Open an immutable memory submission",
    request_body:
      {"Original source and trusted context", "application/json", IngestionRequest,
       required: true},
    responses: [
      created: {"Opened", "application/json", IngestionResponse},
      ok: {"Existing submission", "application/json", IngestionResponse},
      unauthorized: {"Invalid credential", "application/json", UnauthorizedResponse},
      forbidden: {"Forbidden memory scope", "application/json", MemoryErrorResponse},
      conflict: {"Source conflict", "application/json", MemoryErrorResponse},
      unprocessable_entity: {"Invalid request", "application/json", MemoryErrorResponse}
    ]

  operation :status,
    operation_id: "memory_ingestion_status",
    summary: "Read memory submission status",
    request_body: {"Trusted context", "application/json", IngestionStatusRequest, required: true},
    responses: [
      ok: {"Submission status", "application/json", IngestionResponse},
      unauthorized: {"Invalid credential", "application/json", UnauthorizedResponse},
      forbidden: {"Forbidden memory scope", "application/json", MemoryErrorResponse},
      not_found: {"No submission", "application/json", MemoryErrorResponse},
      unprocessable_entity: {"Invalid request", "application/json", MemoryErrorResponse}
    ]

  def create(conn, attrs) do
    with {:ok, scope} <- Scope.resolve(conn.assigns.current_scope.actor, attrs),
         true <- Enum.all?(Map.keys(attrs), &(&1 in ~w(context content))),
         {:ok, result} <- Ingestion.Manager.open(scope, attrs["content"]) do
      conn |> put_status(if(result.replayed, do: 200, else: 201)) |> json(%{data: result.data})
    else
      {:error, reason} -> Error.render(conn, reason)
      _ -> Error.render(conn, :invalid_request)
    end
  end

  def status(conn, attrs) do
    with {:ok, scope} <- Scope.resolve(conn.assigns.current_scope.actor, attrs),
         true <- Map.keys(attrs) == ["context"],
         {:ok, data} <- Ingestion.Manager.status(scope) do
      json(conn, %{data: data})
    else
      {:error, reason} -> Error.render(conn, reason)
      _ -> Error.render(conn, :invalid_request)
    end
  end
end
