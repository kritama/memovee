defmodule Memovee.OAuth do
  @moduledoc """
  Memovee's OAuth authorization-server facade and runtime configuration.

  Protocol mechanics are delegated to `TamaOAuth`; Memovee owns identities,
  persistence, authorization policy, transactions, and HTTP adapters.
  """

  alias Memovee.OAuth.{Authorization, Introspection, Revocation}
  alias Memovee.OAuth.Token.Exchange

  defdelegate start_authorization(params, remote_ip \\ nil), to: Authorization, as: :start
  defdelegate consent(scope, handle), to: Authorization
  defdelegate approve(scope, handle), to: Authorization
  defdelegate deny(scope, handle), to: Authorization

  def exchange(params, authorization_headers \\ [], remote_ip \\ nil),
    do: Exchange.exchange(params, authorization_headers, remote_ip)

  def revoke(params, authorization_headers \\ [], remote_ip \\ nil),
    do: Revocation.revoke(params, authorization_headers, remote_ip)

  def introspect(params, credentials, remote_ip \\ nil),
    do: Introspection.introspect(params, credentials, remote_ip)

  def config(key), do: Keyword.fetch!(config(), key)
  def config(key, default), do: Keyword.get(config(), key, default)
  def config, do: Application.fetch_env!(:memovee, __MODULE__)

  def issuer, do: config(:issuer)
  def resource, do: config(:resource)
  def now, do: DateTime.utc_now(:microsecond)

  def validate_issuer!(issuer, opts \\ []) when is_binary(issuer) do
    required_scheme = Keyword.get(opts, :scheme)

    with {:ok, uri} <- URI.new(issuer),
         true <- valid_issuer_origin?(uri, required_scheme) do
      :ok
    else
      _invalid ->
        raise ArgumentError,
              "OAuth issuer must be an absolute origin without a path, query, fragment, or user info"
    end
  end

  def endpoint(path),
    do: URI.merge(issuer() <> "/", String.trim_leading(path, "/")) |> to_string()

  defp valid_issuer_origin?(uri, required_scheme) do
    is_binary(uri.scheme) and
      is_binary(uri.host) and
      uri.host != "" and
      is_nil(uri.userinfo) and
      is_nil(uri.path) and
      is_nil(uri.query) and
      is_nil(uri.fragment) and
      (is_nil(required_scheme) or uri.scheme == required_scheme)
  end
end
