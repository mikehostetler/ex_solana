defmodule Jido.AgentServer.Status do
  @moduledoc """
  Runtime status for an agent process.

  Combines `Strategy.Snapshot` with process-level metadata to provide a clean,
  stable API for querying agent status without depending on internal `__strategy__`
  implementation details.

  ## Fields

  - `agent_module` - The agent's module (e.g., `MyAgent`)
  - `agent_id` - The agent's unique ID
  - `pid` - The GenServer process PID
  - `snapshot` - The `Strategy.Snapshot` containing core status info
  - `raw_state` - Escape hatch containing full agent state (use sparingly)

  ## Usage

      {:ok, agent_status} = AgentServer.status(pid)

      # Check if completed
      if agent_status.snapshot.done? do
        IO.puts("Result: " <> inspect(agent_status.snapshot.result))
      end

      # Access snapshot fields via helpers
      case Status.status(agent_status) do
        :success -> handle_success(agent_status)
        :failure -> handle_failure(agent_status)
        :running -> poll_again()
      end

  ## Delegate Helpers

  The module provides convenience delegates to common snapshot fields:
  - `status/1` - Returns the snapshot's status
  - `done?/1` - Returns the snapshot's done? flag
  - `result/1` - Returns the snapshot's result
  - `details/1` - Returns the snapshot's details map
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent_module: Zoi.atom(description: "The agent's module"),
              agent_id: Zoi.string(description: "The agent's unique ID"),
              pid: Zoi.any(description: "The GenServer process PID"),
              snapshot: Zoi.any(description: "The Strategy.Snapshot containing core status"),
              raw_state: Zoi.map(description: "Escape hatch containing full agent state")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc """
  Creates a new Status from a map of attributes.

  Returns `{:ok, status}` or `{:error, reason}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  def new(_), do: {:error, Jido.Error.validation_error("Status requires a map")}

  @doc "Returns the status from the snapshot (:idle, :running, :waiting, :success, :failure)."
  @spec status(t()) :: Jido.Agent.Strategy.status()
  def status(%__MODULE__{snapshot: s}), do: s.status

  @doc "Returns whether the agent has reached a terminal state."
  @spec done?(t()) :: boolean()
  def done?(%__MODULE__{snapshot: s}), do: s.done?

  @doc "Returns the result from the snapshot (if any)."
  @spec result(t()) :: term() | nil
  def result(%__MODULE__{snapshot: s}), do: s.result

  @doc "Returns strategy-specific details from the snapshot."
  @spec details(t()) :: map()
  def details(%__MODULE__{snapshot: s}), do: s.details
end
