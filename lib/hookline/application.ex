defmodule Hookline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HooklineWeb.Telemetry,
      Hookline.Repo,
      {DNSCluster, query: Application.get_env(:hookline, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hookline.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Hookline.Finch},
      {Oban, Application.fetch_env!(:hookline, Oban)},
      # Start a worker by calling: Hookline.Worker.start_link(arg)
      # {Hookline.Worker, arg},
      # Start to serve requests, typically the last entry
      HooklineWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hookline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HooklineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
