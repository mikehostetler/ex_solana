defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Telemetry handler for agent and strategy metrics
      Jido.Telemetry,

      # Shared task supervisor for async directive work (LLMs, HTTP, heavy IO)
      {Task.Supervisor, name: Jido.TaskSupervisor, max_children: 1000},

      # Global registry for agent lookup by ID
      {Registry, keys: :unique, name: Jido.Registry},

      # Dynamic supervisor for all agent instances (flat hierarchy)
      {DynamicSupervisor,
       name: Jido.AgentSupervisor, strategy: :one_for_one, max_restarts: 1000, max_seconds: 5}
    ]

    # Register essential signal extensions before starting supervision tree
    register_signal_extensions()

    # Initialize discovery catalog asynchronously
    Task.start(fn -> Jido.Discovery.init() end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end

  # Ensure critical signal extensions are registered
  defp register_signal_extensions do
    extensions = [
      Jido.Signal.Ext.Trace,
      Jido.Signal.Ext.Dispatch,
      Jido.Signal.Ext.Target
    ]

    for ext <- extensions do
      Code.ensure_loaded(ext)
      Jido.Signal.Ext.Registry.register(ext)
    end

    :ok
  rescue
    # Gracefully handle missing modules during compilation or testing
    _ -> :ok
  end
end
