defmodule MemoveeWeb.Tama.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Tama API.
  """

  alias MemoveeWeb.{Endpoint, Router}
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server, Tag}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Memovee Tama API",
        version: to_string(Application.spec(:memovee, :vsn))
      },
      servers: [Server.from_endpoint(Endpoint)],
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "<client-id>.<client-secret>"
          }
        }
      },
      security: [%{"bearer_auth" => []}],
      tags: [
        %Tag{name: "memory", description: "Canonical memory resources"}
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
