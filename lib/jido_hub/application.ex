defmodule JidoHub.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JidoHubWeb.Telemetry,
      JidoHub.Repo,
      {DNSCluster, query: JidoHub.config(:dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:jido_hub, :ash_domains),
         Application.fetch_env!(:jido_hub, Oban)
       )},
      {Phoenix.PubSub, name: JidoHub.PubSub},
      JidoHubWeb.Presence,
      {Task.Supervisor, name: JidoHub.Logs.TaskSupervisor},
      # Start a worker by calling: JidoHub.Worker.start_link(arg)
      # {JidoHub.Worker, arg},
      # Start to serve requests, typically the last entry
      JidoHubWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :jido_hub]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JidoHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JidoHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
