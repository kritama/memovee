defmodule Memovee.OAuth.CacheTest do
  use ExUnit.Case, async: false

  alias Memovee.OAuth.Cache

  test "prunes expired entries without requiring another lookup of their keys" do
    key = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    now = System.monotonic_time(:millisecond)

    assert :ok = Cache.put(key, :cached, :timer.minutes(1))
    assert :cached = Cache.get(key)
    assert Cache.prune_expired(now + :timer.minutes(1)) >= 1
    assert is_nil(Cache.get(key))
  end
end
