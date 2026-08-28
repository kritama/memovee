# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :memovee, :scopes,
  user: [
    default: true,
    module: Memovee.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Memovee.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :memovee,
  ecto_repos: [Memovee.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :memovee, :environment, config_env()

config :memovee, Memovee.OAuth,
  issuer: "http://localhost:4000",
  resource: "http://localhost:4001/mcp/app",
  signing_algorithm: "RS256",
  signing_key_id: "memovee-oauth-local-1",
  signing_keys: [],
  allowed_client_ids: [],
  allowed_client_id_prefixes: [
    "https://chatgpt.com/oauth/",
    "https://chatgpt.com/oauth/codex/"
  ],
  allow_local_client_metadata: false,
  pre_registered_clients: %{},
  token_endpoint_auth_methods: ["none", "private_key_jwt"],
  token_endpoint_auth_signing_algorithms: ["RS256"],
  authorization_request_lifetime_seconds: 600,
  authorization_code_lifetime_seconds: 120,
  access_token_lifetime_seconds: 600,
  refresh_token_lifetime_seconds: 2_592_000,
  refresh_token_idle_lifetime_seconds: 604_800,
  cleanup_interval_ms: 900_000,
  client_assertion_clock_skew_seconds: 30,
  introspection_client_id: "tama-mcp-app",
  introspection_jwks_uri: nil,
  introspection_bearer_token: nil

# Configure the endpoint
config :memovee, MemoveeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MemoveeWeb.ErrorHTML, json: MemoveeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Memovee.PubSub,
  live_view: [signing_salt: "HQdINpyz"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :memovee, Memovee.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  memovee: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  memovee: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
