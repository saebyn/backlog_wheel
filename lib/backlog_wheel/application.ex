defmodule BacklogWheel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BacklogWheelWeb.Telemetry,
      BacklogWheel.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:backlog_wheel, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:backlog_wheel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BacklogWheel.PubSub},
      # Start a worker by calling: BacklogWheel.Worker.start_link(arg)
      # {BacklogWheel.Worker, arg},
      # Start to serve requests, typically the last entry
      BacklogWheelWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BacklogWheel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BacklogWheelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, database migrations are run when using a release.
    System.get_env("RELEASE_NAME") == nil
  end
end
