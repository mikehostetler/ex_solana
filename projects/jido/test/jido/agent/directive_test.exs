defmodule JidoTest.Agent.DirectiveTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.{Emit, Error, Spawn, Schedule, Stop}

  describe "schema/0" do
    test "all directives expose schema/0" do
      for mod <- [Emit, Error, Spawn, Schedule, Stop] do
        assert mod.schema(), "#{inspect(mod)}.schema/0 should return a schema"
      end
    end
  end

  describe "emit/2" do
    test "creates Emit directive with signal only" do
      signal = %{type: "test.event"}
      directive = Directive.emit(signal)

      assert %Emit{signal: ^signal, dispatch: nil} = directive
    end

    test "creates Emit directive with dispatch config" do
      signal = %{type: "test.event"}
      dispatch = {:pubsub, topic: "events"}
      directive = Directive.emit(signal, dispatch)

      assert %Emit{signal: ^signal, dispatch: ^dispatch} = directive
    end

    test "creates Emit with list dispatch config" do
      signal = %{type: "test.event"}
      dispatch = [{:pubsub, topic: "events"}, {:logger, level: :info}]
      directive = Directive.emit(signal, dispatch)

      assert %Emit{signal: ^signal, dispatch: ^dispatch} = directive
    end
  end

  describe "error/2" do
    test "creates Error directive with error only" do
      error = Jido.Error.validation_error("Test")
      directive = Directive.error(error)

      assert %Error{error: ^error, context: nil} = directive
    end

    test "creates Error directive with context" do
      error = Jido.Error.execution_error("Failed")
      directive = Directive.error(error, :normalize)

      assert %Error{error: ^error, context: :normalize} = directive
    end
  end

  describe "spawn/2" do
    test "creates Spawn directive with child_spec only" do
      child_spec = {Task, fn -> :ok end}
      directive = Directive.spawn(child_spec)

      assert %Spawn{child_spec: ^child_spec, tag: nil} = directive
    end

    test "creates Spawn directive with tag" do
      child_spec = {Task, fn -> :ok end}
      directive = Directive.spawn(child_spec, :worker_1)

      assert %Spawn{child_spec: ^child_spec, tag: :worker_1} = directive
    end
  end

  describe "schedule/2" do
    test "creates Schedule directive" do
      directive = Directive.schedule(5000, :timeout)

      assert %Schedule{delay_ms: 5000, message: :timeout} = directive
    end

    test "creates Schedule with complex message" do
      directive = Directive.schedule(1000, {:check, ref: "abc"})

      assert %Schedule{delay_ms: 1000, message: {:check, ref: "abc"}} = directive
    end
  end

  describe "stop/1" do
    test "creates Stop directive with default reason" do
      directive = Directive.stop()

      assert %Stop{reason: :normal} = directive
    end

    test "creates Stop directive with custom reason" do
      directive = Directive.stop(:shutdown)

      assert %Stop{reason: :shutdown} = directive
    end

    test "creates Stop directive with error reason" do
      directive = Directive.stop({:error, :crashed})

      assert %Stop{reason: {:error, :crashed}} = directive
    end
  end
end
