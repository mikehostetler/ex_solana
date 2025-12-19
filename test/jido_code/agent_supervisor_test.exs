defmodule JidoCode.AgentSupervisorTest do
  use ExUnit.Case, async: false

  alias JidoCode.AgentSupervisor
  alias JidoCode.Telemetry.AgentInstrumentation
  alias JidoCode.TestAgent

  setup do
    # Ensure supervisor starts with no children
    for {_, pid, _, _} <- AgentSupervisor.which_children() do
      AgentSupervisor.stop_agent(pid)
    end

    :ok
  end

  describe "start_agent/1" do
    test "starts an agent successfully" do
      assert {:ok, pid} =
               AgentSupervisor.start_agent(%{
                 name: :test_agent_1,
                 module: TestAgent,
                 args: []
               })

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "agent registers in AgentRegistry" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_2,
          module: TestAgent,
          args: []
        })

      assert {:ok, ^pid} = AgentSupervisor.lookup_agent(:test_agent_2)
    end

    test "returns error for duplicate name" do
      {:ok, _pid} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_3,
          module: TestAgent,
          args: []
        })

      assert {:error, {:already_started, _}} =
               AgentSupervisor.start_agent(%{
                 name: :test_agent_3,
                 module: TestAgent,
                 args: []
               })
    end

    test "returns error for invalid spec" do
      assert {:error, msg} = AgentSupervisor.start_agent(%{})
      assert msg =~ "invalid agent spec"
      assert msg =~ ":name and :module"

      assert {:error, msg} = AgentSupervisor.start_agent(%{name: :foo})
      assert msg =~ "invalid agent spec"

      assert {:error, msg} = AgentSupervisor.start_agent(%{module: TestAgent})
      assert msg =~ "invalid agent spec"
    end

    test "increments child count" do
      initial_count = AgentSupervisor.count_children().active

      {:ok, _} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_4,
          module: TestAgent,
          args: []
        })

      assert AgentSupervisor.count_children().active == initial_count + 1
    end
  end

  describe "stop_agent/1" do
    test "stops agent by pid" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_5,
          module: TestAgent,
          args: []
        })

      assert :ok = AgentSupervisor.stop_agent(pid)
      refute Process.alive?(pid)
    end

    test "stops agent by name" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_6,
          module: TestAgent,
          args: []
        })

      assert :ok = AgentSupervisor.stop_agent(:test_agent_6)
      refute Process.alive?(pid)
    end

    test "returns error for unknown pid" do
      fake_pid = spawn(fn -> :ok end)
      Process.sleep(10)
      assert {:error, :not_found} = AgentSupervisor.stop_agent(fake_pid)
    end

    test "returns error for unknown name" do
      assert {:error, :not_found} = AgentSupervisor.stop_agent(:unknown_agent)
    end

    test "decrements child count" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_7,
          module: TestAgent,
          args: []
        })

      count_before = AgentSupervisor.count_children().active
      AgentSupervisor.stop_agent(pid)
      assert AgentSupervisor.count_children().active == count_before - 1
    end
  end

  describe "lookup_agent/1" do
    test "returns pid for existing agent" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :test_agent_8,
          module: TestAgent,
          args: []
        })

      assert {:ok, ^pid} = AgentSupervisor.lookup_agent(:test_agent_8)
    end

    test "returns error for non-existent agent" do
      assert {:error, :not_found} = AgentSupervisor.lookup_agent(:nonexistent)
    end
  end

  describe "restart behavior" do
    test "agent with transient restart recovers from crash" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :crash_test_agent,
          module: TestAgent,
          args: []
        })

      original_pid = pid

      # Cause a crash
      TestAgent.crash(pid)

      # Wait for restart
      Process.sleep(100)

      # Should have a new pid (restarted)
      {:ok, new_pid} = AgentSupervisor.lookup_agent(:crash_test_agent)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end

    test "agent with normal exit is not restarted" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :normal_exit_agent,
          module: TestAgent,
          args: []
        })

      # Request normal shutdown
      TestAgent.stop(pid)

      # Wait a bit
      Process.sleep(100)

      # Should not be restarted
      assert {:error, :not_found} = AgentSupervisor.lookup_agent(:normal_exit_agent)
    end
  end

  describe "TestAgent functionality" do
    test "can get and set state" do
      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: :state_test_agent,
          module: TestAgent,
          args: []
        })

      initial_state = TestAgent.get_state(pid)
      assert is_map(initial_state)
      assert Map.has_key?(initial_state, :started_at)

      TestAgent.set_state(pid, %{custom: "value"})
      assert %{custom: "value"} = TestAgent.get_state(pid)
    end
  end

  describe "telemetry integration" do
    setup do
      # Ensure ETS table is set up
      AgentInstrumentation.setup()

      # Attach a test handler to capture events
      test_pid = self()

      :telemetry.attach_many(
        "supervisor-test-handler-#{inspect(self())}",
        [
          AgentInstrumentation.event_start(),
          AgentInstrumentation.event_stop()
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("supervisor-test-handler-#{inspect(test_pid)}")
      end)

      :ok
    end

    test "emits start event when agent starts" do
      {:ok, _pid} =
        AgentSupervisor.start_agent(%{
          name: :telemetry_start_agent,
          module: TestAgent,
          args: []
        })

      assert_receive {:telemetry_event, [:jido_code, :agent, :start], _measurements, metadata}
      assert metadata.name == :telemetry_start_agent
      assert metadata.module == TestAgent
    end

    test "emits stop event when agent stops by name" do
      {:ok, _pid} =
        AgentSupervisor.start_agent(%{
          name: :telemetry_stop_agent,
          module: TestAgent,
          args: []
        })

      # Clear the start event
      assert_receive {:telemetry_event, [:jido_code, :agent, :start], _, _}

      # Stop the agent
      AgentSupervisor.stop_agent(:telemetry_stop_agent)

      assert_receive {:telemetry_event, [:jido_code, :agent, :stop], measurements, metadata}
      assert metadata.name == :telemetry_stop_agent
      assert metadata.module == TestAgent
      assert metadata.reason == :normal
      assert is_integer(measurements.duration)
    end
  end
end
