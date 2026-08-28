defmodule Memovee.OAuth.RateLimiter do
  @moduledoc "Distributed OAuth boundary rate limits backed by Hammer and Phoenix PubSub."

  alias __MODULE__.{Listener, Local}

  @default_limits %{
    authorization: {30, 60_000},
    registration: {15, 60_000},
    token: {60, 60_000},
    revocation: {30, 60_000},
    introspection: {120, 60_000}
  }

  @pubsub Memovee.PubSub
  @topic "oauth:rate_limiter"

  def authorization(remote_ip), do: hit(:authorization, :ip, remote_ip)
  def registration(remote_ip), do: hit(:registration, :ip, remote_ip)

  def token(remote_ip, client_id) do
    with :ok <- hit(:token, :ip, remote_ip) do
      hit(:token, :client, client_id)
    end
  end

  def revocation(remote_ip, client_id) do
    with :ok <- hit(:revocation, :ip, remote_ip) do
      hit(:revocation, :client, client_id)
    end
  end

  def introspection(remote_ip, client_id) do
    with :ok <- hit(:introspection, :ip, remote_ip) do
      hit(:introspection, :client, client_id)
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts) do
    children = [
      {Local, opts},
      {Listener, pubsub: @pubsub, topic: @topic}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp hit(bucket, dimension, identifier) do
    {limit, window_ms} = Map.fetch!(@default_limits, bucket)
    key = :erlang.term_to_binary({__MODULE__, bucket, dimension, identifier_digest(identifier)})

    :ok = broadcast({:inc, key, window_ms, 1})

    case Local.hit(key, window_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after} -> {:error, {:rate_limited, retry_after}}
    end
  end

  defp identifier_digest(identifier),
    do: identifier |> :erlang.term_to_binary() |> TamaOAuth.Crypto.digest()

  defp broadcast(message) do
    case Process.whereis(Listener) do
      nil -> Phoenix.PubSub.broadcast(@pubsub, @topic, message)
      listener -> Phoenix.PubSub.broadcast_from(@pubsub, listener, @topic, message)
    end
  end
end
