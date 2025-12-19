defmodule JidoCode.Telemetry.AgentInstrumentation do
  @moduledoc """
  Telemetry instrumentation for agent lifecycle events.

  This module provides functions to emit telemetry events for agent start, stop,
  and crash events. It also tracks restart counts per agent to detect restart loops.

  ## Telemetry Events

  The following events are emitted:

  ### `[:jido_code, :agent, :start]`

  Emitted when an agent starts.

  - Measurements: `%{system_time: integer()}`
  - Metadata: `%{name: atom(), module: module()}`

  ### `[:jido_code, :agent, :stop]`

  Emitted when an agent stops normally.

  - Measurements: `%{duration: integer()}` (native time units)
  - Metadata: `%{name: atom(), module: module(), reason: term()}`

  ### `[:jido_code, :agent, :crash]`

  Emitted when an agent crashes or exits abnormally.

  - Measurements: `%{duration: integer()}` (native time units)
  - Metadata: `%{name: atom(), module: module(), reason: term(), restart_count: integer()}`

  ## Logger Integration

  Attach the built-in logger handler to log telemetry events:

      JidoCode.Telemetry.AgentInstrumentation.attach_logger(level: :info)

  Detach when no longer needed:

      JidoCode.Telemetry.AgentInstrumentation.detach_logger()

  ## Restart Tracking

  Restart counts are tracked per agent name using an ETS table. The count is
  incremented on each crash and reset when an agent stops normally.

      # Get restart count for an agent
      JidoCode.Telemetry.AgentInstrumentation.restart_count(:my_agent)
      # => 0

  """

  require Logger

  @ets_table :jido_code_agent_restarts
  @logger_handler_id :jido_code_agent_logger

  # Telemetry event names
  @event_start [:jido_code, :agent, :start]
  @event_stop [:jido_code, :agent, :stop]
  @event_crash [:jido_code, :agent, :crash]

  # ============================================================================
  # Setup
  # ============================================================================

  @doc """
  Initializes the restart tracking ETS table.

  This is called automatically when the application starts, but can be called
  manually in tests. The function is idempotent and thread-safe - it can be
  called multiple times without error.

  ## ARCH-3 Fix

  The table is created during application startup to prevent race conditions.
  If called concurrently, only one call will create the table; others will
  silently succeed.
  """
  @spec setup() :: :ok
  def setup do
    # ARCH-3 Fix: Use try/catch to handle concurrent table creation attempts
    # :ets.new/2 will raise ArgumentError if table already exists with :named_table
    try do
      if :ets.whereis(@ets_table) == :undefined do
        :ets.new(@ets_table, [:named_table, :public, :set])
      end
    catch
      # Table was created by another process between whereis check and new
      :error, :badarg -> :ok
    end

    :ok
  end

  # ============================================================================
  # Telemetry Event Emission
  # ============================================================================

  @doc """
  Emits a telemetry event when an agent starts.

  Records the start time for duration calculation on stop/crash.

  ## Parameters

  - `name` - The agent's registered name
  - `module` - The agent's module

  ## Returns

  The system time at start (for duration tracking).
  """
  @spec emit_start(atom(), module()) :: integer()
  def emit_start(name, module) do
    setup()
    start_time = System.monotonic_time()

    # Store start time for duration calculation
    :ets.insert(@ets_table, {{:start_time, name}, start_time})

    :telemetry.execute(
      @event_start,
      %{system_time: System.system_time()},
      %{name: name, module: module}
    )

    start_time
  end

  @doc """
  Emits a telemetry event when an agent stops normally.

  Resets the restart count for this agent.

  ## Parameters

  - `name` - The agent's registered name
  - `module` - The agent's module
  - `reason` - The stop reason (usually `:normal` or `:shutdown`)
  """
  @spec emit_stop(atom(), module(), term()) :: :ok
  def emit_stop(name, module, reason) do
    setup()
    duration = calculate_duration(name)

    # Reset restart count on normal stop
    :ets.delete(@ets_table, {:restart_count, name})
    :ets.delete(@ets_table, {:start_time, name})

    :telemetry.execute(
      @event_stop,
      %{duration: duration},
      %{name: name, module: module, reason: reason}
    )

    :ok
  end

  @doc """
  Emits a telemetry event when an agent crashes.

  Increments the restart count for this agent.

  ## Parameters

  - `name` - The agent's registered name
  - `module` - The agent's module
  - `reason` - The crash reason
  """
  @spec emit_crash(atom(), module(), term()) :: :ok
  def emit_crash(name, module, reason) do
    setup()
    duration = calculate_duration(name)

    # Increment restart count
    count = increment_restart_count(name)

    :telemetry.execute(
      @event_crash,
      %{duration: duration},
      %{name: name, module: module, reason: reason, restart_count: count}
    )

    :ok
  end

  # ============================================================================
  # Restart Count Tracking
  # ============================================================================

  @doc """
  Returns the current restart count for an agent.

  ## Parameters

  - `name` - The agent's registered name

  ## Returns

  The number of times the agent has crashed since last normal stop.
  """
  @spec restart_count(atom()) :: non_neg_integer()
  def restart_count(name) do
    setup()

    case :ets.lookup(@ets_table, {:restart_count, name}) do
      [{{:restart_count, ^name}, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Resets the restart count for an agent.

  ## Parameters

  - `name` - The agent's registered name
  """
  @spec reset_restart_count(atom()) :: :ok
  def reset_restart_count(name) do
    setup()
    :ets.delete(@ets_table, {:restart_count, name})
    :ok
  end

  # ============================================================================
  # Logger Handler
  # ============================================================================

  @doc """
  Attaches a Logger handler for agent telemetry events.

  ## Options

  - `:level` - Log level to use (default: `:info`)

  ## Examples

      JidoCode.Telemetry.AgentInstrumentation.attach_logger()
      JidoCode.Telemetry.AgentInstrumentation.attach_logger(level: :debug)
  """
  @spec attach_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :info)

    :telemetry.attach_many(
      @logger_handler_id,
      [@event_start, @event_stop, @event_crash],
      &handle_telemetry_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the Logger handler for agent telemetry events.
  """
  @spec detach_logger() :: :ok | {:error, :not_found}
  def detach_logger do
    :telemetry.detach(@logger_handler_id)
  end

  # ============================================================================
  # Event Names (for external attachment)
  # ============================================================================

  @doc """
  Returns the telemetry event name for agent start events.
  """
  @spec event_start() :: [atom()]
  def event_start, do: @event_start

  @doc """
  Returns the telemetry event name for agent stop events.
  """
  @spec event_stop() :: [atom()]
  def event_stop, do: @event_stop

  @doc """
  Returns the telemetry event name for agent crash events.
  """
  @spec event_crash() :: [atom()]
  def event_crash, do: @event_crash

  # ============================================================================
  # ETS Accessor Functions (for AgentSupervisor)
  # ============================================================================

  @doc """
  Stores the module for an agent name in the instrumentation table.

  Used by AgentSupervisor to track agent module associations.
  """
  @spec store_agent_module(atom(), module()) :: true
  def store_agent_module(name, module) when is_atom(name) do
    :ets.insert(@ets_table, {{:module, name}, module})
  end

  @doc """
  Retrieves the module for an agent name.

  Returns `{:ok, module}` if found, `:error` otherwise.
  """
  @spec get_agent_module(atom()) :: {:ok, module()} | :error
  def get_agent_module(name) when is_atom(name) do
    case :ets.lookup(@ets_table, {:module, name}) do
      [{{:module, ^name}, module}] -> {:ok, module}
      [] -> :error
    end
  end

  @doc """
  Removes the module entry for an agent name.
  """
  @spec delete_agent_module(atom()) :: true
  def delete_agent_module(name) when is_atom(name) do
    :ets.delete(@ets_table, {:module, name})
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp calculate_duration(name) do
    case :ets.lookup(@ets_table, {:start_time, name}) do
      [{{:start_time, ^name}, start_time}] ->
        System.monotonic_time() - start_time

      [] ->
        0
    end
  end

  defp increment_restart_count(name) do
    case :ets.lookup(@ets_table, {:restart_count, name}) do
      [{{:restart_count, ^name}, count}] ->
        new_count = count + 1
        :ets.insert(@ets_table, {{:restart_count, name}, new_count})
        new_count

      [] ->
        :ets.insert(@ets_table, {{:restart_count, name}, 1})
        1
    end
  end

  defp handle_telemetry_event(event, measurements, metadata, config) do
    level = config.level

    case event do
      [:jido_code, :agent, :start] ->
        Logger.log(level, fn ->
          "[Agent] Started #{inspect(metadata.name)} (#{inspect(metadata.module)})"
        end)

      [:jido_code, :agent, :stop] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

        Logger.log(level, fn ->
          "[Agent] Stopped #{inspect(metadata.name)} (#{inspect(metadata.module)}) " <>
            "after #{duration_ms}ms, reason: #{inspect(metadata.reason)}"
        end)

      [:jido_code, :agent, :crash] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

        Logger.log(:warning, fn ->
          "[Agent] Crashed #{inspect(metadata.name)} (#{inspect(metadata.module)}) " <>
            "after #{duration_ms}ms, reason: #{inspect(metadata.reason)}, " <>
            "restart_count: #{metadata.restart_count}"
        end)
    end
  end
end
