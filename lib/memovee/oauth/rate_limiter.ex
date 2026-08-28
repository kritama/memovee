defmodule Memovee.OAuth.RateLimiter do
  @moduledoc "Small application-owned fixed-window limiter for OAuth boundaries."

  use GenServer

  @default_limits %{
    authorization: {30, 60_000},
    registration: {15, 60_000},
    token: {60, 60_000},
    revocation: {30, 60_000},
    introspection: {120, 60_000}
  }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def check(bucket, key) do
    GenServer.call(__MODULE__, {:check, bucket, :erlang.phash2(key)})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:check, bucket, key}, _from, state) do
    {limit, window_ms} = Map.fetch!(@default_limits, bucket)
    now = System.monotonic_time(:millisecond)

    case Map.get(state, {bucket, key}) do
      {count, started_at} when now - started_at < window_ms and count >= limit ->
        retry_after = max(div(window_ms - (now - started_at), 1_000), 1)
        {:reply, {:error, retry_after}, state}

      {count, started_at} when now - started_at < window_ms ->
        {:reply, :ok, Map.put(state, {bucket, key}, {count + 1, started_at})}

      _ ->
        state = prune(state, now, window_ms)
        {:reply, :ok, Map.put(state, {bucket, key}, {1, now})}
    end
  end

  defp prune(state, now, max_window) do
    Map.reject(state, fn {_key, {_count, started_at}} -> now - started_at >= max_window end)
  end
end
