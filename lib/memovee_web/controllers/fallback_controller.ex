defmodule MemoveeWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """

  use MemoveeWeb, :controller

  def call(conn, {:error, {:memory, reason}}) do
    {status, code, message} =
      case reason do
        :forbidden_context ->
          {:forbidden, "forbidden_context",
           "Only the configured Tama service may assert context."}

        :forbidden ->
          {:forbidden, "forbidden", "Memory access is forbidden."}

        :not_found ->
          {:not_found, "not_found", "Memory resource not found."}

        :kind_tag_mismatch ->
          {:unprocessable_entity, "kind_tag_mismatch", "The kind tag must match the memory kind."}

        _ ->
          {:unprocessable_entity, "invalid_request", "Invalid memory request."}
      end

    conn
    |> put_status(status)
    |> put_view(json: MemoveeWeb.ErrorJSON)
    |> render(:memory, code: code, message: message)
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MemoveeWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, nil) do
    conn
    |> put_status(:not_found)
    |> put_view(html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON)
    |> render(:"401")
  end

  def call(conn, {:error, %Eventful.Error{}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON)
    |> render(:"422")
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:bad_request)
    |> put_view(html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON)
    |> render(:"400")
  end

  def call(conn, _unexpected) do
    conn
    |> put_status(:bad_request)
    |> put_view(html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON)
    |> render(:"400")
  end
end
