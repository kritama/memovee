defmodule Memovee.OAuth.JWKSCacheTest do
  use ExUnit.Case, async: false

  alias Memovee.OAuth.{Cache, JWKSCache, KeyProvider}

  test "refreshes a cached JWKS once when the requested key ID is unknown" do
    cache_key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    {:ok, current_jwks} = KeyProvider.public_jwks()
    stale_jwks = rename_only_key(current_jwks, "retired-key")
    rotated_jwks = rename_only_key(current_jwks, "rotated-key")
    :ok = Cache.put(cache_key, stale_jwks, :timer.minutes(5))
    test_pid = self()

    fetcher = fn jwks_uri, origin ->
      send(test_pid, {:fetched, jwks_uri, origin})
      {:ok, rotated_jwks}
    end

    assert {:ok, %{"kid" => "rotated-key"}} =
             JWKSCache.select(
               cache_key,
               "https://client.example/jwks.json",
               "https://client.example/client.json",
               "rotated-key",
               "RS256",
               ttl_ms: :timer.minutes(5),
               fetcher: fetcher
             )

    assert_receive {:fetched, "https://client.example/jwks.json",
                    "https://client.example/client.json"}

    assert rotated_jwks == Cache.get(cache_key)

    rejecting_fetcher = fn _jwks_uri, _origin -> flunk("fresh JWKS should remain cached") end

    assert {:ok, %{"kid" => "rotated-key"}} =
             JWKSCache.select(
               cache_key,
               "https://client.example/jwks.json",
               "https://client.example/client.json",
               "rotated-key",
               "RS256",
               ttl_ms: :timer.minutes(5),
               fetcher: rejecting_fetcher
             )
  end

  defp rename_only_key(%{"keys" => [key]}, kid) do
    renamed = Map.put(key, "kid", kid)
    {:ok, jwks} = TamaOAuth.JWKS.validate(%{"keys" => [renamed]})
    jwks
  end
end
