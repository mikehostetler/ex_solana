defmodule JidoCode.ApplicationTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure infrastructure is running (may have been stopped by another test)
    JidoCode.Test.SessionTestHelpers.ensure_infrastructure()
    :ok
  end

  describe "supervision tree" do
    test "application starts successfully" do
      # Application is already started by ExUnit
      assert Process.whereis(JidoCode.Supervisor) != nil
    end

    test "PubSub is running" do
      assert Process.whereis(JidoCode.PubSub) != nil
    end

    test "AgentRegistry is running" do
      assert Registry.lookup(JidoCode.AgentRegistry, :test) == []
    end

    test "AgentSupervisor is running" do
      assert Process.whereis(JidoCode.AgentSupervisor) != nil
    end

    test "AgentSupervisor is a DynamicSupervisor" do
      # Verify it responds to DynamicSupervisor functions
      counts = JidoCode.AgentSupervisor.count_children()
      assert is_map(counts)
      assert Map.has_key?(counts, :active)
      assert Map.has_key?(counts, :workers)
    end

    test "AgentSupervisor starts with no children" do
      counts = JidoCode.AgentSupervisor.count_children()
      assert counts.active == 0
      assert counts.workers == 0
    end

    test "Settings.Cache is running" do
      assert Process.whereis(JidoCode.Settings.Cache) != nil
    end

    test "all supervisor children are running" do
      # Verify all expected children are present
      children = Supervisor.which_children(JidoCode.Supervisor)

      # Should have 11 children:
      # - Settings.Cache, Jido.AI.Model.Registry.Cache, TermUI.Theme
      # - PubSub, AgentRegistry, SessionProcessRegistry
      # - Tools.Manager, TaskSupervisor, RateLimit
      # - AgentSupervisor, SessionSupervisor
      assert length(children) == 11

      # Extract child ids
      child_ids = Enum.map(children, fn {id, _pid, _type, _modules} -> id end)

      # Settings.Cache starts first
      assert JidoCode.Settings.Cache in child_ids
      # Model registry cache for Jido.AI
      assert Jido.AI.Model.Registry.Cache in child_ids
      # Theme server for TUI styling
      assert TermUI.Theme in child_ids
      # PubSub registers as Phoenix.PubSub.Supervisor internally
      assert Phoenix.PubSub.Supervisor in child_ids
      assert JidoCode.AgentRegistry in child_ids
      # SessionProcessRegistry for session process lookup
      assert JidoCode.SessionProcessRegistry in child_ids
      # TaskSupervisor for monitored async tasks (ARCH-1 fix)
      assert JidoCode.TaskSupervisor in child_ids
      # Tools.Manager for Lua sandbox
      assert JidoCode.Tools.Manager in child_ids
      # RateLimit for session operations
      assert JidoCode.RateLimit in child_ids
      assert JidoCode.AgentSupervisor in child_ids
      # SessionSupervisor for session processes
      assert JidoCode.SessionSupervisor in child_ids
    end

    # Task 1.5.1 Integration Tests (B1 fix)

    test "SessionSupervisor is running after application start" do
      assert Process.whereis(JidoCode.SessionSupervisor) != nil
    end

    test "SessionProcessRegistry is running after application start" do
      # Registry doesn't use whereis, check it's queryable
      assert Registry.lookup(JidoCode.SessionProcessRegistry, :nonexistent) == []
    end

    test "SessionRegistry ETS table exists after application start" do
      assert JidoCode.SessionRegistry.table_exists?()
    end
  end

  describe "PubSub functionality" do
    test "can subscribe and receive messages" do
      topic = "test:supervision"
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
      Phoenix.PubSub.broadcast(JidoCode.PubSub, topic, {:test_message, "hello"})

      assert_receive {:test_message, "hello"}, 100
    end
  end

  describe "Registry functionality" do
    test "can register and lookup processes" do
      # Register current process
      {:ok, _} = Registry.register(JidoCode.AgentRegistry, :test_agent, %{type: :test})

      # Lookup should find it
      [{pid, value}] = Registry.lookup(JidoCode.AgentRegistry, :test_agent)
      assert pid == self()
      assert value == %{type: :test}
    end

    test "registry enforces unique keys" do
      {:ok, _} = Registry.register(JidoCode.AgentRegistry, :unique_test, :first)

      # Second registration with same key should fail
      assert {:error, {:already_registered, _}} =
               Registry.register(JidoCode.AgentRegistry, :unique_test, :second)
    end
  end
end
