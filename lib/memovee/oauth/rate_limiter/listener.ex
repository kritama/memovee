defmodule Memovee.OAuth.RateLimiter.Listener do
  @moduledoc false

  use GenServer

  alias Memovee.OAuth.RateLimiter.Local

  def start_link(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    topic = Keyword.fetch!(opts, :topic)
    GenServer.start_link(__MODULE__, {pubsub, topic}, name: __MODULE__)
  end

  @impl true
  def init({pubsub, topic}) do
    :ok = Phoenix.PubSub.subscribe(pubsub, topic)
    {:ok, nil}
  end

  @impl true
  def handle_info({:inc, key, window_ms, increment}, state) do
    _count = Local.inc(key, window_ms, increment)
    {:noreply, state}
  end
end
