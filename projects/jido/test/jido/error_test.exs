defmodule JidoTest.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Error

  describe "validation_error/2" do
    test "creates a validation error with message" do
      error = Error.validation_error("Invalid input")

      assert error.message == "Invalid input"
    end

    test "creates a validation error with details" do
      error = Error.validation_error("Invalid field", field: :email, value: "bad")

      assert error.message == "Invalid field"
      assert error.field == :email
      assert error.value == "bad"
    end
  end

  describe "invalid_action/2" do
    test "creates an invalid action error" do
      error = Error.invalid_action("Action not found", action: SomeAction)

      assert error.message == "Action not found"
      assert error.action == SomeAction
    end
  end

  describe "invalid_sensor/2" do
    test "creates an invalid sensor error" do
      error = Error.invalid_sensor("Sensor failed", sensor: SomeSensor)

      assert error.message == "Sensor failed"
      assert error.sensor == SomeSensor
    end
  end

  describe "execution_error/2" do
    test "creates an execution error" do
      error = Error.execution_error("Execution failed", step: :process)

      assert error.message == "Execution failed"
      assert error.details[:step] == :process
    end
  end

  describe "planning_error/2" do
    test "creates a planning error" do
      error = Error.planning_error("Planning failed")

      assert error.message == "Planning failed"
    end
  end

  describe "routing_error/2" do
    test "creates a routing error" do
      error = Error.routing_error("Route not found", target: :agent_1)

      assert error.message == "Route not found"
      assert error.target == :agent_1
    end
  end

  describe "dispatch_error/2" do
    test "creates a dispatch error" do
      error = Error.dispatch_error("Dispatch failed")

      assert error.message == "Dispatch failed"
    end
  end

  describe "timeout/2" do
    test "creates a timeout error" do
      error = Error.timeout("Operation timed out", timeout: 5000)

      assert error.message == "Operation timed out"
      assert error.timeout == 5000
    end
  end

  describe "invalid_async_ref/2" do
    test "creates an invalid async ref error" do
      error = Error.invalid_async_ref("Invalid ref")

      assert error.message == "Invalid ref"
    end
  end

  describe "compensation_error/2" do
    test "creates a compensation error for successful compensation" do
      original = Error.execution_error("Original failure")

      error =
        Error.compensation_error(original,
          compensated: true,
          compensation_result: %{refund: true}
        )

      assert error.compensated == true
      assert error.original_error == original
      assert error.compensation_result == %{refund: true}
    end

    test "creates a compensation error for failed compensation" do
      original = Error.execution_error("Original failure")
      comp_error = Error.internal_error("Compensation failed")

      error =
        Error.compensation_error(original, compensated: false, compensation_error: comp_error)

      assert error.compensated == false
      assert error.compensation_error == comp_error
    end
  end

  describe "config_error/2" do
    test "creates a configuration error" do
      error = Error.config_error("Missing config key")

      assert error.message == "Missing config key"
    end
  end

  describe "internal_server_error/2" do
    test "creates an internal server error" do
      error = Error.internal_server_error("Unexpected error")

      assert error.message == "Unexpected error"
    end
  end

  describe "alias constructors" do
    test "alias constructors produce same error shape as primary ones" do
      aliases = [
        {:bad_request, :validation_error, []},
        {:action_error, :execution_error, []},
        {:timeout_error, :timeout, [timeout: 1000]},
        {:internal_error, :internal_server_error, []}
      ]

      for {alias_fun, primary_fun, opts} <- aliases do
        alias_err = apply(Error, alias_fun, ["msg", opts])
        primary_err = apply(Error, primary_fun, ["msg", opts])

        assert alias_err.__struct__ == primary_err.__struct__,
               "#{alias_fun} should produce same struct as #{primary_fun}"

        assert alias_err.message == primary_err.message
      end
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

  describe "new/4" do
    test "creates errors for all supported types" do
      types = [
        {:invalid_action, %{action: SomeAction}},
        {:invalid_sensor, %{sensor: SomeSensor}},
        {:bad_request, %{}},
        {:validation_error, %{field: :email}},
        {:config_error, %{}},
        {:execution_error, %{}},
        {:planning_error, %{}},
        {:action_error, %{}},
        {:internal_server_error, %{}},
        {:timeout, %{timeout: 5000}},
        {:invalid_async_ref, %{}},
        {:routing_error, %{target: :agent}},
        {:dispatch_error, %{}}
      ]

      for {type, details} <- types do
        error = Error.new(type, "Test message", details)

        assert is_struct(error),
               "Error.new(#{inspect(type)}, ...) should return a struct"

        assert is_binary(error.message),
               "Error for #{inspect(type)} should have a message"
      end
    end

    test "creates compensation_error via new/4" do
      original = Error.execution_error("Original")

      error =
        Error.new(:compensation_error, "Compensation", %{
          original_error: original,
          compensated: true
        })

      assert error.compensated == true
      assert error.original_error == original
    end

    test "creates internal error for unknown type" do
      error = Error.new(:unknown_type, "Unknown", %{})

      assert error.message =~ "Unknown error type"
    end
  end

  describe "to_map/1" do
    test "converts various error types to map" do
      errors = [
        {Error.validation_error("Invalid", field: :email), :validation_error},
        {Error.execution_error("Failed"), :execution_error},
        {Error.timeout("Timed out", timeout: 5000), :timeout},
        {Error.config_error("Missing key"), :config_error},
        {Error.internal_error("Internal"), :internal_server_error}
      ]

      for {error, expected_type} <- errors do
        result = Error.to_map(error)
        assert result.type == expected_type, "#{inspect(error)} should map to #{expected_type}"
        assert is_binary(result.message)
        assert is_list(result.stacktrace)
      end
    end

    test "converts compensation error to map" do
      original = Error.execution_error("Original")
      error = Error.compensation_error(original, compensated: true)
      result = Error.to_map(error)

      assert result.type == :compensation_error
    end

    test "handles unknown struct" do
      result = Error.to_map(%{unknown: "struct"})

      assert result.type == :internal_server_error
    end
  end

  describe "extract_message/1" do
    test "extracts message from various structures" do
      assert Error.extract_message(%{message: %{message: "Nested"}}) == "Nested"
      assert Error.extract_message(%{message: "Direct"}) == "Direct"
      assert Error.extract_message(%{message: nil}) == ""

      inner = struct(Error.InternalError, message: "Struct message")
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
