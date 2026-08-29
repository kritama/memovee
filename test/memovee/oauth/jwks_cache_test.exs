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

  test "coalesces concurrent refreshes for the same stale JWKS" do
    cache_key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    {:ok, current_jwks} = KeyProvider.public_jwks()
    stale_jwks = rename_only_key(current_jwks, "retired-key")
    rotated_jwks = rename_only_key(current_jwks, "rotated-key")
    :ok = Cache.put(cache_key, stale_jwks, :timer.minutes(5))
    test_pid = self()
    counter = start_supervised!({Agent, fn -> 0 end})

    fetcher = fn _jwks_uri, _origin ->
      attempt = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
      send(test_pid, {:fetch_attempt, attempt, self()})

      if attempt == 1 do
        receive do
          :release_fetch -> :ok
        end
      end

      {:ok, rotated_jwks}
    end

    select = fn ->
      JWKSCache.select(
        cache_key,
        "https://client.example/jwks.json",
        "https://client.example/client.json",
        "rotated-key",
        "RS256",
        ttl_ms: :timer.minutes(5),
        fetcher: fetcher
      )
    end

    first = Task.async(select)
    assert_receive {:fetch_attempt, 1, first_fetcher}
    second = Task.async(select)

    parallel_fetch? =
      receive do
        {:fetch_attempt, 2, _second_fetcher} -> true
      after
        100 -> false
      end

    send(first_fetcher, :release_fetch)

    assert {:ok, %{"kid" => "rotated-key"}} = Task.await(first)
    assert {:ok, %{"kid" => "rotated-key"}} = Task.await(second)
    refute parallel_fetch?
    assert Agent.get(counter, & &1) == 1
  end

  defp rename_only_key(%{"keys" => [key]}, kid) do
    renamed = Map.put(key, "kid", kid)
    {:ok, jwks} = TamaOAuth.JWKS.validate(%{"keys" => [renamed]})
    jwks
  end
end
