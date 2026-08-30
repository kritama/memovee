defmodule Memovee.OAuth.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Memovee.OAuth.RateLimiter

  test "enforces authorization and registration limits per IP" do
    authorization_ip = unique_key(:authorization_ip)

    assert Enum.all?(1..30, fn _request ->
             RateLimiter.authorization(authorization_ip) == :ok
           end)

    assert {:error, {:rate_limited, _retry_after}} =
             RateLimiter.authorization(authorization_ip)

    registration_ip = unique_key(:registration_ip)

    assert Enum.all?(1..15, fn _request ->
             RateLimiter.registration(registration_ip) == :ok
           end)

    assert {:error, {:rate_limited, _retry_after}} =
             RateLimiter.registration(registration_ip)
  end

  test "enforces token, revocation, and introspection limits by IP and client" do
    assert_dual_limit(&RateLimiter.token/2, :token, 60)
    assert_dual_limit(&RateLimiter.revocation/2, :revocation, 30)
    assert_dual_limit(&RateLimiter.introspection/2, :introspection, 120)
  end

  test "a denied IP does not allocate or increment a client bucket" do
    denied_ip = unique_key(:denied_ip)
    target_client = unique_key(:target_client)

    assert Enum.all?(1..60, fn request ->
             RateLimiter.token(denied_ip, unique_key({:client, request})) == :ok
           end)

    assert {:error, {:rate_limited, _retry_after}} =
             RateLimiter.token(denied_ip, target_client)

    assert Enum.all?(1..60, fn request ->
             RateLimiter.token(unique_key({:ip, request}), target_client) == :ok
           end)
  end

  defp unique_key(label), do: {label, System.unique_integer([:positive, :monotonic])}

  defp assert_dual_limit(rate_limiter, label, limit) do
    remote_ip = unique_key({label, :ip})
    client_id = unique_key({label, :client})

    assert Enum.all?(1..limit, fn _request -> rate_limiter.(remote_ip, client_id) == :ok end)

    assert {:error, {:rate_limited, _retry_after}} = rate_limiter.(remote_ip, client_id)
  end
end
