defmodule MemoveeWeb.ApiPrincipalController do
  use MemoveeWeb, :controller

  def show(conn, _params) do
    actor = conn.assigns.current_scope.actor

    json(conn, %{
      data: %{
        id: actor.id,
        type: actor.type,
        identifier: actor.identifier
      }
    })
  end
end
