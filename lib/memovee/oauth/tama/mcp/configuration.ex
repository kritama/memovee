defmodule Memovee.OAuth.Tama.MCP.Configuration do
  @moduledoc false

  @contract_version "1"
  @compatibility_identifier "tama-mcp-app-bootstrap-v1"
  @private_signing_key_max_bytes 65_536
  @public_signing_keys_max_bytes 2_097_152
  @public_signing_key_limit 30
  @modes [:disabled, :prepared, :enabled]
  @hostname_label ~r/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/

  @required_environment ~w(
    MEMOVEE_OAUTH_ISSUER
    MEMOVEE_TAMA_MCP_APP_RESOURCE
    MEMOVEE_OAUTH_SIGNING_ALGORITHM
    MEMOVEE_OAUTH_SIGNING_KEY_ID
    MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY
    MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID
    MEMOVEE_TAMA_INTROSPECTION_JWKS_URI
  )

  @bounds [
    client_assertion_max_bytes: 16_384,
    client_assertion_max_lifetime_seconds: 300,
    client_assertion_clock_skew_seconds: 30,
    jwks_fetch_deadline_ms: 3_000
  ]

  @default_signing_key_specification {:rsa, 2_048}

  @development [
    issuer: "http://127.0.0.1:4000",
    resource: "http://127.0.0.1:4001/mcp/app",
    signing_algorithm: "RS256",
    signing_key_id: "memovee-oauth-local-rs256-1",
    public_signing_keys: [],
    introspection_client_id: "http://127.0.0.1:4001/mcp/app/introspection",
    introspection_jwks_uri: "http://127.0.0.1:4001/.well-known/jwks.json"
  ]

  @test [
    issuer: "http://127.0.0.1:4002",
    resource: "http://127.0.0.1:4001/mcp/app",
    signing_algorithm: "RS256",
    signing_key_id: "memovee-oauth-test-rs256-1",
    public_signing_keys: [],
    introspection_client_id: "http://127.0.0.1:4001/mcp/app/introspection",
    introspection_jwks_uri: "http://127.0.0.1:4001/.well-known/jwks.json"
  ]

  def contract_version, do: @contract_version
  def compatibility_identifier, do: @compatibility_identifier
  def private_signing_key_max_bytes, do: @private_signing_key_max_bytes
  def public_signing_keys_max_bytes, do: @public_signing_keys_max_bytes
  def public_signing_key_limit, do: @public_signing_key_limit
  def modes, do: @modes
  def required_environment, do: @required_environment

  @doc false
  def dns_hostname?(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _address} -> false
      {:error, _reason} -> hostname?(host)
    end
  rescue
    _error -> false
  end

  def dns_hostname?(_host), do: false

  @doc false
  def trusted_private_origins(resource) do
    case URI.parse(resource || "") do
      %URI{
        scheme: "https",
        host: host,
        port: port,
        path: "/mcp/app",
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when is_binary(host) and port in 1..65_535 ->
        if dns_hostname?(host), do: [String.replace_suffix(resource, "/mcp/app", "")], else: []

      _uri ->
        []
    end
  rescue
    _error -> []
  end

  def load!(environment, get_env \\ &System.get_env/1)

  def load!(environment, get_env)
      when environment in [:dev, :test, :prod] and is_function(get_env, 1) do
    case lifecycle(environment, get_env) do
      {:default, :enabled} -> default_configuration(environment)
      {_source, :disabled} -> [mode: :disabled]
      {_source, mode} -> configured_environment(mode, environment, get_env)
    end
  end

  def load!(_environment, _get_env), do: raise("unsupported Memovee runtime environment")

  defp lifecycle(environment, get_env) do
    case get_env.("MEMOVEE_TAMA_MCP_APP_MODE") do
      nil -> {:default, default_mode(environment)}
      mode -> {:mode, parse_mode!(mode)}
    end
  end

  defp default_mode(:prod), do: :disabled
  defp default_mode(environment) when environment in [:dev, :test], do: :enabled

  defp parse_mode!("disabled"), do: :disabled
  defp parse_mode!("prepared"), do: :prepared
  defp parse_mode!("enabled"), do: :enabled

  defp parse_mode!(_mode) do
    raise "MEMOVEE_TAMA_MCP_APP_MODE must be disabled, prepared, or enabled"
  end

  defp default_configuration(:dev), do: default_configuration(@development)
  defp default_configuration(:test), do: default_configuration(@test)

  defp default_configuration(values) do
    algorithm = Keyword.fetch!(values, :signing_algorithm)
    kid = Keyword.fetch!(values, :signing_key_id)

    signing_key = generate_signing_key!(algorithm, kid)

    configured(:enabled, Keyword.put(values, :signing_key, signing_key), true)
  end

  defp configured_environment(mode, environment, get_env) do
    algorithm = required!(get_env, "MEMOVEE_OAUTH_SIGNING_ALGORITHM")
    kid = required!(get_env, "MEMOVEE_OAUTH_SIGNING_KEY_ID")

    signing_key =
      get_env
      |> required!("MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY")
      |> load_signing_key!(algorithm, kid)

    values = [
      issuer: required!(get_env, "MEMOVEE_OAUTH_ISSUER"),
      resource: required!(get_env, "MEMOVEE_TAMA_MCP_APP_RESOURCE"),
      signing_algorithm: algorithm,
      signing_key_id: kid,
      signing_key: signing_key,
      public_signing_keys: public_signing_keys!(get_env),
      introspection_client_id: required!(get_env, "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID"),
      introspection_jwks_uri: required!(get_env, "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI")
    ]

    configured(mode, values, environment in [:dev, :test])
  end

  defp configured(mode, values, allow_local?) do
    values =
      Keyword.put(
        values,
        :trusted_private_origins,
        values |> Keyword.get(:resource) |> trusted_private_origins()
      )

    [mode: mode]
    |> Keyword.merge(@bounds)
    |> Keyword.merge(values)
    |> Keyword.put(:allow_local?, allow_local?)
  end

  defp required!(get_env, name) do
    get_env.(name) || raise "#{name} is required when the Tama MCP app is configured"
  end

  defp load_signing_key!(source, algorithm, kid)
       when is_binary(source) and byte_size(source) in 1..@private_signing_key_max_bytes do
    case TamaOAuth.SigningKey.load(source,
           algorithm: algorithm,
           algorithms: [algorithm],
           kid: kid,
           stage: :oauth_signing_key
         ) do
      {:ok, key} -> key
      {:error, _error} -> raise "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY is invalid"
    end
  end

  defp load_signing_key!(_source, _algorithm, _kid) do
    raise "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY is invalid"
  end

  defp generate_signing_key!(algorithm, kid) do
    case TamaOAuth.SigningKey.generate(@default_signing_key_specification,
           algorithm: algorithm,
           algorithms: [algorithm],
           kid: kid,
           stage: :oauth_signing_key
         ) do
      {:ok, key} -> key
      {:error, _error} -> raise "failed to generate the local Memovee OAuth signing key"
    end
  end

  defp public_signing_keys!(get_env) do
    encoded = get_env.("MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS") || "[]"

    if is_binary(encoded) and byte_size(encoded) <= @public_signing_keys_max_bytes do
      case Jason.decode(encoded) do
        {:ok, keys} when is_list(keys) and length(keys) <= @public_signing_key_limit -> keys
        _error -> raise "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS must be a bounded JSON JWK array"
      end
    else
      raise "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS must be a bounded JSON JWK array"
    end
  end

  defp hostname?(host) when byte_size(host) in 1..253 do
    host
    |> String.split(".")
    |> Enum.all?(&Regex.match?(@hostname_label, &1))
  end

  defp hostname?(_host), do: false
end
