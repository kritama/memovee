defmodule Memovee.OAuth.Cache do
  @moduledoc false

  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def get(key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now -> value
      [{^key, _value, _expires_at}] -> delete(key)
      [] -> nil
    end
  end

  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    GenServer.call(__MODULE__, {:put, key, value, expires_at})
  end

  def delete(key), do: GenServer.call(__MODULE__, {:delete, key})

  @impl true
  def init(:ok) do
    _table = :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, %{}}
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
end
