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

  def endpoint(path),
    do: URI.merge(issuer() <> "/", String.trim_leading(path, "/")) |> to_string()
end
