defmodule JidoCode.Telemetry.AgentInstrumentationTest do
  use ExUnit.Case, async: false

  alias JidoCode.Telemetry.AgentInstrumentation

  @moduletag :telemetry

  setup do
    # Ensure ETS table is set up
    AgentInstrumentation.setup()

    # Attach a test handler to capture events
    test_pid = self()

    :telemetry.attach_many(
      "test-handler-#{inspect(self())}",
      [
        AgentInstrumentation.event_start(),
        AgentInstrumentation.event_stop(),
        AgentInstrumentation.event_crash()
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("test-handler-#{inspect(test_pid)}")
      # Clean up restart counts
      AgentInstrumentation.reset_restart_count(:test_agent)
    end)

    :ok
  end

  describe "emit_start/2" do
    test "emits start telemetry event" do
      AgentInstrumentation.emit_start(:test_agent, TestModule)

      assert_receive {:telemetry_event, [:jido_code, :agent, :start], measurements, metadata}

      assert is_integer(measurements.system_time)
      assert metadata.name == :test_agent
      assert metadata.module == TestModule
    end

    test "returns start time for duration tracking" do
      start_time = AgentInstrumentation.emit_start(:test_agent, TestModule)

      assert is_integer(start_time)
    end
  end

  describe "emit_stop/3" do
    test "emits stop telemetry event with duration" do
      # First emit start to record start time
      AgentInstrumentation.emit_start(:test_agent, TestModule)

      # Small delay to ensure measurable duration
      Process.sleep(10)

      AgentInstrumentation.emit_stop(:test_agent, TestModule, :normal)

      # Should receive both start and stop events
      assert_receive {:telemetry_event, [:jido_code, :agent, :start], _, _}
      assert_receive {:telemetry_event, [:jido_code, :agent, :stop], measurements, metadata}

      assert measurements.duration > 0
      assert metadata.name == :test_agent
      assert metadata.module == TestModule
      assert metadata.reason == :normal
    end

    test "resets restart count on normal stop" do
      # Simulate some crashes first
      AgentInstrumentation.emit_start(:test_agent, TestModule)
      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash_reason)
      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash_reason)

      assert AgentInstrumentation.restart_count(:test_agent) == 2

      # Now stop normally
      AgentInstrumentation.emit_stop(:test_agent, TestModule, :normal)

      # Restart count should be reset
      assert AgentInstrumentation.restart_count(:test_agent) == 0
    end
  end

  describe "emit_crash/3" do
    test "emits crash telemetry event with duration and restart count" do
      AgentInstrumentation.emit_start(:test_agent, TestModule)

      Process.sleep(10)

      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash_reason)

      assert_receive {:telemetry_event, [:jido_code, :agent, :start], _, _}
      assert_receive {:telemetry_event, [:jido_code, :agent, :crash], measurements, metadata}

      assert measurements.duration > 0
      assert metadata.name == :test_agent
      assert metadata.module == TestModule
      assert metadata.reason == :crash_reason
      assert metadata.restart_count == 1
    end

    test "increments restart count on each crash" do
      AgentInstrumentation.emit_start(:test_agent, TestModule)

      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash1)
      assert AgentInstrumentation.restart_count(:test_agent) == 1

      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash2)
      assert AgentInstrumentation.restart_count(:test_agent) == 2

      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash3)
      assert AgentInstrumentation.restart_count(:test_agent) == 3
    end
  end

  describe "restart_count/1" do
    test "returns 0 for agents that haven't crashed" do
      assert AgentInstrumentation.restart_count(:never_crashed_agent) == 0
    end

    test "returns current crash count" do
      AgentInstrumentation.emit_start(:test_agent, TestModule)
      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash)
      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash)

      assert AgentInstrumentation.restart_count(:test_agent) == 2
    end
  end

  describe "reset_restart_count/1" do
    test "resets count to zero" do
      AgentInstrumentation.emit_start(:test_agent, TestModule)
      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash)
      AgentInstrumentation.emit_crash(:test_agent, TestModule, :crash)

      assert AgentInstrumentation.restart_count(:test_agent) == 2

      AgentInstrumentation.reset_restart_count(:test_agent)

      assert AgentInstrumentation.restart_count(:test_agent) == 0
    end
  end

  describe "attach_logger/1" do
    test "attaches logger handler" do
      # Detach any existing handler first
      AgentInstrumentation.detach_logger()

      assert :ok = AgentInstrumentation.attach_logger(level: :debug)

      # Should return error if already attached
      assert {:error, :already_exists} = AgentInstrumentation.attach_logger()

      # Clean up
      AgentInstrumentation.detach_logger()
    end
  end

  describe "detach_logger/0" do
    test "detaches logger handler" do
      AgentInstrumentation.attach_logger()
      assert :ok = AgentInstrumentation.detach_logger()

      # Should return error if not attached
      assert {:error, :not_found} = AgentInstrumentation.detach_logger()
    end
  end

  describe "event name accessors" do
    test "event_start/0 returns correct event name" do
      assert AgentInstrumentation.event_start() == [:jido_code, :agent, :start]
    end

    test "event_stop/0 returns correct event name" do
      assert AgentInstrumentation.event_stop() == [:jido_code, :agent, :stop]
    end

    test "event_crash/0 returns correct event name" do
      assert AgentInstrumentation.event_crash() == [:jido_code, :agent, :crash]
    end
  end
end
