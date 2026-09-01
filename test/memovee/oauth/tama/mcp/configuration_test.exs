defmodule Memovee.OAuth.Tama.MCP.ConfigurationTest do
  use ExUnit.Case, async: true

  alias Memovee.OAuth.Tama.MCP
  alias Memovee.OAuth.Tama.MCP.Configuration

  @contract_path "priv/contracts/tama-mcp-app-bootstrap-v1.json"

  setup_all do
    {:ok, key} =
      TamaOAuth.SigningKey.generate({:rsa, 2_048},
        algorithm: "RS256",
        algorithms: ["RS256"],
        kid: "memovee-contract-test-rs256-1"
      )

    {:ok, private_key: Jason.encode!(key)}
  end

  test "disabled mode reads no state-dependent values" do
    parent = self()

    get_env = fn name ->
      send(parent, {:read, name})
      if name == "MEMOVEE_TAMA_MCP_APP_MODE", do: "disabled"
    end

    assert [mode: :disabled] = Configuration.load!(:prod, get_env)
    assert_received {:read, "MEMOVEE_TAMA_MCP_APP_MODE"}
    refute_received {:read, _other}
  end

  test "unknown modes fail before reading integration values" do
    parent = self()

    get_env = fn name ->
      send(parent, {:read, name})
      if name == "MEMOVEE_TAMA_MCP_APP_MODE", do: "unexpected"
    end

    assert_raise RuntimeError, ~r/must be disabled, prepared, or enabled/, fn ->
      Configuration.load!(:prod, get_env)
    end

    assert_received {:read, "MEMOVEE_TAMA_MCP_APP_MODE"}
    refute_received {:read, _other}
  end

  test "development and test retain enabled loopback defaults" do
    for environment <- [:dev, :test] do
      configuration = Configuration.load!(environment, fn _name -> nil end)

      assert configuration[:mode] == :enabled
      assert configuration[:allow_local?]
      assert :ok = MCP.validate(configuration)
    end
  end

  test "production defaults to disabled" do
    assert [mode: :disabled] = Configuration.load!(:prod, fn _name -> nil end)
  end

  test "prepared and enabled modes require every state-dependent value", context do
    for mode <- ["prepared", "enabled"], missing <- Configuration.required_environment() do
      environment = Map.delete(production_environment(context.private_key, mode), missing)

      assert_raise RuntimeError, ~r/#{missing} is required/, fn ->
        Configuration.load!(:prod, &Map.get(environment, &1))
      end
    end
  end

  test "production accepts exact HTTPS trust topology", context do
    environment = production_environment(context.private_key, "prepared")
    configuration = Configuration.load!(:prod, &Map.get(environment, &1))

    assert configuration[:mode] == :prepared
    refute configuration[:allow_local?]
    assert :ok = MCP.validate(configuration)
  end

  test "production rejects loopback HTTP and cross-origin Tama JWKS", context do
    loopback =
      context.private_key
      |> production_environment("enabled")
      |> Map.merge(%{
        "MEMOVEE_OAUTH_ISSUER" => "http://127.0.0.1:4000",
        "MEMOVEE_TAMA_MCP_APP_RESOURCE" => "http://127.0.0.1:4001/mcp/app",
        "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID" => "http://127.0.0.1:4001/mcp/app/introspection",
        "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI" => "http://127.0.0.1:4001/.well-known/jwks.json"
      })

    configuration = Configuration.load!(:prod, &Map.get(loopback, &1))
    assert {:error, :issuer} = MCP.validate(configuration)

    cross_origin =
      production_environment(context.private_key, "enabled")
      |> Map.put(
        "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI",
        "https://keys.example/.well-known/jwks.json"
      )

    configuration = Configuration.load!(:prod, &Map.get(cross_origin, &1))
    assert {:error, :introspection_jwks_uri} = MCP.validate(configuration)
  end

  test "public overlap keys are bounded JSON arrays", context do
    environment =
      context.private_key
      |> production_environment("prepared")
      |> Map.put("MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS", "{}")

    assert_raise RuntimeError, ~r/bounded JSON JWK array/, fn ->
      Configuration.load!(:prod, &Map.get(environment, &1))
    end
  end

  test "encoded signing key inputs enforce the published byte limits", context do
    private_environment =
      context.private_key
      |> production_environment("prepared")
      |> Map.put(
        "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY",
        String.duplicate("x", Configuration.private_signing_key_max_bytes() + 1)
      )

    assert_raise RuntimeError, ~r/MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY is invalid/, fn ->
      Configuration.load!(:prod, &Map.get(private_environment, &1))
    end

    public_environment =
      context.private_key
      |> production_environment("prepared")
      |> Map.put(
        "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS",
        String.duplicate("x", Configuration.public_signing_keys_max_bytes() + 1)
      )

    assert_raise RuntimeError, ~r/bounded JSON JWK array/, fn ->
      Configuration.load!(:prod, &Map.get(public_environment, &1))
    end
  end

  test ".envrc remains sourceable by a POSIX shell without direnv helpers" do
    envrc = Path.expand("../../../../../.envrc", __DIR__)

    assert {"", 0} =
             System.cmd("sh", ["-c", ~S(. "$1"), "sh", envrc],
               cd: System.tmp_dir!(),
               stderr_to_stdout: true
             )
  end

  test "committed contract matches parser and policy constants" do
    contract = @contract_path |> File.read!() |> Jason.decode!()

    assert contract["schema_version"] == Configuration.contract_version()
    assert contract["compatibility_identifier"] == Configuration.compatibility_identifier()

    assert contract["lifecycle"]["modes"] == Enum.map(Configuration.modes(), &to_string/1)

    assert contract["variables"]["MEMOVEE_OAUTH_SIGNING_ALGORITHM"]["allowed_values"] ==
             MCP.supported_algorithms()

    assert contract["variables"]["MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS"]["max_items"] ==
             Configuration.public_signing_key_limit()

    assert contract["variables"]["MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY"]["max_bytes"] ==
             Configuration.private_signing_key_max_bytes()

    assert contract["variables"]["MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS"]["max_bytes"] ==
             Configuration.public_signing_keys_max_bytes()

    assert contract["cache_policy"] == %{
             "authorization_server_metadata" => "no-store",
             "memovee_jwks" => "public, max-age=300"
           }

    assert contract["mode_gate_responses"] == MCP.mode_gate_contract()

    assert contract["local_development"] == %{
             "introspection_client_id" => "http://127.0.0.1:4001/mcp/app/introspection",
             "memovee_introspection_endpoint" => "http://127.0.0.1:4000/auth/introspections",
             "memovee_jwks_uri" => "http://127.0.0.1:4000/.well-known/jwks.json",
             "memovee_origin" => "http://127.0.0.1:4000",
             "resource" => "http://127.0.0.1:4001/mcp/app",
             "tama_jwks_uri" => "http://127.0.0.1:4001/.well-known/jwks.json",
             "tama_origin" => "http://127.0.0.1:4001"
           }

    required_from_contract =
      contract["variables"]
      |> Enum.filter(fn {_name, definition} ->
        definition["required_in"] == ["prepared", "enabled"]
      end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    assert required_from_contract == Enum.sort(Configuration.required_environment())
  end

  defp production_environment(private_key, mode) do
    %{
      "MEMOVEE_TAMA_MCP_APP_MODE" => mode,
      "MEMOVEE_OAUTH_ISSUER" => "https://memovee.example",
      "MEMOVEE_TAMA_MCP_APP_RESOURCE" => "https://tama.example/mcp/app",
      "MEMOVEE_OAUTH_SIGNING_ALGORITHM" => "RS256",
      "MEMOVEE_OAUTH_SIGNING_KEY_ID" => "memovee-contract-test-rs256-1",
      "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY" => private_key,
      "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS" => "[]",
      "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID" => "https://tama.example/mcp/app/introspection",
      "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI" => "https://tama.example/.well-known/jwks.json"
    }
  end
end
