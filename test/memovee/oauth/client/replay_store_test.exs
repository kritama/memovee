defmodule Memovee.OAuth.Client.ReplayStoreTest do
  use Memovee.DataCase, async: false

  import Memovee.OAuthFixtures

  alias Memovee.OAuth
  alias Memovee.OAuth.Client.ReplayStore

  test "claims each client assertion digest exactly once" do
    digest = TamaOAuth.Crypto.digest("unique-client-assertion")
    expires_at = DateTime.add(DateTime.utc_now(:microsecond), 5, :minute)

    assert :ok = ReplayStore.claim(digest, expires_at)
    assert {:error, :replayed} = ReplayStore.claim(digest, expires_at)
  end

  test "claims the bounded digest and expiry from a Tama introspection assertion" do
    {params, []} = introspection_request("unknown-token")
    {:ok, claims} = Joken.peek_claims(params["client_assertion"])

    digest =
      TamaOAuth.Crypto.digest(OAuth.config(:introspection_client_id) <> <<0>> <> claims["jti"])

    {:ok, expires_at} =
      DateTime.from_unix(claims["exp"] + OAuth.config(:client_assertion_clock_skew_seconds))

    assert :ok = ReplayStore.claim(digest, expires_at)
  end
end
