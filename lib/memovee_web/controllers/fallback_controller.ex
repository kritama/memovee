defmodule MemoveeWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """

  use MemoveeWeb, :controller

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
