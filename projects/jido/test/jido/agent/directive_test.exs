defmodule JidoTest.Agent.DirectiveTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive

  describe "emit/2" do
    test "creates Emit directive without dispatch" do
      signal = %{type: "test"}
      directive = Directive.emit(signal)
      assert %Directive.Emit{signal: ^signal, dispatch: nil} = directive
    end

    test "creates Emit directive with dispatch config" do
      signal = %{type: "test"}
      directive = Directive.emit(signal, {:pubsub, topic: "events"})
      assert directive.signal == signal
      assert directive.dispatch == {:pubsub, topic: "events"}
    end
  end

  describe "error/2" do
    test "creates Error directive without context" do
      error = %{message: "test error"}
      directive = Directive.error(error)
      assert %Directive.Error{error: ^error, context: nil} = directive
    end

    test "creates Error directive with context" do
      error = %{message: "test error"}
      directive = Directive.error(error, :normalize)
      assert directive.error == error
      assert directive.context == :normalize
    end
  end

  describe "spawn/2" do
    test "creates Spawn directive without tag" do
      child_spec = {MyWorker, arg: :value}
      directive = Directive.spawn(child_spec)
      assert %Directive.Spawn{child_spec: ^child_spec, tag: nil} = directive
    end

    test "creates Spawn directive with tag" do
      child_spec = {MyWorker, arg: :value}
      directive = Directive.spawn(child_spec, :worker_1)
      assert directive.child_spec == child_spec
      assert directive.tag == :worker_1
    end
  end

  describe "spawn_agent/3" do
    test "creates SpawnAgent directive with defaults" do
      directive = Directive.spawn_agent(MyAgent, :worker_1)
      assert %Directive.SpawnAgent{} = directive
      assert directive.agent == MyAgent
      assert directive.tag == :worker_1
      assert directive.opts == %{}
      assert directive.meta == %{}
    end

    test "creates SpawnAgent directive with opts" do
      directive =
        Directive.spawn_agent(MyAgent, :processor, opts: %{initial_state: %{batch: 100}})

      assert directive.opts == %{initial_state: %{batch: 100}}
      assert directive.meta == %{}
    end

    test "creates SpawnAgent directive with meta" do
      directive = Directive.spawn_agent(MyAgent, :handler, meta: %{topic: "events"})
      assert directive.opts == %{}
      assert directive.meta == %{topic: "events"}
    end

    test "creates SpawnAgent directive with both opts and meta" do
      directive =
        Directive.spawn_agent(MyAgent, :worker,
          opts: %{id: "custom"},
          meta: %{assigned: true}
        )

      assert directive.opts == %{id: "custom"}
      assert directive.meta == %{assigned: true}
    end
  end

  describe "stop_child/2" do
    test "creates StopChild directive with default reason" do
      directive = Directive.stop_child(:worker_1)
      assert %Directive.StopChild{tag: :worker_1, reason: :normal} = directive
    end

    test "creates StopChild directive with custom reason" do
      directive = Directive.stop_child(:processor, :shutdown)
      assert directive.tag == :processor
      assert directive.reason == :shutdown
    end
  end

  describe "schedule/2" do
    test "creates Schedule directive" do
      directive = Directive.schedule(5000, :timeout)
      assert %Directive.Schedule{delay_ms: 5000, message: :timeout} = directive
    end

    test "creates Schedule directive with complex message" do
      directive = Directive.schedule(1000, {:check, ref: "abc123"})
      assert directive.delay_ms == 1000
      assert directive.message == {:check, ref: "abc123"}
    end
  end

  describe "stop/1" do
    test "creates Stop directive with default reason" do
      directive = Directive.stop()
      assert %Directive.Stop{reason: :normal} = directive
    end

    test "creates Stop directive with custom reason" do
      directive = Directive.stop(:shutdown)
      assert directive.reason == :shutdown
    end
  end

  describe "emit_to_pid/3" do
    test "creates Emit directive targeting a pid" do
      signal = %{type: "test"}
      pid = self()
      directive = Directive.emit_to_pid(signal, pid)
      assert %Directive.Emit{signal: ^signal, dispatch: {:pid, opts}} = directive
      assert opts[:target] == pid
    end

    test "merges extra options" do
      signal = %{type: "test"}
      pid = self()
      directive = Directive.emit_to_pid(signal, pid, delivery_mode: :sync, timeout: 10_000)
      {:pid, opts} = directive.dispatch
      assert opts[:target] == pid
      assert opts[:delivery_mode] == :sync
      assert opts[:timeout] == 10_000
    end
  end

  describe "emit_to_parent/3" do
    test "returns nil when agent has no parent" do
      agent = %{state: %{}}
      assert Directive.emit_to_parent(agent, %{type: "test"}) == nil
    end

    test "returns nil when parent ref is missing pid" do
      agent = %{state: %{__parent__: %{}}}
      assert Directive.emit_to_parent(agent, %{type: "test"}) == nil
    end

    test "creates Emit directive when parent is present" do
      parent_pid = self()

      parent_ref =
        Jido.AgentServer.ParentRef.new!(%{pid: parent_pid, id: "parent-123", tag: :child})

      agent = %{state: %{__parent__: parent_ref}}
      signal = %{type: "child.result"}

      directive = Directive.emit_to_parent(agent, signal)

      assert %Directive.Emit{signal: ^signal, dispatch: {:pid, opts}} = directive
      assert opts[:target] == parent_pid
    end

    test "passes extra options to emit_to_pid" do
      parent_pid = self()

      parent_ref =
        Jido.AgentServer.ParentRef.new!(%{pid: parent_pid, id: "parent-123", tag: :child})

      agent = %{state: %{__parent__: parent_ref}}

      directive = Directive.emit_to_parent(agent, %{type: "test"}, delivery_mode: :sync)

      {:pid, opts} = directive.dispatch
      assert opts[:delivery_mode] == :sync
    end
  end

  describe "directive structs" do
    test "Emit struct fields" do
      emit = %Directive.Emit{signal: %{type: "test"}, dispatch: nil}
      assert emit.signal == %{type: "test"}
      assert emit.dispatch == nil
    end

    test "Error struct fields" do
      error = %Directive.Error{error: %{msg: "fail"}, context: :test}
      assert error.error == %{msg: "fail"}
      assert error.context == :test
    end

    test "Schedule struct fields" do
      schedule = %Directive.Schedule{delay_ms: 100, message: :tick}
      assert schedule.delay_ms == 100
      assert schedule.message == :tick
    end

    test "Stop struct fields" do
      stop = %Directive.Stop{reason: :normal}
      assert stop.reason == :normal
    end

    test "Spawn struct fields" do
      spawn_d = %Directive.Spawn{child_spec: {MyWorker, []}, tag: :w1}
      assert spawn_d.child_spec == {MyWorker, []}
      assert spawn_d.tag == :w1
    end

    test "SpawnAgent struct fields" do
      spawn_a = %Directive.SpawnAgent{agent: MyAgent, tag: :child, opts: %{}, meta: %{}}
      assert spawn_a.agent == MyAgent
      assert spawn_a.tag == :child
    end

    test "StopChild struct fields" do
      stop_c = %Directive.StopChild{tag: :child, reason: :normal}
      assert stop_c.tag == :child
      assert stop_c.reason == :normal
    end
  end
end
