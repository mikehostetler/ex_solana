defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Task Supervisor for async action execution
      {Task.Supervisor, name: Jido.TaskSupervisor},

      # Global Registry for agent processes
      {Registry, keys: :unique, name: Jido.Registry},

      # Dynamic Supervisor for agent processes
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor}
    ]

    # Initialize Discovery catalog asynchronously
    Task.start(fn -> Jido.Discovery.init() end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
