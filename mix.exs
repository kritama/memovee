defmodule Memovee.MixProject do
  use Mix.Project

  def project do
    [
      app: :memovee,
      version: "0.1.2",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_add_apps: [:ex_unit, :mix],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Memovee.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Web framework and server
      {:phoenix, "~> 1.8.12"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:bandit, "~> 1.5"},
      {:gettext, "~> 1.0"},

      # Database and resource lifecycle
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:eventful, "~> 3.3"},

      # Background jobs, caching and clustering
      {:oban, "~> 2.24.1"},
      {:nebulex, "~> 3.0"},
      {:nebulex_local, "~> 3.0"},
      {:dns_cluster, "~> 0.2.0"},

      # Authentication and request protection
      {:bcrypt_elixir, "~> 3.0"},
      {:hammer, "~> 7.0"},
      {:remote_ip, "~> 1.2"},
      {:tama_oauth, "~> 0.4.1"},

      # HTTP, JSON and API documentation
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:open_api_spex, "~> 3.22"},

      # Email delivery
      {:swoosh, "~> 1.16"},

      # Frontend assets and components
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      # Monitoring and telemetry
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Development, testing and code quality
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind memovee", "esbuild memovee"],
      "assets.deploy": [
        "tailwind memovee --minify",
        "esbuild memovee --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
