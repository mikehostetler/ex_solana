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

      # Create a new agent (fully initialized including strategy state)
      agent = MyAgent.new()
      agent = MyAgent.new(id: "custom-id", state: %{counter: 10})

      # Execute actions
      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

      # Update state directly
      {:ok, agent} = MyAgent.set(agent, %{status: :running})

  ## Strategy Initialization

  `new/1` automatically calls `strategy.init/2` to initialize strategy-specific
  state. Any directives returned by strategy init are dropped here since they
  require a runtime to execute. When using `AgentServer`, it handles strategy
  init directives separately during startup.

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
                             |> Zoi.default(Jido.Agent.Strategy.Direct),
                           skills:
                             Zoi.list(Zoi.any(),
                               description: "Skill modules or {module, config} tuples"
                             )
                             |> Zoi.default([])
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

  @doc """
  Handles an incoming signal and returns updated agent with directives.

  The default implementation translates the signal to an action via
  `signal_to_action/1` and delegates to `cmd/2`. Override this callback
  for custom signal handling logic.

  ## Examples

      # Default behavior: translates signal.type to action tuple
      def handle_signal(agent, %Signal{type: "user.created", data: data}) do
        # Default: calls cmd(agent, {"user.created", data})
        ...
      end

      # Custom override for specific signal handling
      def handle_signal(agent, %Signal{type: "increment"} = _signal) do
        count = agent.state.counter + 1
        {%{agent | state: %{agent.state | counter: count}}, []}
      end
  """
  @callback handle_signal(agent :: t(), signal :: Jido.Signal.t()) ::
              {t(), [directive()]}

  @doc """
  Translates a signal to an action for `cmd/2`.

  The default implementation returns `{signal.type, signal.data}`.
  Override to customize how signals map to actions.

  ## Examples

      # Default behavior
      def signal_to_action(%Signal{type: type, data: data}) do
        {type, data}
      end

      # Custom mapping
      def signal_to_action(%Signal{type: "user." <> action, data: data}) do
        {String.to_existing_atom(action), data}
      end
  """
  @callback signal_to_action(signal :: Jido.Signal.t()) :: action()

  @optional_callbacks [on_after_cmd: 3, handle_signal: 2, signal_to_action: 1]

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

      # Normalize skills: Module or {Module, config}
      @skills_config Enum.map(@validated_opts[:skills] || [], fn
                       mod when is_atom(mod) -> {mod, %{}}
                       {mod, opts} when is_list(opts) -> {mod, Map.new(opts)}
                       {mod, opts} when is_map(opts) -> {mod, opts}
                     end)

      # Validate skills implement behaviour
      for {mod, _} <- @skills_config do
        case Code.ensure_compiled(mod) do
          {:module, _} ->
            unless function_exported?(mod, :skill_spec, 1) do
              raise CompileError,
                description:
                  "#{inspect(mod)} does not implement Jido.Skill (missing skill_spec/1)",
                file: __ENV__.file,
                line: __ENV__.line
            end

          {:error, reason} ->
            raise CompileError,
              description: "Skill #{inspect(mod)} could not be compiled: #{inspect(reason)}",
              file: __ENV__.file,
              line: __ENV__.line
        end
      end

      # Build skill specs at compile time
      @skill_specs Enum.map(@skills_config, fn {mod, config} ->
                     mod.skill_spec(config)
                   end)

      # Validate unique state_keys
      @skill_state_keys Enum.map(@skill_specs, & &1.state_key)
      @duplicate_keys @skill_state_keys -- Enum.uniq(@skill_state_keys)
      if @duplicate_keys != [] do
        raise CompileError,
          description: "Duplicate skill state_keys: #{inspect(@duplicate_keys)}",
          file: __ENV__.file,
          line: __ENV__.line
      end

      # Validate no collision with base schema keys
      @base_schema_keys Jido.Agent.Schema.known_keys(@validated_opts[:schema])
      @colliding_keys Enum.filter(@skill_state_keys, &(&1 in @base_schema_keys))
      if @colliding_keys != [] do
        raise CompileError,
          description: "Skill state_keys collide with agent schema: #{inspect(@colliding_keys)}",
          file: __ENV__.file,
          line: __ENV__.line
      end

      # Merge schemas: base schema + nested skill schemas
      @merged_schema Jido.Agent.Schema.merge_with_skills(
                       @validated_opts[:schema],
                       @skill_specs
                     )

      # Aggregate actions from skills
      @skill_actions @skill_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq()

      # Metadata accessors
      def name, do: @validated_opts.name
      def description, do: @validated_opts[:description]
      def category, do: @validated_opts[:category]
      def tags, do: @validated_opts[:tags] || []
      def vsn, do: @validated_opts[:vsn]
      def schema, do: @merged_schema

      # Skill introspection functions
      def skills, do: @skill_specs
      def skill_specs, do: @skill_specs
      def actions, do: @skill_actions

      def skill_config(skill_mod) do
        case Enum.find(@skill_specs, &(&1.module == skill_mod)) do
          nil -> nil
          spec -> spec.config
        end
      end

      def skill_state(agent, skill_mod) do
        case Enum.find(@skill_specs, &(&1.module == skill_mod)) do
          nil -> nil
          spec -> Map.get(agent.state, spec.state_key)
        end
      end

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

      The agent is fully initialized including strategy state. For the default
      Direct strategy, this is a no-op. For custom strategies, any state
      initialization is applied (but directives are only processed by AgentServer).

      ## Examples

          agent = #{inspect(__MODULE__)}.new()
          agent = #{inspect(__MODULE__)}.new(id: "custom-id")
          agent = #{inspect(__MODULE__)}.new(state: %{counter: 10})
      """
      @spec new(keyword() | map()) :: Agent.t()
      def new(opts \\ []) do
        opts = if is_list(opts), do: Map.new(opts), else: opts

        # Build initial state from base schema defaults
        base_defaults = Jido.Agent.State.defaults_from_schema(@validated_opts[:schema])

        # Build skill defaults nested under their state_keys
        skill_defaults =
          @skill_specs
          |> Enum.map(fn spec ->
            skill_state_defaults = Jido.Agent.Schema.defaults_from_zoi_schema(spec.schema)
            {spec.state_key, skill_state_defaults}
          end)
          |> Map.new()

        # Merge: base defaults + skill defaults + provided state
        schema_defaults = Map.merge(base_defaults, skill_defaults)
        initial_state = Map.merge(schema_defaults, opts[:state] || %{})

        id = opts[:id] || Jido.Util.generate_id()

        agent = %Agent{
          id: id,
          name: name(),
          description: description(),
          category: category(),
          tags: tags(),
          vsn: vsn(),
          schema: schema(),
          state: initial_state
        }

        # Run strategy initialization (directives are dropped here;
        # AgentServer handles init directives separately)
        ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
        {initialized_agent, _directives} = strategy().init(agent, ctx)
        initialized_agent
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
            strat = strategy()

            normalized_instructions =
              Enum.map(instructions, fn instr ->
                Jido.Agent.Strategy.normalize_instruction(strat, instr, ctx)
              end)

            {agent, directives} = strat.cmd(agent, normalized_instructions, ctx)
            do_after_cmd(agent, action, directives)

          {:error, reason} ->
            error = Jido.Error.validation_error("Invalid action", %{reason: reason})
            {agent, [%Directive.Error{error: error, context: :normalize}]}
        end
      end

      @doc """
      Returns a stable, public view of the strategy's execution state.

      Use this instead of inspecting `agent.state.__strategy__` directly.
      Returns a `Jido.Agent.Strategy.Public` struct with:
      - `status` - Coarse execution status
      - `done?` - Whether strategy reached terminal state
      - `result` - Main output if any
      - `meta` - Additional strategy-specific metadata
      """
      @spec strategy_snapshot(Agent.t()) :: Jido.Agent.Strategy.Public.t()
      def strategy_snapshot(%Agent{} = agent) do
        ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
        strategy().snapshot(agent, ctx)
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

      # Default callback implementations

      def on_after_cmd(agent, _action, directives), do: {:ok, agent, directives}

      @doc """
      Default signal handler with automatic strategy routing.

      If the strategy implements `signal_routes/1`, this handler automatically
      routes matching signals to strategy commands. For unmatched signals,
      falls back to `signal_to_action/1` translation.

      Override this function to customize signal handling for your agent.
      """
      @spec handle_signal(Agent.t(), Jido.Signal.t()) :: Agent.cmd_result()
      def handle_signal(%Agent{} = agent, %Jido.Signal{} = signal) do
        strat = strategy()
        ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}

        case route_signal_to_strategy(strat, signal, ctx) do
          {:routed, action} ->
            cmd(agent, action)

          :no_route ->
            action = signal_to_action(signal)
            cmd(agent, action)
        end
      end

      defp route_signal_to_strategy(strat, signal, ctx) do
        if function_exported?(strat, :signal_routes, 1) do
          routes = strat.signal_routes(ctx)

          case find_matching_route(routes, signal) do
            nil -> :no_route
            {:strategy_cmd, action} -> {:routed, {action, signal.data}}
            {:strategy_tick} -> {:routed, {:strategy_tick, %{}}}
            {:custom, _term} -> :no_route
          end
        else
          :no_route
        end
      end

      defp find_matching_route(routes, signal) do
        Enum.find_value(routes, fn
          {type, target} when is_binary(type) ->
            if signal.type == type, do: target, else: nil

          {type, target, _priority} when is_binary(type) ->
            if signal.type == type, do: target, else: nil

          {type, match_fn, target} when is_binary(type) and is_function(match_fn, 1) ->
            if signal.type == type and match_fn.(signal), do: target, else: nil

          {type, match_fn, target, _priority} when is_binary(type) and is_function(match_fn, 1) ->
            if signal.type == type and match_fn.(signal), do: target, else: nil

          _ ->
            nil
        end)
      end

      @doc """
      Default signal-to-action translation.

      Returns `{signal.type, signal.data}` as an action tuple.
      Override to customize how signals map to actions.
      """
      @spec signal_to_action(Jido.Signal.t()) :: Agent.action()
      def signal_to_action(%Jido.Signal{type: type, data: data}) do
        {type, data}
      end

      defoverridable on_after_cmd: 3,
                     handle_signal: 2,
                     signal_to_action: 1,
                     name: 0,
                     description: 0,
                     category: 0,
                     tags: 0,
                     vsn: 0,
                     schema: 0,
                     strategy: 0,
                     strategy_opts: 0,
                     skills: 0,
                     skill_specs: 0,
                     actions: 0,
                     skill_config: 1,
                     skill_state: 2

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
