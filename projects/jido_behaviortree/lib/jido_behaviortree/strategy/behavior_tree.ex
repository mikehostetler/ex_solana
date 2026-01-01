defmodule Jido.Agent.Strategy.BehaviorTree do
  @moduledoc """
  Behavior tree execution strategy for Jido agents.

  This strategy allows agents to use behavior trees for decision-making.
  Each `cmd/3` call executes exactly one behavior tree tick, making execution
  bounded and predictable.

  ## Configuration

  Configure via strategy options when defining an agent:

      defmodule MyAgent do
        use Jido.Agent,
          name: "bt_agent",
          strategy: {Jido.Agent.Strategy.BehaviorTree,
            tree: my_tree(),
            blackboard: %{initial: "data"}
          }
      end

  ## Options

  - `:tree` - A `Jido.BehaviorTree.Tree.t()` (required unless `:tree_builder` provided)
  - `:tree_builder` - `{mod, fun, args}` to build tree dynamically per agent
  - `:blackboard` - Initial blackboard data map (default: `%{}`)
  - `:reset_on_completion` - Reset tree when status is `:success` or `:failure` (default: `false`)

  ## Execution Model

  1. `init/2` - Creates tree and blackboard from options, stores in `__strategy__`
  2. `cmd/3` - Injects instructions into blackboard, runs one tree tick, returns directives
  3. `snapshot/2` - Maps tree status to `Strategy.Snapshot`

  ## Status Mapping

  - Tree `:success` → Snapshot `:success`
  - Tree `:failure` → Snapshot `:failure`
  - Tree `:running` → Snapshot `:running`
  - Before first tick → Snapshot `:idle`
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.BehaviorTree.{Blackboard, Tick, Tree}
  alias Jido.Error
  alias Jido.Telemetry, as: JidoTelemetry

  defmodule State do
    @moduledoc """
    Internal state for the BehaviorTree strategy.

    Stored in `agent.state.__strategy__.bt`.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                tree: Zoi.any(description: "The behavior tree"),
                blackboard: Zoi.any(description: "Shared blackboard state"),
                status:
                  Zoi.atom(description: "Current execution status")
                  |> Zoi.default(:idle),
                tick_count:
                  Zoi.integer(description: "Number of ticks executed")
                  |> Zoi.min(0)
                  |> Zoi.default(0),
                last_result: Zoi.any(description: "Result from last tick") |> Zoi.optional(),
                error: Zoi.any(description: "Last error if any") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for this module"
    def schema, do: @schema

    @doc "Creates a new State with the given tree and blackboard"
    @spec new(Tree.t(), Blackboard.t()) :: t()
    def new(tree, blackboard) do
      %__MODULE__{
        tree: tree,
        blackboard: blackboard,
        status: :idle,
        tick_count: 0,
        last_result: nil,
        error: nil
      }
    end
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    JidoTelemetry.span_strategy(agent, :init, __MODULE__, fn ->
      opts = ctx[:strategy_opts] || []

      tree = resolve_tree(opts, agent)
      blackboard = Blackboard.new(Keyword.get(opts, :blackboard, %{}))
      bt_state = State.new(tree, blackboard)

      agent =
        StratState.put(agent, %{
          bt: bt_state,
          module: __MODULE__,
          reset_on_completion: Keyword.get(opts, :reset_on_completion, false)
        })

      {agent, []}
    end)
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) when is_list(instructions) do
    JidoTelemetry.span_strategy(agent, :cmd, __MODULE__, fn ->
      strat_state = StratState.get(agent, %{})
      %State{} = bt = Map.fetch!(strat_state, :bt)
      reset_on_completion? = Map.get(strat_state, :reset_on_completion, false)

      blackboard =
        bt.blackboard
        |> Blackboard.put(:instructions, instructions)
        |> Blackboard.put(:agent_state, agent.state)

      tick_context =
        Map.merge(ctx, %{
          agent_id: agent.id,
          agent_module: agent.name,
          strategy: __MODULE__
        })

      tick =
        Tick.new_with_context(
          blackboard,
          agent,
          [],
          tick_context
        )

      {status, tree, tick} = Tree.tick_with_context(bt.tree, tick)

      updated_agent = tick.agent
      directives = tick.directives
      last_result = Blackboard.get(tick.blackboard, :last_result)
      error = Blackboard.get(tick.blackboard, :error)

      tree =
        if reset_on_completion? and status in [:success, :failure] do
          Tree.halt(tree)
        else
          tree
        end

      bt = %State{
        bt
        | tree: tree,
          blackboard: tick.blackboard,
          status: status,
          tick_count: bt.tick_count + 1,
          last_result: last_result,
          error: error
      }

      updated_agent = StratState.put(updated_agent, %{strat_state | bt: bt})
      {updated_agent, directives}
    end)
  rescue
    e ->
      error = Error.execution_error("BehaviorTree tick failed", %{reason: Exception.message(e)})
      {agent, [%Directive.Error{error: error, context: :bt_tick}]}
  end

  @impl true
  def snapshot(agent, _ctx) do
    strat_state = StratState.get(agent, %{})
    bt = Map.get(strat_state, :bt)

    case bt do
      %State{} = state ->
        status = state.status || :idle

        %Jido.Agent.Strategy.Snapshot{
          status: status,
          done?: status in [:success, :failure],
          result: state.last_result,
          details: %{
            tick_count: state.tick_count || 0,
            error: state.error,
            tree_depth: safe_tree_depth(state.tree)
          }
        }

      _ ->
        %Jido.Agent.Strategy.Snapshot{
          status: :idle,
          done?: false,
          result: nil,
          details: %{tick_count: 0, error: nil, tree_depth: 0}
        }
    end
  end

  defp resolve_tree(opts, agent) do
    case Keyword.get(opts, :tree) do
      %Tree{} = t ->
        t

      nil ->
        case Keyword.get(opts, :tree_builder) do
          {mod, fun, extra_args} ->
            apply(mod, fun, [agent | List.wrap(extra_args)])

          nil ->
            raise ArgumentError, "BehaviorTree strategy requires :tree or :tree_builder option"
        end

      other ->
        raise ArgumentError,
              "BehaviorTree strategy :tree must be a Tree struct, got: #{inspect(other)}"
    end
  end

  defp safe_tree_depth(nil), do: 0

  defp safe_tree_depth(%Tree{} = tree) do
    Tree.depth(tree)
  rescue
    _ -> 0
  end

  defp safe_tree_depth(_), do: 0
end
