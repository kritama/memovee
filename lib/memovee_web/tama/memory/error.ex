defmodule MemoveeWeb.Tama.Memory.Error do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def render(conn, reason) do
    {status, code} =
      case reason do
        :forbidden_context -> {403, "forbidden_context"}
        :forbidden -> {403, "forbidden"}
        :not_found -> {404, "not_found"}
        :ingestion_conflict -> {409, "ingestion_conflict"}
        :kind_tag_mismatch -> {422, "kind_tag_mismatch"}
        _ -> {422, "invalid_request"}
      end

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message(code), retryable: false, details: %{}}})
  end

  defp message("forbidden_context"), do: "Only the configured Tama service may assert context."
  defp message("forbidden"), do: "Memory access is forbidden."
  defp message("not_found"), do: "Memory resource not found."
  defp message("ingestion_conflict"), do: "This origin already has a different source submission."
  defp message("kind_tag_mismatch"), do: "The kind tag must match the memory kind."
  defp message(_), do: "Invalid memory request."
end
