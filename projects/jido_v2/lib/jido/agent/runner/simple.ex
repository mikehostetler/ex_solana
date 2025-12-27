defmodule Jido.Agent.Runner.Simple do
  @moduledoc """
  Simple runner that delegates directly to `agent_module.handle_signal/2`.

  This is the default runner for Jido agents. It provides:

  - Direct delegation to the agent's `handle_signal/2` callback
  - Exception wrapping in Splode errors
  - Contract validation (ensures proper return format)

  ## Usage

  This runner is used by default when no runner is specified:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent"
          # runner: :simple is implicit
      end

  Or explicitly:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          runner: :simple
      end

  ## When to Use

  Use the Simple runner when:

  - Your agent has straightforward `handle_signal/2` logic
  - You're writing tests and want minimal overhead
  - You don't need state machine, ReAct, or other advanced patterns
  """

  @behaviour Jido.Agent.Runner

  alias Jido.Agent.Effect

  @impl true
  @spec handle(module(), struct(), Jido.Signal.t()) ::
          {:ok, struct(), [Effect.t()]} | {:error, term()}
  def handle(agent_module, state, signal) do
    do_handle(agent_module, state, signal)
  rescue
    exception ->
      {:error,
       Jido.Error.Agent.RunnerCallbackError.exception(
         agent: agent_module,
         runner: __MODULE__,
         reason: exception
       )}
  end

  defp do_handle(agent_module, state, signal) do
    case agent_module.handle_signal(state, signal) do
      {:ok, new_state, effects} when is_struct(new_state) and is_list(effects) ->
        {:ok, new_state, effects}

      {:error, _} = error ->
        error

      other ->
        {:error,
         Jido.Error.Framework.UnexpectedRunnerResult.exception(
           runner: __MODULE__,
           agent: agent_module,
           result: other
         )}
    end
  end
end
