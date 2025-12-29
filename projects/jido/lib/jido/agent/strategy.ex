defmodule Jido.Agent.Strategy do
  @moduledoc """
  Behaviour for agent execution strategies.

  A Strategy decides how to execute actions in `cmd/2`. The default strategy
  (`Direct`) simply executes actions immediately. Advanced strategies can
  implement behavior trees, LLM chains of thought, or other execution patterns.

  ## Core Contract

  Strategies implement three callbacks:

      cmd(agent, action, context) :: {agent, directives}
      init(agent, context) :: {agent, directives}
      tick(agent, context) :: {agent, directives}

  The `cmd/3` callback is required. `init/2` and `tick/2` are optional with
  default no-op implementations provided by `use Jido.Agent.Strategy`.

  ## Lifecycle

  - `init/2` - Called by AgentServer after `MyAgent.new/1` and before the first `cmd/2`.
    Use this to initialize strategy-specific state.
  - `cmd/3` - Called by `MyAgent.cmd/2` to execute actions.
  - `tick/2` - Called by AgentServer when a strategy has scheduled a tick
    (via `{:schedule, ms, :strategy_tick}`). Use for multi-step execution.

  ## Usage

  Set strategy at compile time:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          strategy: Jido.Agent.Strategy.Direct  # default
      end

      # Or with options:
      defmodule MyBTAgent do
        use Jido.Agent,
          name: "bt_agent",
          strategy: {MyBehaviorTreeStrategy, max_depth: 5}
      end

  ## Built-in Strategies

  - `Jido.Agent.Strategy.Direct` - Execute actions immediately (default)

  ## Custom Strategies

  Use the module and implement the required `cmd/3` callback:

      defmodule MyCustomStrategy do
        use Jido.Agent.Strategy

        @impl true
        def cmd(agent, action, ctx) do
          # Custom execution logic
          # Must return {updated_agent, directives}
        end

        # Optionally override init/2 and tick/2
      end

  Strategy state should live inside `agent.state` under the reserved key
  `:__strategy__`. Use `Jido.Agent.Strategy.State` helpers to manage it.
  """

  alias Jido.Agent

  @type context :: %{
          agent_module: module(),
          strategy_opts: keyword()
        }

  @type status :: :idle | :running | :waiting | :success | :failure

  @doc """
  Execute instructions against the agent.

  Called by `MyAgent.cmd/2` after normalization. Receives a list of
  already-normalized `Instruction` structs. Must return the updated agent
  and any external directives.

  ## Parameters

    * `agent` - The current agent struct
    * `instructions` - List of normalized `Instruction` structs
    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

    * `{updated_agent, directives}` - The new agent state and external effects
  """
  @callback cmd(agent :: Agent.t(), instructions :: [Jido.Instruction.t()], ctx :: context()) ::
              {Agent.t(), [Agent.directive()]}

  @doc """
  Initialize strategy-specific state for a freshly created Agent.

  Called by AgentServer after `MyAgent.new/1` and before the first `cmd/2`.
  Default implementation is a no-op.

  ## Parameters

    * `agent` - The newly created agent struct
    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

    * `{updated_agent, directives}` - The agent with initialized strategy state
  """
  @callback init(agent :: Agent.t(), ctx :: context()) ::
              {Agent.t(), [Agent.directive()]}

  @doc """
  Tick-based continuation for multi-step or long-running strategies.

  Called by AgentServer when a strategy has indicated it wants to be ticked
  (via a schedule directive like `{:schedule, ms, :strategy_tick}`).
  Default implementation is a no-op.

  ## Parameters

    * `agent` - The current agent struct
    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

    * `{updated_agent, directives}` - The new agent state and external effects
  """
  @callback tick(agent :: Agent.t(), ctx :: context()) ::
              {Agent.t(), [Agent.directive()]}

  @optional_callbacks init: 2, tick: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Agent.Strategy

      @impl true
      def init(agent, _ctx), do: {agent, []}

      @impl true
      def tick(agent, _ctx), do: {agent, []}

      defoverridable init: 2, tick: 2
    end
  end
end
