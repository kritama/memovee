defmodule Memovee.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MemoveeWeb.Telemetry,
      Memovee.Repo,
      Memovee.OAuth.Cache,
      Memovee.OAuth.RateLimiter,
      Memovee.OAuth.Cleanup,
      {DNSCluster, query: Application.get_env(:memovee, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Memovee.PubSub},
      # Start a worker by calling: Memovee.Worker.start_link(arg)
      # {Memovee.Worker, arg},
      # Start to serve requests, typically the last entry
      MemoveeWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Memovee.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MemoveeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
