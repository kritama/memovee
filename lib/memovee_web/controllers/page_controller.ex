defmodule MemoveeWeb.PageController do
  use MemoveeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
