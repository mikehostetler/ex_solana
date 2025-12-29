defmodule Jido.Agent.Directive do
  @moduledoc """
  Typed directive structs for `Jido.Agent`.

  A *directive* is a pure description of an external effect for the runtime
  (e.g. `Jido.AgentServer`) to execute. Agents and strategies **never**
  interpret or execute directives; they only emit them.

  ## Signal Integration

  The Emit directive integrates with `Jido.Signal` and `Jido.Signal.Dispatch`:

  - `%Emit{}` - Dispatch a signal via configured adapters (pid, pubsub, bus, http, etc.)

  ## Design

  Directives are bare structs - no tuple wrappers. This enables:
  - Clean pattern matching on struct type
  - Protocol-based dispatch for extensibility
  - External packages can define custom directives

  ## Core Directives

    * `%Emit{}` - Dispatch a signal via `Jido.Signal.Dispatch`
    * `%Error{}` - Signal an error (wraps `Jido.Error.t()`)
    * `%Spawn{}` - Spawn a child process
    * `%Schedule{}` - Schedule a delayed message
    * `%Stop{}` - Stop the agent process

  ## Usage

      alias Jido.Agent.Directive

      # Emit a signal (runtime will dispatch via configured adapters)
      %Directive.Emit{signal: my_signal}
      %Directive.Emit{signal: my_signal, dispatch: {:pubsub, topic: "events"}}
      %Directive.Emit{signal: my_signal, dispatch: {:pid, target: pid}}

      # Schedule for later
      %Directive.Schedule{delay_ms: 5000, message: :timeout}

  ## Extensibility

  External packages can define their own directive structs:

      defmodule MyApp.Directive.CallLLM do
        defstruct [:model, :prompt, :tag]
      end

  The runtime dispatches on struct type, so no changes to core are needed.
  """

  alias __MODULE__.{Emit, Error, Spawn, Schedule, Stop}

  @typedoc """
  Any external directive struct (core or extension).

  This is intentionally `struct()` so external packages can define
  their own directive structs without modifying this type.
  """
  @type t :: struct()

  @typedoc "Built-in core directives."
  @type core ::
          Emit.t()
          | Error.t()
          | Spawn.t()
          | Schedule.t()
          | Stop.t()

  # ============================================================================
  # Error - Signal an error from cmd/2
  # ============================================================================

  defmodule Error do
    @moduledoc """
    Signal an error from agent command processing.

    This directive carries a `Jido.Error.t()` for consistent error handling.
    The runtime can log, emit, or handle errors based on this directive.

    ## Fields

    - `error` - A `Jido.Error.t()` struct
    - `context` - Optional atom describing error context (e.g., `:normalize`, `:instruction`)
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                error: Zoi.any(description: "Jido.Error struct"),
                context: Zoi.atom(description: "Error context") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  # ============================================================================
  # Emit - Signal dispatch via Jido.Signal.Dispatch
  # ============================================================================

  defmodule Emit do
    @moduledoc """
    Dispatch a signal via `Jido.Signal.Dispatch`.

    The runtime interprets this directive by calling:

        Jido.Signal.Dispatch.dispatch(signal, dispatch_config)

    ## Fields

    - `signal` - A `Jido.Signal.t()` struct to dispatch
    - `dispatch` - Dispatch config: `{adapter, opts}` or list of configs
      - `:pid` - Direct to process
      - `:pubsub` - Via PubSub
      - `:bus` - To signal bus
      - `:http` / `:webhook` - HTTP endpoints
      - `:logger` / `:console` / `:noop` - Logging/testing

    ## Examples

        # Use agent's default dispatch (configured on AgentServer)
        %Emit{signal: signal}

        # Explicit dispatch to PubSub
        %Emit{signal: signal, dispatch: {:pubsub, topic: "events"}}

        # Multiple dispatch targets
        %Emit{signal: signal, dispatch: [
          {:pubsub, topic: "events"},
          {:logger, level: :info}
        ]}
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                signal: Zoi.any(description: "Jido.Signal.t() to dispatch"),
                dispatch:
                  Zoi.any(description: "Dispatch config: {adapter, opts} or list")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  # ============================================================================
  # Spawn - Child process spawning
  # ============================================================================

  defmodule Spawn do
    @moduledoc """
    Spawn a child process under the agent's supervisor.

    ## Fields

    - `child_spec` - Supervisor child_spec for the process to spawn
    - `tag` - Optional correlation tag for tracking
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                child_spec: Zoi.any(description: "Supervisor child_spec"),
                tag: Zoi.any(description: "Optional correlation tag") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  # ============================================================================
  # Schedule - Delayed message scheduling
  # ============================================================================

  defmodule Schedule do
    @moduledoc """
    Schedule a delayed message to the agent.

    The runtime will send the message back to the agent after the delay.

    ## Fields

    - `delay_ms` - Delay in milliseconds (must be >= 0)
    - `message` - Message to send after delay
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                delay_ms: Zoi.integer(description: "Delay in milliseconds") |> Zoi.min(0),
                message: Zoi.any(description: "Message to send after delay")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  # ============================================================================
  # Stop - Stop the agent process
  # ============================================================================

  defmodule Stop do
    @moduledoc """
    Request that the agent process stop.

    ## Fields

    - `reason` - Reason for stopping (default: `:normal`)
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                reason: Zoi.any(description: "Reason for stopping") |> Zoi.default(:normal)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  # ============================================================================
  # Helper Constructors
  # ============================================================================

  @doc """
  Creates an Emit directive.

  ## Examples

      Directive.emit(signal)
      Directive.emit(signal, {:pubsub, topic: "events"})
  """
  @spec emit(term(), term()) :: Emit.t()
  def emit(signal, dispatch \\ nil) do
    %Emit{signal: signal, dispatch: dispatch}
  end

  @doc """
  Creates an Error directive.

  ## Examples

      Directive.error(Jido.Error.validation_error("Invalid input"))
      Directive.error(error, :normalize)
  """
  @spec error(term(), atom()) :: Error.t()
  def error(error, context \\ nil) do
    %Error{error: error, context: context}
  end

  @doc """
  Creates a Spawn directive.

  ## Examples

      Directive.spawn({MyWorker, arg: value})
      Directive.spawn(child_spec, :worker_1)
  """
  @spec spawn(term(), term()) :: Spawn.t()
  def spawn(child_spec, tag \\ nil) do
    %Spawn{child_spec: child_spec, tag: tag}
  end

  @doc """
  Creates a Schedule directive.

  ## Examples

      Directive.schedule(5000, :timeout)
      Directive.schedule(1000, {:check, ref})
  """
  @spec schedule(non_neg_integer(), term()) :: Schedule.t()
  def schedule(delay_ms, message) do
    %Schedule{delay_ms: delay_ms, message: message}
  end

  @doc """
  Creates a Stop directive.

  ## Examples

      Directive.stop()
      Directive.stop(:shutdown)
  """
  @spec stop(term()) :: Stop.t()
  def stop(reason \\ :normal) do
    %Stop{reason: reason}
  end
end
