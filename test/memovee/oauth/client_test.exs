defmodule Memovee.OAuth.ClientTest do
  use ExUnit.Case, async: false

  alias Memovee.OAuth.Client
  alias TamaOAuth.ClientMetadata

  test "coalesces concurrent metadata cache misses for one client" do
    client_id = unique_client_id()
    metadata = metadata(client_id)
    test_pid = self()
    counter = start_supervised!({Agent, fn -> 0 end})

    loader = fn _client_id ->
      attempt = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
      send(test_pid, {:metadata_fetch, attempt, self()})

      if attempt == 1 do
        receive do
          :release_fetch -> :ok
        end
      end

      {:ok, metadata}
    end

    load = fn -> Client.fetch(client_id, metadata_loader: loader) end
    first = Task.async(load)
    assert_receive {:metadata_fetch, 1, first_loader}
    second = Task.async(load)

    parallel_fetch? =
      receive do
        {:metadata_fetch, 2, _second_loader} -> true
      after
        100 -> false
      end

    send(first_loader, :release_fetch)

    assert {:ok, ^metadata} = Task.await(first)
    assert {:ok, ^metadata} = Task.await(second)
    refute parallel_fetch?
    assert Agent.get(counter, & &1) == 1
  end

  test "retains a short failure cooldown for cold metadata" do
    client_id = unique_client_id()
    counter = start_supervised!({Agent, fn -> 0 end})

    loader = fn _client_id ->
      Agent.update(counter, &(&1 + 1))
      {:error, :temporarily_unavailable}
    end

    opts = [metadata_loader: loader, failure_cooldown_ms: :timer.seconds(30)]

    assert {:error, :temporarily_unavailable} = Client.fetch(client_id, opts)
    assert {:error, :temporarily_unavailable} = Client.fetch(client_id, opts)
    assert Agent.get(counter, & &1) == 1
  end

  test "explicit refresh still revalidates unchanged metadata" do
    client_id = unique_client_id()
    metadata = metadata(client_id)
    counter = start_supervised!({Agent, fn -> 0 end})

    loader = fn _client_id ->
      Agent.update(counter, &(&1 + 1))
      {:ok, metadata}
    end

    opts = [metadata_loader: loader]

    assert {:ok, ^metadata} = Client.fetch(client_id, opts)
    assert {:ok, ^metadata} = Client.fetch(client_id, opts)
    assert {:ok, ^metadata} = Client.refresh(client_id, opts)
    assert {:ok, ^metadata} = Client.refresh(client_id, opts)
    assert Agent.get(counter, & &1) == 3
  end

  defp unique_client_id do
    suffix = System.unique_integer([:positive, :monotonic])
    "http://127.0.0.1/client-#{suffix}.json"
  end

  defp metadata(client_id) do
    %ClientMetadata{
      client_id: client_id,
      client_name: "Concurrent client",
      redirect_uris: ["http://127.0.0.1/callback"],
      grant_types: ["authorization_code"],
      response_types: ["code"],
      token_endpoint_auth_methods_supported: ["none"],
      token_endpoint_auth_signing_algorithms: [],
      cache_ttl: 3_600
    }
  end
end
