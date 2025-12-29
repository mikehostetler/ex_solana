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

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
