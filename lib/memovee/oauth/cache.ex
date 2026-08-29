defmodule Memovee.OAuth.Cache do
  @moduledoc false

  use GenServer

  @table __MODULE__
  @sweep_interval_ms :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now -> value
      [{^key, value, expires_at}] -> delete_expired(key, value, expires_at)
      [] -> nil
    end
  end

  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    GenServer.call(__MODULE__, {:put, key, value, expires_at})
  end

  def delete(key), do: GenServer.call(__MODULE__, {:delete, key})

  defp delete_expired(key, value, expires_at) do
    GenServer.call(__MODULE__, {:delete_expired, key, value, expires_at})
  end

  def prune_expired(now \\ System.monotonic_time(:millisecond)) when is_integer(now) do
    GenServer.call(__MODULE__, {:prune_expired, now})
  end

  @impl true
  def init(opts) do
    _table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @sweep_interval_ms)
    {:ok, schedule_sweep(%{sweep_interval_ms: sweep_interval_ms})}
  end

  @impl true
  def handle_call({:put, key, value, expires_at}, _from, state) do
    true = :ets.insert(@table, {key, value, expires_at})
    {:reply, :ok, state}
  end

  def handle_call({:delete, key}, _from, state) do
    true = :ets.delete(@table, key)
    {:reply, nil, state}
  end

  def handle_call({:delete_expired, key, value, expires_at}, _from, state) do
    true = :ets.delete_object(@table, {key, value, expires_at})
    {:reply, current_value(key), state}
  end

  def handle_call({:prune_expired, now}, _from, state) do
    {:reply, delete_expired(now), state}
  end

  @impl true
  def handle_info(:sweep_expired, state) do
    _deleted_count = delete_expired(System.monotonic_time(:millisecond))
    {:noreply, schedule_sweep(state)}
  end

  defp schedule_sweep(state) do
    _timer = Process.send_after(self(), :sweep_expired, state.sweep_interval_ms)
    state
  end

  defp delete_expired(now) do
    :ets.select_delete(@table, [
      {{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", now}], [true]}
    ])
  end

  defp current_value(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, _expires_at}] -> value
      [] -> nil
    end
  end
end
