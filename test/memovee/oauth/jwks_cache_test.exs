defmodule Memovee.OAuth.JWKSCacheTest do
  use ExUnit.Case, async: false

  alias Memovee.Cache
  alias Memovee.OAuth.{JWKSCache, KeyProvider}

  test "refreshes a cached JWKS once when the requested key ID is unknown" do
    cache_key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    {:ok, current_jwks} = KeyProvider.public_jwks()
    stale_jwks = rename_only_key(current_jwks, "retired-key")
    rotated_jwks = rename_only_key(current_jwks, "rotated-key")
    :ok = Cache.put!(cache_key, stale_jwks, ttl: :timer.minutes(5))
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

    assert rotated_jwks == Cache.get!(cache_key)

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
    :ok = Cache.put!(cache_key, stale_jwks, ttl: :timer.minutes(5))
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

  test "does not serialize refreshes for unrelated JWKS cache keys" do
    first_cache_key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    second_cache_key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    {:ok, current_jwks} = KeyProvider.public_jwks()
    stale_jwks = rename_only_key(current_jwks, "retired-key")
    rotated_jwks = rename_only_key(current_jwks, "rotated-key")
    :ok = Cache.put!(first_cache_key, stale_jwks, ttl: :timer.minutes(5))
    :ok = Cache.put!(second_cache_key, stale_jwks, ttl: :timer.minutes(5))
    test_pid = self()

    blocking_fetcher = fn _jwks_uri, _origin ->
      send(test_pid, {:blocking_fetch_started, self()})

      receive do
        :release_fetch -> :ok
      end

      {:ok, rotated_jwks}
    end

    first =
      Task.async(fn ->
        select_key(first_cache_key, blocking_fetcher)
      end)

    assert_receive {:blocking_fetch_started, first_fetcher}

    second =
      Task.async(fn ->
        select_key(second_cache_key, fn _jwks_uri, _origin -> {:ok, rotated_jwks} end)
      end)

    second_while_first_locked = Task.yield(second, 1_000)
    send(first_fetcher, :release_fetch)

    assert {:ok, %{"kid" => "rotated-key"}} = Task.await(first)

    second_result = second_while_first_locked || {:ok, Task.await(second)}
    assert {:ok, {:ok, %{"kid" => "rotated-key"}}} = second_result
    refute is_nil(second_while_first_locked)
  end

  test "throttles repeated unknown key IDs after a fresh JWKS still misses" do
    cache_key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    {:ok, current_jwks} = KeyProvider.public_jwks()
    stale_jwks = rename_only_key(current_jwks, "retired-key")
    refreshed_jwks = rename_only_key(current_jwks, "current-key")
    :ok = Cache.put!(cache_key, stale_jwks, ttl: :timer.minutes(5))
    counter = start_supervised!({Agent, fn -> 0 end})

    fetcher = fn _jwks_uri, _origin ->
      Agent.update(counter, &(&1 + 1))
      {:ok, refreshed_jwks}
    end

    options = [
      ttl_ms: :timer.minutes(5),
      refresh_cooldown_ms: :timer.seconds(30),
      fetcher: fetcher
    ]

    assert {:error, :unknown_kid} =
             JWKSCache.select(
               cache_key,
               "https://client.example/jwks.json",
               "https://client.example/client.json",
               "missing-key-one",
               "RS256",
               options
             )

    assert {:error, :unknown_kid} =
             JWKSCache.select(
               cache_key,
               "https://client.example/jwks.json",
               "https://client.example/client.json",
               "missing-key-two",
               "RS256",
               options
             )

    assert Agent.get(counter, & &1) == 1
  end

  defp rename_only_key(%{"keys" => [key]}, kid) do
    renamed = Map.put(key, "kid", kid)
    {:ok, jwks} = TamaOAuth.JWKS.validate(%{"keys" => [renamed]})
    jwks
  end

  defp select_key(cache_key, fetcher) do
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
end
