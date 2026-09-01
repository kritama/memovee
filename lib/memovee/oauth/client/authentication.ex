defmodule Memovee.OAuth.Client.Authentication do
  @moduledoc false

  alias Memovee.OAuth
  alias Memovee.OAuth.Client
  alias Memovee.OAuth.Client.ReplayStore
  alias TamaOAuth.ClientAuthentication

  def authenticate(method, context, endpoint, opts \\ []) do
    ClientAuthentication.authenticate(
      method,
      context,
      algorithms: OAuth.config(:token_endpoint_auth_signing_algorithms),
      token_endpoint: OAuth.endpoint(endpoint),
      now: DateTime.to_unix(OAuth.now()),
      max_assertion_bytes: OAuth.config(:client_assertion_max_bytes),
      max_lifetime_seconds: OAuth.config(:client_assertion_max_lifetime_seconds),
      clock_skew_seconds: OAuth.config(:client_assertion_clock_skew_seconds),
      key_resolver: Keyword.get(opts, :key_resolver, &Client.key/3),
      claim_replay: &ReplayStore.claim/2
    )
  end
end
