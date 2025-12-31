defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Telemetry handler for agent and strategy metrics
      Jido.Telemetry,

      # Component discovery catalog (global - not per-instance)
      Jido.Discovery
    ]

    # Register essential signal extensions before starting supervision tree
    register_signal_extensions()

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
