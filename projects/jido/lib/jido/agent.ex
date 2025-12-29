defmodule Jido.Agent do
  @moduledoc """
  An Agent is an immutable data structure that holds state and can be updated
  via commands. This module provides a minimal, purely functional API:

  - `new/1` - Create a new agent
  - `set/2` - Update state directly
  - `validate/2` - Validate agent state against schema
  - `cmd/2` - Execute actions: `(agent, action) -> {agent, directives}`

  ## Core Pattern

  The fundamental operation is `cmd/2`:

      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

  Key invariants:
  - The returned `agent` is **always complete** — no "apply directives" step needed
  - `directives` are **external effects only** — they never modify agent state
  - `cmd/2` is a **pure function** — given same inputs, always same outputs

  ## Action Formats

  `cmd/2` accepts actions in these forms:

  - `MyAction` - Action module with no params
  - `{MyAction, %{param: value}}` - Action with params
  - `%Instruction{}` - Full instruction struct
  - `[...]` - List of any of the above (processed in sequence)

  ## Directives

  Directives are effect descriptions for the runtime to interpret. They are
  **strictly outbound** - the agent never receives directives as input.

  Directives are bare structs (no tuple wrappers). Built-in directives
  (see `Jido.Agent.Directive`):

  - `%Directive.Emit{}` - Dispatch a signal via `Jido.Signal.Dispatch`
  - `%Directive.Error{}` - Signal an error (wraps `Jido.Error.t()`)
  - `%Directive.Spawn{}` - Spawn a child process
  - `%Directive.Schedule{}` - Schedule a delayed message
  - `%Directive.Stop{}` - Stop the agent process

  The Emit directive integrates with `Jido.Signal` for dispatch:

      # Emit with default dispatch config
      %Directive.Emit{signal: my_signal}

      # Emit to PubSub topic
      %Directive.Emit{signal: my_signal, dispatch: {:pubsub, topic: "events"}}

      # Emit to a specific process
      %Directive.Emit{signal: my_signal, dispatch: {:pid, target: pid}}

  External packages can define custom directive structs without modifying core.

  Directives never modify agent state — that's handled by the returned agent.

  ## Usage

  ### Defining an Agent Module

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "My custom agent",
          schema: [
            status: [type: :atom, default: :idle],
            counter: [type: :integer, default: 0]
          ]
      end

  ### Working with Agents

      # Create a new agent
      agent = MyAgent.new()
      agent = MyAgent.new(id: "custom-id", state: %{counter: 10})

      # Execute actions
      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

      # Update state directly
      {:ok, agent} = MyAgent.set(agent, %{status: :running})

  ## Lifecycle Hook

  Agents support one optional callback:

  - `on_after_cmd/3` - Called after command processing (pure transformations only)

  ## State Schema Types

  Agent supports two schema formats for state validation:

  1. **NimbleOptions schemas** (familiar, legacy):
     ```elixir
     schema: [
       status: [type: :atom, default: :idle],
       counter: [type: :integer, default: 0]
     ]
     ```

  2. **Zoi schemas** (recommended for new code):
     ```elixir
     schema: Zoi.object(%{
       status: Zoi.atom() |> Zoi.default(:idle),
       counter: Zoi.integer() |> Zoi.default(0)
     })
     ```

  Both are handled transparently by `Jido.Agent.State` via `Jido.Action.Schema`.

  ## Pure Functional Design

  The Agent struct is immutable. All operations return new agent structs.
  Server/OTP integration is handled separately by `Jido.AgentServer`.
  """

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.State, as: StateHelper
  alias Jido.Action.Schema
  alias Jido.Error
  alias Jido.Instruction

  require OK

  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique agent identifier")
                |> Zoi.optional(),
              name:
                Zoi.string(description: "Agent name")
                |> Zoi.optional(),
              description:
                Zoi.string(description: "Agent description")
                |> Zoi.optional(),
              category:
                Zoi.string(description: "Agent category")
                |> Zoi.optional(),
              tags:
                Zoi.list(Zoi.string(), description: "Tags")
                |> Zoi.default([]),
              vsn:
                Zoi.string(description: "Version")
                |> Zoi.optional(),
              schema:
                Zoi.any(
                  description: "NimbleOptions or Zoi schema for validating the Agent's state"
                )
                |> Zoi.default([]),
              state:
                Zoi.map(description: "Current state")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Agent."
  def schema, do: @schema

  # Action input types
  @type action :: module() | {module(), map()} | Instruction.t() | [action()]

  # Directive types (external effects only - never modify agent state)
  # See Jido.Agent.Directive for structured payload modules
  @type directive :: Directive.t()

  @type agent_result :: {:ok, t()} | {:error, Error.t()}
  @type cmd_result :: {t(), [directive()]}

  @agent_config_schema Zoi.object(
                         %{
                           name:
                             Zoi.string(
                               description:
                                 "The name of the Agent. Must contain only letters, numbers, and underscores."
                             )
                             |> Zoi.refine({Jido.Util, :validate_name, []}),
                           description:
                             Zoi.string(description: "A description of what the Agent does.")
                             |> Zoi.optional(),
                           category:
                             Zoi.string(description: "The category of the Agent.")
                             |> Zoi.optional(),
                           tags:
                             Zoi.list(Zoi.string(), description: "Tags")
                             |> Zoi.default([]),
                           vsn:
                             Zoi.string(description: "Version")
                             |> Zoi.optional(),
                           schema:
                             Zoi.any(
                               description:
                                 "NimbleOptions or Zoi schema for validating the Agent's state."
                             )
                             |> Zoi.refine({Schema, :validate_config_schema, []})
                             |> Zoi.default([]),
                           strategy:
                             Zoi.any(
                               description:
                                 "Execution strategy module or {module, opts}. Default: Jido.Agent.Strategy.Direct"
                             )
                             |> Zoi.default(Jido.Agent.Strategy.Direct)
                         },
                         coerce: true
                       )

  @doc false
  def config_schema, do: @agent_config_schema

  # Callbacks

  @doc """
  Called after command processing. Can transform the agent or directives.
  Must be pure - no side effects. Return `{:ok, agent, directives}` to continue.

  Use cases:
  - Auto-validate state after changes
  - Derive computed fields
  - Add invariant checks
  """
  @callback on_after_cmd(agent :: t(), action :: term(), directives :: [directive()]) ::
              {:ok, t(), [directive()]}

  @optional_callbacks [on_after_cmd: 3]

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Agent

      alias Jido.Agent
      alias Jido.Instruction

      require OK

      # Validate config at compile time
      @validated_opts (case Zoi.parse(Agent.config_schema(), Map.new(unquote(opts))) do
                         {:ok, validated} ->
                           validated

                         {:error, errors} ->
                           message =
                             "Invalid Agent configuration for #{inspect(__MODULE__)}: #{inspect(errors)}"

                           raise CompileError,
                             description: message,
                             file: __ENV__.file,
                             line: __ENV__.line
                       end)

      # Metadata accessors
      def name, do: @validated_opts.name
      def description, do: @validated_opts[:description]
      def category, do: @validated_opts[:category]
      def tags, do: @validated_opts[:tags] || []
      def vsn, do: @validated_opts[:vsn]
      def schema, do: @validated_opts[:schema] || []

      # Strategy accessors
      def strategy do
        case @validated_opts[:strategy] do
          {mod, _opts} -> mod
          mod -> mod
        end
      end

      def strategy_opts do
        case @validated_opts[:strategy] do
          {_mod, opts} -> opts
          _ -> []
        end
      end

      @doc """
      Creates a new agent with optional initial state.

      ## Examples

          agent = #{inspect(__MODULE__)}.new()
          agent = #{inspect(__MODULE__)}.new(id: "custom-id")
          agent = #{inspect(__MODULE__)}.new(state: %{counter: 10})
      """
      @spec new(keyword() | map()) :: Agent.t()
      def new(opts \\ []) do
        opts = if is_list(opts), do: Map.new(opts), else: opts

        # Build initial state from schema defaults + provided state
        schema_defaults = Jido.Agent.State.defaults_from_schema(schema())
        initial_state = Map.merge(schema_defaults, opts[:state] || %{})

        id = opts[:id] || Jido.Util.generate_id()

        %Agent{
          id: id,
          name: name(),
          description: description(),
          category: category(),
          tags: tags(),
          vsn: vsn(),
          schema: schema(),
          state: initial_state
        }
      end

      @doc """
      Execute actions against the agent. Pure: `(agent, action) -> {agent, directives}`

      This is the core operation. Actions modify state, directives are external effects.
      Execution is delegated to the configured strategy (default: Direct).

      ## Action Formats

        * `MyAction` - Action module with no params
        * `{MyAction, %{param: 1}}` - Action with params
        * `%Instruction{}` - Full instruction struct
        * `[...]` - List of any of the above (processed in sequence)

      ## Examples

          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, MyAction)
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, {MyAction, %{value: 42}})
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, [Action1, Action2])
      """
      @spec cmd(Agent.t(), Agent.action()) :: Agent.cmd_result()
      def cmd(%Agent{} = agent, action) do
        case Instruction.normalize(action, %{state: agent.state}, []) do
          {:ok, instructions} ->
            ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
            {agent, directives} = strategy().cmd(agent, instructions, ctx)
            do_after_cmd(agent, action, directives)

          {:error, reason} ->
            error = Jido.Error.validation_error("Invalid action", %{reason: reason})
            {agent, [%Directive.Error{error: error, context: :normalize}]}
        end
      end

      @doc """
      Updates the agent's state by merging new attributes.

      Uses deep merge semantics - nested maps are merged recursively.

      ## Examples

          {:ok, agent} = #{inspect(__MODULE__)}.set(agent, %{status: :running})
          {:ok, agent} = #{inspect(__MODULE__)}.set(agent, counter: 5)
      """
      @spec set(Agent.t(), map() | keyword()) :: Agent.agent_result()
      def set(%Agent{} = agent, attrs) do
        new_state = Jido.Agent.State.merge(agent.state, Map.new(attrs))
        OK.success(%{agent | state: new_state})
      end

      @doc """
      Validates the agent's state against its schema.

      ## Options
        * `:strict` - When true, only schema-defined fields are kept (default: false)

      ## Examples

          {:ok, agent} = #{inspect(__MODULE__)}.validate(agent)
          {:ok, agent} = #{inspect(__MODULE__)}.validate(agent, strict: true)
      """
      @spec validate(Agent.t(), keyword()) :: Agent.agent_result()
      def validate(%Agent{} = agent, opts \\ []) do
        case Jido.Agent.State.validate(agent.state, agent.schema, opts) do
          {:ok, validated_state} ->
            OK.success(%{agent | state: validated_state})

          {:error, reason} ->
            Jido.Error.validation_error("State validation failed", %{reason: reason})
            |> OK.failure()
        end
      end

      # Default callback implementation
      def on_after_cmd(agent, _action, directives), do: {:ok, agent, directives}

      defoverridable on_after_cmd: 3,
                     name: 0,
                     description: 0,
                     category: 0,
                     tags: 0,
                     vsn: 0,
                     schema: 0,
                     strategy: 0,
                     strategy_opts: 0

      # Private helper for after hook dispatch
      defp do_after_cmd(agent, msg, directives) do
        {:ok, agent, directives} = on_after_cmd(agent, msg, directives)
        {agent, directives}
      end
    end
  end

  # Base module functions (for direct use without `use`)

  @doc """
  Creates a new agent from attributes.

  For module-based agents, use `MyAgent.new/1` instead.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    attrs_with_id = Map.put_new_lazy(attrs, :id, &Jido.Util.generate_id/0)

    case Zoi.parse(@schema, attrs_with_id) do
      {:ok, agent} ->
        {:ok, agent}

      {:error, errors} ->
        {:error, Error.validation_error("Agent validation failed", %{errors: errors})}
    end
  end

  @doc """
  Updates agent state by merging new attributes.
  """
  @spec set(t(), map() | keyword()) :: agent_result()
  def set(%Agent{} = agent, attrs) do
    new_state = StateHelper.merge(agent.state, Map.new(attrs))
    OK.success(%{agent | state: new_state})
  end

  @doc """
  Validates agent state against its schema.
  """
  @spec validate(t(), keyword()) :: agent_result()
  def validate(%Agent{} = agent, opts \\ []) do
    case StateHelper.validate(agent.state, agent.schema, opts) do
      {:ok, validated_state} ->
        OK.success(%{agent | state: validated_state})

      {:error, reason} ->
        Error.validation_error("State validation failed", %{reason: reason})
        |> OK.failure()
    end
  end
end
