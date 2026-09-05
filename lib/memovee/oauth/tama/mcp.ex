defmodule Memovee.OAuth.Tama.MCP do
  @moduledoc "The exact resource, scope, and client trust policy for Tama `/mcp/app`."

  alias Memovee.OAuth
  alias Memovee.OAuth.Tama.MCP.Configuration
  alias TamaOAuth.{Error, Scope, URI}

  @scope "mcp.message"
  @supported_algorithms ["RS256", "PS256", "ES256"]
  @max_uri_bytes 2_048
  @max_key_id_bytes 128

  @mode_gate_contract %{
    "disabled" => %{
      "authorization" => %{"status" => 503, "error" => "temporarily_unavailable"},
      "introspection" => %{"status" => 401, "error" => "invalid_client"},
      "jwks" => %{"status" => 404},
      "metadata" => %{"status" => 404},
      "registration" => %{"status" => 503, "error" => "temporarily_unavailable"},
      "revocation" => %{"status" => 503, "error" => "temporarily_unavailable"},
      "token" => %{"status" => 400, "error" => "invalid_grant"}
    },
    "prepared" => %{
      "authorization" => %{"status" => 503, "error" => "temporarily_unavailable"},
      "introspection" => %{"available" => true},
      "jwks" => %{"available" => true},
      "metadata" => %{"available" => true},
      "registration" => %{"status" => 503, "error" => "temporarily_unavailable"},
      "revocation" => %{"available" => true},
      "token" => %{"status" => 400, "error" => "invalid_grant"}
    },
    "enabled" => %{
      "authorization" => %{"available" => true},
      "introspection" => %{"available" => true},
      "jwks" => %{"available" => true},
      "metadata" => %{"available" => true},
      "registration" => %{"available" => true},
      "revocation" => %{"available" => true},
      "token" => %{"available" => true}
    }
  }

  def resource, do: OAuth.resource()
  def mode, do: OAuth.config(:mode)
  def configured?, do: mode() in [:prepared, :enabled]
  def enabled?, do: mode() == :enabled
  def supported_algorithms, do: @supported_algorithms
  def mode_gate_contract, do: @mode_gate_contract

  def require_configured(error_code \\ :temporarily_unavailable) do
    if configured?(), do: :ok, else: integration_error(error_code)
  end

  def require_enabled(error_code \\ :temporarily_unavailable) do
    if enabled?(), do: :ok, else: integration_error(error_code)
  end

  def supported_scopes, do: [@scope]
  def default_scopes, do: [@scope]

  def normalize_scope(nil), do: {:ok, @scope}
  def normalize_scope(scope), do: Scope.normalize(scope, supported_scopes())
  def parse_scope(scope), do: Scope.parse(scope, supported_scopes())

  def allowed_client_id?(client_id) when is_binary(client_id) do
    client_id in OAuth.config(:allowed_client_ids, []) or
      Enum.any?(OAuth.config(:allowed_client_id_prefixes, []), fn prefix ->
        URI.scoped_client_id?(client_id, prefix)
      end) or
      (OAuth.config(:allow_local_client_metadata, false) and
         TamaOAuth.ClientMetadata.valid_client_id_url?(client_id, allow_local?: true))
  end

  def allowed_client_id?(_client_id), do: false

  def validate_config! do
    configuration = OAuth.config()

    case validate(configuration) do
      :ok -> :ok
      {:error, field} -> raise "invalid Memovee Tama MCP app configuration: #{field}"
    end
  end

  def validate(configuration) when is_list(configuration) do
    with :ok <- validate_mode(configuration[:mode]) do
      if configuration[:mode] == :disabled, do: :ok, else: validate_configured(configuration)
    end
  end

  def validate(_configuration), do: {:error, :configuration}

  defp validate_configured(configuration) do
    allow_local? = Keyword.get(configuration, :allow_local?, false)

    with :ok <- validate_origin(configuration[:issuer], allow_local?, :issuer),
         :ok <- validate_endpoint(configuration[:resource], "/mcp/app", allow_local?, :resource),
         :ok <- validate_tama_resource_hostname(configuration[:resource]),
         :ok <-
           validate_trusted_private_origins(
             configuration[:trusted_private_origins],
             configuration[:resource]
           ),
         :ok <-
           validate_derived_tama_endpoint(
             configuration[:introspection_jwks_uri],
             "/.well-known/jwks.json",
             String.replace_suffix(
               configuration[:resource],
               "/mcp/app",
               "/.well-known/jwks.json"
             ),
             allow_local?,
             :introspection_jwks_uri
           ),
         :ok <- validate_algorithm(configuration[:signing_algorithm]),
         :ok <-
           validate_identifier(
             configuration[:signing_key_id],
             :signing_key_id,
             @max_key_id_bytes
           ),
         :ok <-
           validate_derived_tama_endpoint(
             configuration[:introspection_client_id],
             "/mcp/app/introspection",
             configuration[:resource] <> "/introspection",
             allow_local?,
             :introspection_client_id
           ),
         :ok <- validate_public_signing_keys(configuration[:public_signing_keys]) do
      validate_bounds(configuration)
    end
  end

  defp validate_mode(mode) do
    if mode in Configuration.modes(), do: :ok, else: {:error, :mode}
  end

  defp validate_origin(value, allow_local?, field) do
    valid? =
      case parse_bounded_uri(value) do
        %Elixir.URI{path: path, query: nil, fragment: nil, userinfo: nil} = uri
        when path in [nil, ""] ->
          allowed_web_uri?(uri, allow_local?)

        _uri ->
          false
      end

    if valid?, do: :ok, else: {:error, field}
  end

  defp validate_endpoint(value, path, allow_local?, field) do
    valid? =
      case parse_bounded_uri(value) do
        %Elixir.URI{path: ^path, query: nil, fragment: nil, userinfo: nil} = uri ->
          allowed_web_uri?(uri, allow_local?)

        _uri ->
          false
      end

    if valid?, do: :ok, else: {:error, field}
  end

  defp validate_derived_tama_endpoint(value, path, expected, allow_local?, field) do
    valid? =
      value == expected and validate_endpoint(value, path, allow_local?, field) == :ok

    if valid?, do: :ok, else: {:error, field}
  end

  defp validate_algorithm(algorithm) do
    if algorithm in @supported_algorithms, do: :ok, else: {:error, :signing_algorithm}
  end

  defp validate_tama_resource_hostname(resource) do
    valid? =
      case parse_bounded_uri(resource) do
        %Elixir.URI{scheme: "https", host: host} -> Configuration.dns_hostname?(host)
        %Elixir.URI{} -> true
        _uri -> false
      end

    if valid?, do: :ok, else: {:error, :resource}
  end

  defp validate_trusted_private_origins(origins, resource) do
    expected = Configuration.trusted_private_origins(resource)
    if origins == expected, do: :ok, else: {:error, :trusted_private_origins}
  end

  defp validate_identifier(value, field, max_bytes)
       when is_binary(value) and byte_size(value) in 1..max_bytes//1 do
    if String.trim(value) != "" and not String.match?(value, ~r/[\x00-\x1F\x7F]/),
      do: :ok,
      else: {:error, field}
  end

  defp validate_identifier(_value, field, _max_bytes), do: {:error, field}

  defp validate_public_signing_keys(keys) when is_list(keys) do
    if length(keys) <= Configuration.public_signing_key_limit(),
      do: :ok,
      else: {:error, :public_signing_keys}
  end

  defp validate_public_signing_keys(_keys), do: {:error, :public_signing_keys}

  defp validate_bounds(configuration) do
    bounds = [
      client_assertion_max_bytes: 1..16_384,
      client_assertion_max_lifetime_seconds: 1..300,
      client_assertion_clock_skew_seconds: 0..300,
      jwks_fetch_deadline_ms: 1..5_000
    ]

    Enum.find_value(bounds, :ok, fn {field, range} ->
      value = configuration[field]
      if is_integer(value) and value in range, do: false, else: {:error, field}
    end)
  end

  defp parse_bounded_uri(value)
       when is_binary(value) and byte_size(value) in 1..@max_uri_bytes,
       do: Elixir.URI.parse(value)

  defp parse_bounded_uri(_value), do: nil

  defp allowed_web_uri?(%Elixir.URI{scheme: "https", host: host, port: port}, _allow_local?),
    do: valid_host_and_port?(host, port)

  defp allowed_web_uri?(%Elixir.URI{scheme: "http", host: host, port: port}, true),
    do: valid_host_and_port?(host, port) and URI.loopback_host?(String.downcase(host))

  defp allowed_web_uri?(_uri, _allow_local?), do: false

  defp valid_host_and_port?(host, port),
    do: is_binary(host) and host != "" and is_integer(port) and port in 1..65_535

  defp integration_error(code), do: {:error, Error.new(code, stage: :integration_mode)}
end
