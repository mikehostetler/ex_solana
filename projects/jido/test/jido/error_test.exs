defmodule JidoTest.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Error

  describe "validation_error/2" do
    test "creates a validation error with message" do
      error = Error.validation_error("Invalid input")

      assert %Error.ValidationError{} = error
      assert error.message == "Invalid input"
    end

    test "creates a validation error with field (infers kind: :input)" do
      error = Error.validation_error("Invalid field", field: :email)

      assert error.message == "Invalid field"
      assert error.kind == :input
      assert error.subject == :email
    end

    test "creates a validation error with explicit kind and subject" do
      error = Error.validation_error("Invalid", kind: :config, subject: :timeout)

      assert error.kind == :config
      assert error.subject == :timeout
    end

    test "creates a validation error for action (convenience)" do
      error = Error.validation_error("Action not found", action: SomeAction)

      assert error.message == "Action not found"
      assert error.kind == :action
      assert error.subject == SomeAction
    end

    test "creates a validation error for sensor (convenience)" do
      error = Error.validation_error("Sensor failed", sensor: SomeSensor)

      assert error.message == "Sensor failed"
      assert error.kind == :sensor
      assert error.subject == SomeSensor
    end
  end

  describe "execution_error/2" do
    test "creates an execution error" do
      error = Error.execution_error("Execution failed")

      assert %Error.ExecutionError{} = error
      assert error.message == "Execution failed"
      assert error.phase == :execution
    end

    test "creates an execution error with planning phase" do
      error = Error.execution_error("Planning failed", phase: :planning)

      assert error.message == "Planning failed"
      assert error.phase == :planning
    end

    test "creates an execution error with details" do
      error = Error.execution_error("Failed", details: %{step: :process})

      assert error.details[:step] == :process
    end
  end

  describe "routing_error/2" do
    test "creates a routing error" do
      error = Error.routing_error("Route not found", target: :agent_1)

      assert %Error.RoutingError{} = error
      assert error.message == "Route not found"
      assert error.target == :agent_1
    end
  end

  describe "timeout_error/2" do
    test "creates a timeout error" do
      error = Error.timeout_error("Operation timed out", timeout: 5000)

      assert %Error.TimeoutError{} = error
      assert error.message == "Operation timed out"
      assert error.timeout == 5000
    end
  end

  describe "compensation_error/2" do
    test "creates a compensation error for successful compensation" do
      original = Error.execution_error("Original failure")

      error =
        Error.compensation_error("Compensated",
          original_error: original,
          compensated: true,
          result: %{refund: true}
        )

      assert %Error.CompensationError{} = error
      assert error.compensated == true
      assert error.original_error == original
      assert error.result == %{refund: true}
    end

    test "creates a compensation error for failed compensation" do
      original = Error.execution_error("Original failure")

      error =
        Error.compensation_error("Compensation failed",
          original_error: original,
          compensated: false
        )

      assert error.compensated == false
      assert error.original_error == original
    end
  end

  describe "internal_error/2" do
    test "creates an internal error" do
      error = Error.internal_error("Unexpected error")

      assert %Error.InternalError{} = error
      assert error.message == "Unexpected error"
    end

    test "creates an internal error with details" do
      error = Error.internal_error("Failed", details: %{reason: :unknown})

      assert error.details[:reason] == :unknown
    end
  end

  describe "format_nimble_config_error/3" do
    test "formats error without keys path" do
      nimble_error = %NimbleOptions.ValidationError{keys_path: [], message: "invalid option"}
      result = Error.format_nimble_config_error(nimble_error, "Agent", TestAgent)

      assert result =~ "Invalid configuration"
      assert result =~ "invalid option"
    end

    test "formats error with keys path" do
      nimble_error = %NimbleOptions.ValidationError{
        keys_path: [:schema, :name],
        message: "required"
      }

      result = Error.format_nimble_config_error(nimble_error, "Agent", TestAgent)

      assert result =~ "Invalid configuration"
      assert result =~ "[:schema, :name]"
    end

    test "handles binary and other error types" do
      assert Error.format_nimble_config_error("plain string error", "Agent", TestAgent) ==
               "plain string error"

      assert Error.format_nimble_config_error({:error, :unknown}, "Agent", TestAgent) =~
               ":error"
    end
  end

  describe "format_nimble_validation_error/3" do
    test "formats validation error without keys path" do
      nimble_error = %NimbleOptions.ValidationError{keys_path: [], message: "invalid value"}
      result = Error.format_nimble_validation_error(nimble_error, "Action", TestAction)

      assert result =~ "Invalid parameters"
      assert result =~ "invalid value"
    end

    test "formats validation error with keys path" do
      nimble_error = %NimbleOptions.ValidationError{
        keys_path: [:params, :id],
        message: "must be integer"
      }

      result = Error.format_nimble_validation_error(nimble_error, "Action", TestAction)

      assert result =~ "Invalid parameters"
      assert result =~ "[:params, :id]"
    end

    test "handles binary and other validation error types" do
      assert Error.format_nimble_validation_error("plain string", "Action", TestAction) ==
               "plain string"

      assert Error.format_nimble_validation_error({:error, :bad}, "Action", TestAction) =~
               ":error"
    end
  end

  describe "to_map/1" do
    test "converts validation error to map" do
      error = Error.validation_error("Invalid", field: :email)
      result = Error.to_map(error)

      assert result.type == :validation_error
      assert result.message == "Invalid"
      assert is_list(result.stacktrace)
    end

    test "converts validation error with kind: :action to :invalid_action" do
      error = Error.validation_error("Bad action", action: SomeAction)
      result = Error.to_map(error)

      assert result.type == :invalid_action
    end

    test "converts validation error with kind: :sensor to :invalid_sensor" do
      error = Error.validation_error("Bad sensor", sensor: SomeSensor)
      result = Error.to_map(error)

      assert result.type == :invalid_sensor
    end

    test "converts validation error with kind: :config to :config_error" do
      error = Error.validation_error("Bad config", kind: :config)
      result = Error.to_map(error)

      assert result.type == :config_error
    end

    test "converts execution error to map" do
      error = Error.execution_error("Failed")
      result = Error.to_map(error)

      assert result.type == :execution_error
    end

    test "converts execution error with phase: :planning to :planning_error" do
      error = Error.execution_error("Planning failed", phase: :planning)
      result = Error.to_map(error)

      assert result.type == :planning_error
    end

    test "converts routing error to map" do
      error = Error.routing_error("Route not found", target: :agent)
      result = Error.to_map(error)

      assert result.type == :routing_error
    end

    test "converts timeout error to map" do
      error = Error.timeout_error("Timed out", timeout: 5000)
      result = Error.to_map(error)

      assert result.type == :timeout
    end

    test "converts compensation error to map" do
      original = Error.execution_error("Original")
      error = Error.compensation_error("Compensated", original_error: original, compensated: true)
      result = Error.to_map(error)

      assert result.type == :compensation_error
    end

    test "converts internal error to map" do
      error = Error.internal_error("Internal")
      result = Error.to_map(error)

      assert result.type == :internal
    end

    test "handles unknown struct" do
      result = Error.to_map(%{unknown: "struct"})

      assert result.type == :internal
    end
  end

  describe "extract_message/1" do
    test "extracts message from various structures" do
      assert Error.extract_message(%{message: %{message: "Nested"}}) == "Nested"
      assert Error.extract_message(%{message: "Direct"}) == "Direct"
      assert Error.extract_message(%{message: nil}) == ""

      inner = struct(Error.InternalError, message: "Struct message", details: %{})
      assert Error.extract_message(%{message: inner}) == "Struct message"

      assert Error.extract_message("plain string") =~ "plain string"
    end
  end

  describe "capture_stacktrace/0" do
    test "returns current stacktrace" do
      stacktrace = Error.capture_stacktrace()

      assert is_list(stacktrace)
      assert length(stacktrace) > 0
    end
  end
end
