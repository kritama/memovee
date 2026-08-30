defmodule Memovee.OAuth.Tama.MCP do
  @moduledoc "The exact resource, scope, and client trust policy for Tama `/mcp/app`."

  alias Memovee.OAuth
  alias TamaOAuth.{Scope, URI}

  @scope "mcp.message"

  def resource, do: OAuth.resource()
  def supported_scopes, do: [@scope]
  def default_scopes, do: [@scope]

  def normalize_scope(nil), do: {:ok, @scope}
  def normalize_scope(scope), do: Scope.normalize(scope, supported_scopes())
  def parse_scope(scope), do: Scope.parse(scope, supported_scopes())

  def allowed_client_id?(client_id) when is_binary(client_id) do
    client_id in OAuth.config(:allowed_client_ids, []) or
      Enum.any?(OAuth.config(:allowed_client_id_prefixes, []), fn prefix ->
        URI.scoped_client_id?(client_id, prefix)
      end) or
      (OAuth.config(:allow_local_client_metadata, false) and
         TamaOAuth.ClientMetadata.valid_client_id_url?(client_id, allow_local?: true))
  end

  def allowed_client_id?(_client_id), do: false
end
