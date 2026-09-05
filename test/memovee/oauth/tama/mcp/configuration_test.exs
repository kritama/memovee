defmodule Memovee.OAuth.Tama.MCP.ConfigurationTest do
  use ExUnit.Case, async: true

  alias Memovee.OAuth.Tama.MCP
  alias Memovee.OAuth.Tama.MCP.Configuration

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
      assert configuration[:trusted_private_origins] == []
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
    assert configuration[:trusted_private_origins] == ["https://tama.example"]
    assert :ok = MCP.validate(configuration)
  end

  test "development accepts the exact generated local HTTPS topology", context do
    environment = local_https_environment(context.private_key, "prepared")
    configuration = Configuration.load!(:dev, &Map.get(environment, &1))

    assert configuration[:mode] == :prepared
    assert configuration[:issuer] == "https://app.localhost"
    assert configuration[:resource] == "https://tama.app.localhost/mcp/app"
    assert configuration[:allow_local?]
    assert configuration[:trusted_private_origins] == ["https://tama.app.localhost"]
    assert :ok = MCP.validate(configuration)
  end

  test "derives an exact private origin including a configured port", context do
    environment =
      context.private_key
      |> production_environment("prepared")
      |> replace_tama_origin("https://tama.example:8443")

    configuration = Configuration.load!(:prod, &Map.get(environment, &1))

    assert configuration[:trusted_private_origins] == ["https://tama.example:8443"]
    assert :ok = MCP.validate(configuration)
  end

  test "does not trust HTTPS resources identified by IP literals or invalid hostnames", context do
    hosts = [
      "8.8.8.8",
      "10.0.0.2",
      "127.0.0.1",
      "169.254.169.254",
      "[fc00::1]",
      "-tama.example",
      "tama-.example",
      "tama..example",
      "tama.example."
    ]

    for host <- hosts do
      environment =
        context.private_key
        |> production_environment("prepared")
        |> replace_tama_origin("https://#{host}")

      configuration = Configuration.load!(:prod, &Map.get(environment, &1))

      assert configuration[:trusted_private_origins] == []
      assert {:error, :resource} = MCP.validate(configuration)
    end
  end

  test "rejects drift from the private origin derived from the Tama resource", context do
    environment = local_https_environment(context.private_key, "prepared")
    configuration = Configuration.load!(:dev, &Map.get(environment, &1))

    for origins <- [
          nil,
          [],
          ["http://tama.app.localhost"],
          ["https://other.localhost"],
          ["https://tama.app.localhost", "https://tama.app.localhost"]
        ] do
      assert {:error, :trusted_private_origins} =
               configuration
               |> Keyword.put(:trusted_private_origins, origins)
               |> MCP.validate()
    end
  end

  test "configured environments require exact Tama-derived trust identities", context do
    cases = [
      {"MEMOVEE_TAMA_INTROSPECTION_JWKS_URI",
       "https://tama.app.localhost:443/.well-known/jwks.json", :introspection_jwks_uri},
      {"MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID",
       "https://tama.app.localhost/mcp/app/introspection/", :introspection_client_id}
    ]

    for runtime_environment <- [:dev, :prod], {variable, value, field} <- cases do
      environment =
        context.private_key
        |> local_https_environment("prepared")
        |> Map.put(variable, value)

      configuration = Configuration.load!(runtime_environment, &Map.get(environment, &1))
      assert {:error, ^field} = MCP.validate(configuration)
    end
  end

  test "development still rejects HTTP .localhost public identities", context do
    environment =
      context.private_key
      |> local_https_environment("prepared")
      |> Map.merge(%{
        "MEMOVEE_OAUTH_ISSUER" => "http://app.localhost",
        "MEMOVEE_TAMA_MCP_APP_RESOURCE" => "http://tama.app.localhost/mcp/app",
        "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID" =>
          "http://tama.app.localhost/mcp/app/introspection",
        "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI" => "http://tama.app.localhost/.well-known/jwks.json"
      })

    configuration = Configuration.load!(:dev, &Map.get(environment, &1))
    assert {:error, :issuer} = MCP.validate(configuration)
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

  test ".envrc exports the managed provider fragment through a POSIX shell" do
    envrc = Path.expand("../../../../../.envrc", __DIR__)
    root = Path.join(System.tmp_dir!(), "memovee-envrc-#{System.unique_integer([:positive])}")
    fragment_directory = Path.join(root, "tama")
    File.mkdir_p!(fragment_directory)
    File.cp!(envrc, Path.join(root, ".envrc"))
    File.write!(Path.join(fragment_directory, ".memovee.integration.env"), "LOADER_TEST=loaded\n")

    on_exit(fn -> File.rm_rf!(root) end)

    assert {"", 0} =
             System.cmd("sh", ["-c", ~S(. ./.envrc && env | grep -q '^LOADER_TEST=loaded$')],
               cd: root,
               stderr_to_stdout: true
             )
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

  defp local_https_environment(private_key, mode) do
    %{
      "MEMOVEE_TAMA_MCP_APP_MODE" => mode,
      "MEMOVEE_OAUTH_ISSUER" => "https://app.localhost",
      "MEMOVEE_TAMA_MCP_APP_RESOURCE" => "https://tama.app.localhost/mcp/app",
      "MEMOVEE_OAUTH_SIGNING_ALGORITHM" => "RS256",
      "MEMOVEE_OAUTH_SIGNING_KEY_ID" => "memovee-contract-test-rs256-1",
      "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY" => private_key,
      "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS" => "[]",
      "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID" =>
        "https://tama.app.localhost/mcp/app/introspection",
      "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI" => "https://tama.app.localhost/.well-known/jwks.json"
    }
  end

  defp replace_tama_origin(environment, origin) do
    environment
    |> Map.put("MEMOVEE_TAMA_MCP_APP_RESOURCE", origin <> "/mcp/app")
    |> Map.put("MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID", origin <> "/mcp/app/introspection")
    |> Map.put("MEMOVEE_TAMA_INTROSPECTION_JWKS_URI", origin <> "/.well-known/jwks.json")
  end
end
