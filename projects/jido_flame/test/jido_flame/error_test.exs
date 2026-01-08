defmodule JidoFlame.ErrorTest do
  use ExUnit.Case, async: true

  alias JidoFlame.Error

  describe "validation_error/2" do
    test "creates InvalidInputError with message and field" do
      error = Error.validation_error("Invalid pool", field: :pool)
      assert %Error.InvalidInputError{} = error
      assert error.message == "Invalid pool"
      assert error.field == :pool
    end

    test "creates InvalidInputError with value" do
      error = Error.validation_error("Invalid value", field: :pool, value: nil)
      assert error.value == nil
    end
  end

  describe "config_error/2" do
    test "creates ConfigError" do
      error = Error.config_error("Missing config", key: :flame_pool)
      assert %Error.ConfigError{} = error
      assert error.message == "Missing config"
      assert error.key == :flame_pool
    end
  end

  describe "remote_call_error/2" do
    test "creates RemoteCallError" do
      error = Error.remote_call_error("Call failed", pool: MyPool, cause: :timeout)
      assert %Error.RemoteCallError{} = error
      assert error.pool == MyPool
      assert error.cause == :timeout
    end
  end

  describe "remote_cast_error/2" do
    test "creates RemoteCastError" do
      error = Error.remote_cast_error("Cast failed", pool: MyPool)
      assert %Error.RemoteCastError{} = error
      assert error.pool == MyPool
    end
  end

  describe "remote_agent_error/2" do
    test "creates RemoteAgentError" do
      error =
        Error.remote_agent_error("Spawn failed",
          agent_id: "agent-1",
          tag: :worker,
          cause: :no_pool
        )

      assert %Error.RemoteAgentError{} = error
      assert error.agent_id == "agent-1"
      assert error.tag == :worker
      assert error.cause == :no_pool
    end
  end

  describe "placement_error/2" do
    test "creates PlacementError" do
      error = Error.placement_error("Place failed", pool: MyPool, child_spec: {MyWorker, []})
      assert %Error.PlacementError{} = error
      assert error.pool == MyPool
      assert error.child_spec == {MyWorker, []}
    end
  end

  describe "timeout_error/2" do
    test "creates TimeoutError" do
      error = Error.timeout_error("Timed out", timeout: 5000, operation: :call)
      assert %Error.TimeoutError{} = error
      assert error.timeout == 5000
      assert error.operation == :call
    end
  end

  describe "owner_error/2" do
    test "creates OwnerError" do
      error = Error.owner_error("Owner failed", agent_id: "agent-1", tag: :worker)
      assert %Error.OwnerError{} = error
      assert error.agent_id == "agent-1"
      assert error.tag == :worker
    end
  end

  describe "registry_error/2" do
    test "creates RegistryError" do
      error = Error.registry_error("Registry failed", registry: :agent_registry, key: "agent-1")
      assert %Error.RegistryError{} = error
      assert error.registry == :agent_registry
      assert error.key == "agent-1"
    end
  end

  describe "internal_error/2" do
    test "creates InternalError" do
      error = Error.internal_error("Unexpected error", details: %{reason: :unknown})
      assert %Error.InternalError{} = error
      assert error.message == "Unexpected error"
    end
  end

  describe "error messages" do
    test "InvalidInputError has correct message" do
      error = Error.InvalidInputError.exception(message: "test", field: :foo)
      assert Exception.message(error) == "test"
    end

    test "RemoteCallError has correct message" do
      error = Error.RemoteCallError.exception(message: "call failed")
      assert Exception.message(error) == "call failed"
    end

    test "TimeoutError has correct message" do
      error = Error.TimeoutError.exception(message: "operation timed out")
      assert Exception.message(error) == "operation timed out"
    end

    test "ConfigError has correct message" do
      error = Error.ConfigError.exception(message: "missing key")
      assert Exception.message(error) == "missing key"
    end
  end

  describe "format_zoi_error/1" do
    test "formats Zoi.Error list" do
      errors = [%Zoi.Error{path: [:pool], message: "is required", code: :required, issue: nil}]
      result = Error.format_zoi_error(errors)
      assert is_binary(result)
    end

    test "inspects non-list errors" do
      result = Error.format_zoi_error(:some_error)
      assert result == ":some_error"
    end
  end
end
