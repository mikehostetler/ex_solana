defmodule JidoTest.Agent.Strategy.StateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StrategyState
  alias JidoTest.TestAgents

  describe "key/0" do
    test "returns the reserved strategy state key" do
      assert StrategyState.key() == :__strategy__
    end
  end

  describe "get/2" do
    test "returns strategy state from agent" do
      agent =
        TestAgents.Basic.new()
        |> Map.update!(:state, &Map.put(&1, :__strategy__, %{status: :running}))

      result = StrategyState.get(agent)

      assert result == %{status: :running}
    end

    test "returns default when no strategy state exists" do
      agent = TestAgents.Basic.new()

      assert StrategyState.get(agent, %{status: :idle}) == %{status: :idle}
      assert StrategyState.get(agent) == %{}
    end
  end

  describe "put/2" do
    test "puts and replaces strategy state" do
      agent = TestAgents.Basic.new()

      updated = StrategyState.put(agent, %{status: :running, data: "test"})
      assert updated.state[:__strategy__] == %{status: :running, data: "test"}

      updated2 = StrategyState.put(updated, %{new: "data"})
      assert updated2.state[:__strategy__] == %{new: "data"}
    end
  end

  describe "update/2" do
    test "updates strategy state using function" do
      agent =
        TestAgents.Basic.new()
        |> Map.update!(:state, &Map.put(&1, :__strategy__, %{count: 1}))

      updated =
        StrategyState.update(agent, fn state -> Map.put(state, :count, state.count + 1) end)

      assert updated.state[:__strategy__][:count] == 2
    end

    test "passes empty map to function when no strategy state exists" do
      agent = TestAgents.Basic.new()

      updated = StrategyState.update(agent, fn state -> Map.put(state, :initialized, true) end)

      assert updated.state[:__strategy__][:initialized] == true
    end
  end

  describe "status/1 and set_status/2" do
    test "returns :idle when no status is set" do
      agent = TestAgents.Basic.new()
      assert StrategyState.status(agent) == :idle
    end

    test "sets and retrieves all supported status values" do
      for status <- [:idle, :running, :waiting, :success, :failure] do
        agent = TestAgents.Basic.new()
        updated = StrategyState.set_status(agent, status)

        assert StrategyState.status(updated) == status,
               "expected status #{inspect(status)} after set_status"
      end
    end
  end

  describe "terminal?/1" do
    test "detects terminal statuses" do
      cases = [
        {:success, true},
        {:failure, true},
        {:running, false},
        {:idle, false},
        {:waiting, false}
      ]

      for {status, expected} <- cases do
        agent =
          TestAgents.Basic.new()
          |> Map.update!(:state, &Map.put(&1, :__strategy__, %{status: status}))

        assert StrategyState.terminal?(agent) == expected,
               "expected terminal?(#{inspect(status)}) to be #{expected}"
      end
    end
  end

  describe "active?/1" do
    test "detects active statuses" do
      cases = [
        {:running, true},
        {:waiting, true},
        {:idle, false},
        {:success, false},
        {:failure, false}
      ]

      for {status, expected} <- cases do
        agent =
          TestAgents.Basic.new()
          |> Map.update!(:state, &Map.put(&1, :__strategy__, %{status: status}))

        assert StrategyState.active?(agent) == expected,
               "expected active?(#{inspect(status)}) to be #{expected}"
      end
    end
  end

  describe "clear/1" do
    test "clears strategy state to empty map" do
      agent =
        TestAgents.Basic.new()
        |> Map.update!(:state, &Map.put(&1, :__strategy__, %{status: :running, data: "test"}))

      cleared = StrategyState.clear(agent)

      assert StrategyState.get(cleared) == %{}
    end
  end
end
