defmodule Memovee.CacheTest do
  use ExUnit.Case, async: false

  alias Memovee.Cache

  test "stores, expires, and deletes local entries through Nebulex" do
    key = {__MODULE__, System.unique_integer([:positive, :monotonic])}

    assert :ok = Cache.put!(key, :cached, ttl: :timer.minutes(1))
    assert :cached = Cache.get!(key)
    assert {:ok, ttl} = Cache.ttl(key)
    assert ttl in 1..:timer.minutes(1)
    assert :ok = Cache.delete!(key)
    assert is_nil(Cache.get!(key))
  end
end
