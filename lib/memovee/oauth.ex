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

  def validate_issuer!(issuer) when is_binary(issuer),
    do: validate_https_uri!(issuer, label: "OAuth issuer", path: :forbid, query: false)

  def validate_https_uri!(value, opts \\ []) when is_binary(value) do
    label = Keyword.get(opts, :label, "OAuth URL")
    path_policy = Keyword.get(opts, :path, :allow)
    query? = Keyword.get(opts, :query, true)

    with {:ok, uri} <- URI.new(value),
         true <- valid_https_uri?(uri, path_policy, query?) do
      :ok
    else
      _invalid ->
        raise ArgumentError,
              "#{label} must be an absolute HTTPS URI with valid routing components"
    end
  end

  def endpoint(path),
    do: URI.merge(issuer() <> "/", String.trim_leading(path, "/")) |> to_string()

  defp valid_https_uri?(uri, path_policy, query?) do
    uri.scheme == "https" and
      is_binary(uri.host) and
      uri.host != "" and
      is_nil(uri.userinfo) and
      is_nil(uri.fragment) and
      valid_path?(uri.path, path_policy) and
      (query? or is_nil(uri.query))
  end

  defp valid_path?(path, :allow), do: is_nil(path) or is_binary(path)
  defp valid_path?(nil, :forbid), do: true
  defp valid_path?(path, :required), do: is_binary(path) and path not in ["", "/"]
  defp valid_path?(path, expected) when is_binary(expected), do: path == expected
  defp valid_path?(_path, _policy), do: false
end
