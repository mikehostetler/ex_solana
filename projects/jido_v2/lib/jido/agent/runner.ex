defmodule Jido.Agent.Runner do
  @moduledoc """
  Behaviour for pluggable agent runners (decision engines).

  > **Agents think. Servers act.**

  A runner takes an agent module, its current state, and an incoming signal,
  and returns the next state plus effects. All runners obey the same pure
  contract; they may implement different strategies (state machine, ReAct,
  behavior tree), but they do not perform I/O directly.

  I/O is executed by AgentServer via Effects.

  ## Built-in Runners

  | Runner | Use Case | Status |
  |--------|----------|--------|
  | `:simple` | Direct delegation to handle_signal/2 | Kernel |
  | `:state_machine` | Deterministic workflows with explicit states | Future |
  | `:react` | LLM with tool use (ReAct pattern) | Future |
  | `:behavior_tree` | Complex decision trees | Future |

  ## Implementing a Custom Runner

      defmodule MyApp.CustomRunner do
        @behaviour Jido.Agent.Runner

        @impl true
        def handle(agent_module, state, signal) do
          # Custom decision logic
          agent_module.handle_signal(state, signal)
        end
      end

  ## Configuring Runners

  Runners are configured via `use Jido.Agent`:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          runner: :simple  # or MyApp.CustomRunner
      end
  """

  alias Jido.Agent.Effect

  @typedoc "Result of running an agent via a runner."
  @type result :: {:ok, struct(), [Effect.t()]} | {:error, term()}

  @doc """
  Handle a signal through the runner's decision strategy.

  Takes an agent module, its current state, and a signal. Returns the
  new state and a list of effects describing what should happen next.

  This callback must be pure - it should not perform I/O.

  ## Parameters

  - `agent_module` - The agent module implementing `Jido.Agent`
  - `state` - The current agent state struct
  - `signal` - The incoming signal to process

  ## Returns

  - `{:ok, new_state, effects}` - Success with new state and effects
  - `{:error, reason}` - Failure with error reason
  """
  @callback handle(
              agent_module :: module(),
              state :: struct(),
              signal :: Jido.Signal.t()
            ) :: result

  @doc """
  Normalize a runner configuration to a module.

  Accepts:
  - `:simple` - Returns `Jido.Agent.Runner.Simple`
  - A module atom - Returns the module if it implements the behaviour

  ## Examples

      iex> Jido.Agent.Runner.normalize(:simple)
      {:ok, Jido.Agent.Runner.Simple}

      iex> Jido.Agent.Runner.normalize(MyCustomRunner)
      {:ok, MyCustomRunner}
  """
  @spec normalize(term()) :: {:ok, module()} | {:error, term()}
  def normalize(:simple), do: {:ok, Jido.Agent.Runner.Simple}
  def normalize(nil), do: {:ok, Jido.Agent.Runner.Simple}

  def normalize(mod) when is_atom(mod) do
    cond do
      not Code.ensure_loaded?(mod) ->
        {:error, {:module_not_found, mod}}

      not function_exported?(mod, :handle, 3) ->
        {:error, {:not_a_runner, mod}}

      true ->
        {:ok, mod}
    end
  end

  def normalize(other), do: {:error, {:invalid_runner_config, other}}

  @doc """
  Normalize a runner configuration, raising on error.
  """
  @spec normalize!(term()) :: module()
  def normalize!(config) do
    case normalize(config) do
      {:ok, mod} ->
        mod

      {:error, reason} ->
        raise Jido.Error.Invalid.RunnerConfig.exception(runner: config, reason: reason)
    end
  end
end
