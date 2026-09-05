defmodule Memovee.Config.RuntimeTest do
  use ExUnit.Case, async: false

  @oauth_environment ~w(
    MEMOVEE_TAMA_MCP_APP_MODE
    MEMOVEE_TAMA_MCP_APP_MODE_TEST
    MEMOVEE_OAUTH_ISSUER
    MEMOVEE_TAMA_MCP_APP_RESOURCE
    MEMOVEE_OAUTH_SIGNING_ALGORITHM
    MEMOVEE_OAUTH_SIGNING_KEY_ID
    MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY
    MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS
    MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID
    MEMOVEE_TAMA_INTROSPECTION_JWKS_URI
  )

  setup do
    original = Map.new(@oauth_environment, &{&1, System.get_env(&1)})
    Enum.each(@oauth_environment, &System.delete_env/1)

    {:ok, private_key} =
      TamaOAuth.SigningKey.generate({:rsa, 2_048},
        algorithm: "RS256",
        algorithms: ["RS256"],
        kid: "memovee-runtime-test-rs256-1"
      )

    System.put_env(%{
      "MEMOVEE_TAMA_MCP_APP_MODE_TEST" => "prepared",
      "MEMOVEE_OAUTH_ISSUER" => "https://app.localhost",
      "MEMOVEE_TAMA_MCP_APP_RESOURCE" => "https://tama.app.localhost/mcp/app",
      "MEMOVEE_OAUTH_SIGNING_ALGORITHM" => "RS256",
      "MEMOVEE_OAUTH_SIGNING_KEY_ID" => "memovee-runtime-test-rs256-1",
      "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY" => Jason.encode!(private_key),
      "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS" => "[]",
      "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID" =>
        "https://tama.app.localhost/mcp/app/introspection",
      "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI" => "https://tama.app.localhost/.well-known/jwks.json"
    })

    on_exit(fn -> restore_environment(original) end)
  end

  test "configures TamaOAuth with the exact origin derived from the Tama resource" do
    configuration = read_runtime_configuration()

    assert [trusted_private_origins: ["https://tama.app.localhost"]] =
             configuration
             |> Keyword.fetch!(:tama_oauth)
             |> Keyword.fetch!(TamaOAuth.RemoteJSON)
  end

  test "standalone development retains loopback endpoint defaults" do
    configuration = read_development_endpoint_configuration()

    assert configuration[:http][:ip] == {127, 0, 0, 1}
    assert configuration[:check_origin] == false
    refute Keyword.has_key?(configuration, :url)
  end

  test "configured development enables the exact Compose proxy endpoint" do
    System.put_env("MEMOVEE_TAMA_MCP_APP_MODE", "prepared")
    System.put_env("MEMOVEE_OAUTH_ISSUER", "https://app.localhost")

    configuration = read_development_endpoint_configuration()

    assert configuration[:http][:ip] == {0, 0, 0, 0}
    assert configuration[:check_origin] == ["https://app.localhost"]
    assert configuration[:url] == [scheme: "https", host: "app.localhost", port: 443]
  end

  defp read_runtime_configuration do
    config_path = Path.expand("../../config/config.exs", __DIR__)
    runtime_path = Path.expand("../../config/runtime.exs", __DIR__)

    config_path
    |> Config.Reader.read!(env: :test)
    |> Config.Reader.merge(Config.Reader.read!(runtime_path, env: :test))
  end

  defp read_development_endpoint_configuration do
    Path.expand("../../config/dev.exs", __DIR__)
    |> Config.Reader.read!(env: :dev)
    |> Keyword.fetch!(:memovee)
    |> Keyword.fetch!(MemoveeWeb.Endpoint)
  end

  defp restore_environment(environment) do
    Enum.each(environment, fn
      {name, nil} -> System.delete_env(name)
      {name, value} -> System.put_env(name, value)
    end)
  end
end
