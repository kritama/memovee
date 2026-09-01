defmodule MemoveeWeb.Auth.MetadataController do
  @moduledoc false

  use MemoveeWeb, :controller

  alias Memovee.OAuth
  alias Memovee.OAuth.Tama.MCP
  alias TamaOAuth.Metadata.AuthorizationServer

  action_fallback MemoveeWeb.Auth.FallbackController

  def authorization_server(conn, _params) do
    if MCP.configured?() do
      with {:ok, metadata} <-
             AuthorizationServer.build(
               issuer: OAuth.issuer(),
               authorization_endpoint: OAuth.endpoint("/auth/authorizations/new"),
               token_endpoint: OAuth.endpoint("/auth/tokens"),
               jwks_uri: OAuth.endpoint("/.well-known/jwks.json"),
               registration_endpoint: OAuth.endpoint("/auth/registrations"),
               revocation_endpoint: OAuth.endpoint("/auth/revocations"),
               introspection_endpoint: OAuth.endpoint("/auth/introspections"),
               protected_resources: if(MCP.enabled?(), do: [OAuth.resource()]),
               scopes_supported: MCP.supported_scopes(),
               token_endpoint_auth_methods_supported: OAuth.config(:token_endpoint_auth_methods),
               token_endpoint_auth_signing_alg_values_supported:
                 OAuth.config(:token_endpoint_auth_signing_algorithms)
             ) do
        conn
        |> put_no_store()
        |> json(metadata)
      end
    else
      conn
      |> put_no_store()
      |> send_resp(:not_found, "")
    end
  end

  defp put_no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end
end
