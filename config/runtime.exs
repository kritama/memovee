import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/memovee start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :memovee, MemoveeWeb.Endpoint, server: true
end

config :memovee, MemoveeWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :memovee, MemoveeWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/memovee_web/router\.ex$"E,
        ~r"lib/memovee_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :memovee, Memovee.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :memovee, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :memovee, MemoveeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  oauth_issuer =
    System.get_env("MEMOVEE_OAUTH_ISSUER") ||
      raise "MEMOVEE_OAUTH_ISSUER is required in production"

  tama_resource =
    System.get_env("MEMOVEE_TAMA_MCP_APP_RESOURCE") ||
      raise "MEMOVEE_TAMA_MCP_APP_RESOURCE is required in production"

  signing_algorithm = System.get_env("MEMOVEE_OAUTH_SIGNING_ALGORITHM", "RS256")

  signing_key_id =
    System.get_env("MEMOVEE_OAUTH_SIGNING_KEY_ID") ||
      raise "MEMOVEE_OAUTH_SIGNING_KEY_ID is required in production"

  private_signing_key =
    System.get_env("MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY") ||
      raise "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY is required in production"

  private_signing_key =
    case Jason.decode(private_signing_key) do
      {:ok, %{} = key} -> key
      _error -> raise "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY must be a JSON JWK"
    end

  public_signing_keys =
    case System.get_env("MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS", "[]") |> Jason.decode() do
      {:ok, keys} when is_list(keys) -> keys
      _error -> raise "MEMOVEE_OAUTH_PUBLIC_SIGNING_KEYS must be a JSON array of JWKs"
    end

  trusted_proxies =
    case System.get_env("MEMOVEE_TRUSTED_PROXIES") do
      value when is_binary(value) ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _missing ->
        []
    end

  MemoveeWeb.Plugs.TrustedProxy.validate_proxies!(trusted_proxies)

  unless signing_algorithm in ["RS256", "PS256", "ES256"] do
    raise "MEMOVEE_OAUTH_SIGNING_ALGORITHM must be RS256, PS256, or ES256"
  end

  unless private_signing_key["kid"] == signing_key_id and
           private_signing_key["alg"] in [nil, signing_algorithm] do
    raise "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY must match the configured key ID and algorithm"
  end

  case Memovee.OAuth.KeyProvider.validate_signing_key(
         private_signing_key,
         signing_algorithm,
         signing_key_id
       ) do
    :ok ->
      :ok

    {:error, :invalid_signing_key} ->
      raise "MEMOVEE_OAUTH_PRIVATE_SIGNING_KEY must contain private signing material"
  end

  signing_keys =
    [private_signing_key | public_signing_keys]
    |> Enum.uniq_by(& &1["kid"])

  case TamaOAuth.JWKS.public_document(signing_keys) do
    {:ok, _jwks} -> :ok
    {:error, _reason} -> raise "OAuth signing keys do not form a valid public JWKS"
  end

  introspection_client_id =
    System.get_env("MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID") ||
      raise "MEMOVEE_TAMA_INTROSPECTION_CLIENT_ID is required in production"

  introspection_jwks_uri =
    System.get_env("MEMOVEE_TAMA_INTROSPECTION_JWKS_URI") ||
      raise "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI is required in production"

  unless String.starts_with?(oauth_issuer, "https://") do
    raise "MEMOVEE_OAUTH_ISSUER must use HTTPS in production"
  end

  unless String.starts_with?(tama_resource, "https://") do
    raise "MEMOVEE_TAMA_MCP_APP_RESOURCE must use HTTPS in production"
  end

  unless String.starts_with?(introspection_jwks_uri, "https://") do
    raise "MEMOVEE_TAMA_INTROSPECTION_JWKS_URI must use HTTPS in production"
  end

  config :memovee, Memovee.OAuth,
    issuer: oauth_issuer,
    resource: tama_resource,
    allow_local_client_metadata: false,
    signing_algorithm: signing_algorithm,
    signing_key_id: signing_key_id,
    signing_keys: signing_keys,
    introspection_client_id: introspection_client_id,
    introspection_jwks_uri: introspection_jwks_uri,
    introspection_bearer_token: nil

  config :memovee, MemoveeWeb.Plugs.TrustedProxy, proxies: trusted_proxies

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :memovee, MemoveeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :memovee, MemoveeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :memovee, Memovee.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
