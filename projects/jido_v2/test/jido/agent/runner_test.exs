defmodule JidoTest.Agent.RunnerTest do
  @moduledoc """
  Tests for Jido.Agent.Runner behaviour and Jido.Agent.Runner.Simple.
  """
  use ExUnit.Case, async: true

  alias Jido.Agent.Runner
  alias Jido.Agent.Runner.Simple
  alias Jido.Agent.Effect
  alias Jido.Signal

  # ---------------------------------------------------------------------------
  # Test Agents
  # ---------------------------------------------------------------------------

  defmodule CounterAgent do
    @moduledoc "Simple counter agent for testing runners."
    use Jido.Agent,
      name: "counter",
      schema: %{
        count: Zoi.integer() |> Zoi.default(0)
      }

    @impl true
    def handle_signal(state, %Signal{type: "increment"}) do
      {:ok, %{state | count: state.count + 1}, []}
    end

    def handle_signal(state, %Signal{type: "increment_by", data: %{"amount" => amount}}) do
      {:ok, %{state | count: state.count + amount}, []}
    end

    def handle_signal(state, %Signal{type: "get_count"}) do
      effects = [
        %Effect.Reply{
          signal: Signal.new!("count_response", %{count: state.count}, source: "/test")
        }
      ]

      {:ok, state, effects}
    end

    def handle_signal(state, _signal), do: {:ok, state, []}
  end

  defmodule ErrorAgent do
    @moduledoc "Agent that returns errors for testing."
    use Jido.Agent,
      name: "error_agent",
      schema: %{}

    @impl true
    def handle_signal(_state, %Signal{type: "raise_error"}) do
      raise "Intentional error for testing"
    end

    def handle_signal(_state, %Signal{type: "return_error"}) do
      {:error, :intentional_error}
    end

    def handle_signal(_state, %Signal{type: "bad_return"}) do
      :not_a_valid_return
    end

    def handle_signal(state, _signal), do: {:ok, state, []}
  end

  defmodule CustomRunnerAgent do
    @moduledoc "Agent with a custom runner configuration."
    use Jido.Agent,
      name: "custom_runner",
      runner: JidoTest.Agent.RunnerTest.CustomRunner,
      schema: %{
        value: Zoi.string() |> Zoi.default("default")
      }

    @impl true
    def handle_signal(state, _signal), do: {:ok, state, []}
  end

  defmodule CustomRunner do
    @moduledoc "Custom runner for testing."
    @behaviour Jido.Agent.Runner

    @impl true
    def handle(agent_module, state, signal) do
      case agent_module.handle_signal(state, signal) do
        {:ok, new_state, effects} ->
          custom_effect = %Effect.Reply{
            signal: Signal.new!("custom_runner_processed", %{}, source: "/custom")
          }

          {:ok, new_state, [custom_effect | effects]}

        error ->
          error
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Runner.normalize/1
  # ---------------------------------------------------------------------------

  describe "Runner.normalize/1" do
    test "normalizes :simple to Simple runner" do
      assert {:ok, Simple} = Runner.normalize(:simple)
    end

    test "normalizes nil to Simple runner" do
      assert {:ok, Simple} = Runner.normalize(nil)
    end

    test "normalizes custom runner module" do
      assert {:ok, CustomRunner} = Runner.normalize(CustomRunner)
    end

    test "returns error for non-existent module" do
      assert {:error, {:module_not_found, NonExistentModule}} =
               Runner.normalize(NonExistentModule)
    end

    test "returns error for module without handle/3" do
      assert {:error, {:not_a_runner, Enum}} = Runner.normalize(Enum)
    end

    test "returns error for invalid config" do
      assert {:error, {:invalid_runner_config, "not_a_module"}} =
               Runner.normalize("not_a_module")
    end
  end

  describe "Runner.normalize!/1" do
    test "returns module for valid config" do
      assert Simple = Runner.normalize!(:simple)
    end

    test "raises for invalid config" do
      assert_raise Jido.Error.Invalid.RunnerConfig, fn ->
        Runner.normalize!("invalid")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Simple Runner
  # ---------------------------------------------------------------------------

  describe "Simple.handle/3" do
    test "delegates to agent handle_signal and returns state + effects" do
      {:ok, agent} = CounterAgent.new(%{id: "test-1", count: 0})
      signal = Signal.new!("increment", %{}, source: "/test")

      {:ok, new_agent, effects} = Simple.handle(CounterAgent, agent, signal)

      assert new_agent.count == 1
      assert effects == []
    end

    test "handles signals with data" do
      {:ok, agent} = CounterAgent.new(%{id: "test-1", count: 5})
      signal = Signal.new!("increment_by", %{"amount" => 10}, source: "/test")

      {:ok, new_agent, effects} = Simple.handle(CounterAgent, agent, signal)

      assert new_agent.count == 15
      assert effects == []
    end

    test "returns effects from agent" do
      {:ok, agent} = CounterAgent.new(%{id: "test-1", count: 42})
      signal = Signal.new!("get_count", %{}, source: "/test")

      {:ok, new_agent, effects} = Simple.handle(CounterAgent, agent, signal)

      assert new_agent.count == 42
      assert length(effects) == 1
      assert %Effect.Reply{signal: reply} = hd(effects)
      assert reply.type == "count_response"
      assert reply.data.count == 42
    end

    test "passes through error returns from agent" do
      {:ok, agent} = ErrorAgent.new(%{id: "test-1"})
      signal = Signal.new!("return_error", %{}, source: "/test")

      assert {:error, :intentional_error} = Simple.handle(ErrorAgent, agent, signal)
    end

    test "wraps exceptions in RunnerCallbackError" do
      {:ok, agent} = ErrorAgent.new(%{id: "test-1"})
      signal = Signal.new!("raise_error", %{}, source: "/test")

      {:error, error} = Simple.handle(ErrorAgent, agent, signal)

      assert %Jido.Error.Agent.RunnerCallbackError{} = error
      assert error.agent == ErrorAgent
      assert error.runner == Simple
      assert is_exception(error.reason)
    end

    test "returns UnexpectedRunnerResult for invalid return format" do
      {:ok, agent} = ErrorAgent.new(%{id: "test-1"})
      signal = Signal.new!("bad_return", %{}, source: "/test")

      {:error, error} = Simple.handle(ErrorAgent, agent, signal)

      assert %Jido.Error.Framework.UnexpectedRunnerResult{} = error
      assert error.agent == ErrorAgent
      assert error.runner == Simple
      assert error.result == :not_a_valid_return
    end

    test "handles unknown signals gracefully" do
      {:ok, agent} = CounterAgent.new(%{id: "test-1", count: 0})
      signal = Signal.new!("unknown_signal", %{}, source: "/test")

      {:ok, new_agent, effects} = Simple.handle(CounterAgent, agent, signal)

      assert new_agent.count == 0
      assert effects == []
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Agent runner/0 function
  # ---------------------------------------------------------------------------

  describe "Agent.runner/0" do
    test "returns Simple runner by default" do
      assert CounterAgent.runner() == Simple
    end

    test "returns configured custom runner" do
      assert CustomRunnerAgent.runner() == CustomRunner
    end

    test "returns raw runner config" do
      assert CounterAgent.runner_config() == :simple
      assert CustomRunnerAgent.runner_config() == CustomRunner
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: Custom Runner Integration
  # ---------------------------------------------------------------------------

  describe "custom runner integration" do
    test "custom runner can add effects" do
      {:ok, agent} = CustomRunnerAgent.new(%{id: "test-1"})
      signal = Signal.new!("any_signal", %{}, source: "/test")

      {:ok, _new_agent, effects} = CustomRunner.handle(CustomRunnerAgent, agent, signal)

      assert length(effects) == 1
      assert %Effect.Reply{signal: reply} = hd(effects)
      assert reply.type == "custom_runner_processed"
    end
  end
end
