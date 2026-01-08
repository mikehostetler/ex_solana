defmodule JidoFlame.Remote do
  @moduledoc """
  Helper functions for code running on remote FLAME nodes.

  Use these functions in agents or processes running on FLAME runners
  to communicate with their parent nodes.

  ## Usage

  In a remote agent, emit signals to parent:

      # Assuming parent_ref was passed in opts
      JidoFlame.Remote.emit_to_parent(parent_ref, "task.completed", %{result: data})
  """

  require Logger

  @doc """
  Emits a signal to the parent agent via the Owner process.

  ## Parameters

  - `parent_ref` - Map with `:owner_pid` and optionally `:logical_agent_id`, `:meta`
  - `type` - Signal type string (CloudEvents type)
  - `data` - Signal data map

  ## Examples

      parent_ref = %{owner_pid: owner, logical_agent_id: "agent-1"}
      JidoFlame.Remote.emit_to_parent(parent_ref, "work.done", %{result: 42})
  """
  @spec emit_to_parent(map(), String.t(), map()) :: :ok | {:error, :no_owner}
  def emit_to_parent(%{owner_pid: owner_pid} = _parent_ref, type, data) when is_pid(owner_pid) do
    signal = %{
      type: type,
      source: inspect(self()),
      data: data,
      time: DateTime.utc_now()
    }

    send(owner_pid, {:remote_child_signal, signal})
    :ok
  end

  def emit_to_parent(_parent_ref, _type, _data) do
    Logger.warning("[JidoFlame.Remote] Cannot emit - no owner_pid in parent_ref")
    {:error, :no_owner}
  end

  @doc """
  Checks if we're running on a FLAME runner.
  """
  @spec flame_runner?() :: boolean()
  def flame_runner? do
    FLAME.Parent.get() != nil
  end

  @doc """
  Returns the FLAME parent info if running on a runner.
  """
  @spec flame_parent() :: map() | nil
  def flame_parent do
    FLAME.Parent.get()
  end

  @doc """
  Returns info about the current remote execution context.
  """
  @spec context() :: map()
  def context do
    %{
      node: node(),
      flame_runner?: flame_runner?(),
      flame_parent: flame_parent()
    }
  end
end
