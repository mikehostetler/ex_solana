# Testing Guide

**Prerequisites**: [Actions Guide](actions-guide.md) • [Error Handling Guide](error-handling.md)

Comprehensive testing strategies for actions, workflows, error scenarios, and AI integrations using ExUnit and property-based testing.

## Basic Action Testing

### Unit Testing Actions

```elixir
defmodule MyApp.Actions.ProcessUserTest do
  use ExUnit.Case

  alias MyApp.Actions.ProcessUser

  describe "direct run/2 testing" do
    test "processes valid user data" do
      # Direct run/2 calls skip validation - useful for testing action logic
      params = %{
        name: "John Doe",
        email: "john@example.com",
        age: 30
      }
      
      assert {:ok, result} = ProcessUser.run(params, %{})
      assert result.name == "John Doe"
      assert result.email == "john@example.com"
      assert result.processed_at
    end
  end

  describe "testing with Jido.Exec.run/4 (recommended)" do
    test "validates and processes user data" do
      # Jido.Exec.run/4 includes full validation, retries, timeouts
      params = %{
        name: "John Doe",
        email: "john@example.com",
        age: 30
      }
      
      assert {:ok, result} = Jido.Exec.run(ProcessUser, params, %{})
      assert result.name == "John Doe"
    end

    test "rejects invalid parameters via schema validation" do
      params = %{name: "John Doe"}  # missing email
      
      assert {:error, error} = Jido.Exec.run(ProcessUser, params, %{})
      assert is_exception(error)
    end

    test "applies default values from schema" do
      params = %{
        name: "John Doe",
        email: "john@example.com"
        # age not provided, should use default
      }
      
      assert {:ok, result} = Jido.Exec.run(ProcessUser, params, %{})
      assert result.age == 18  # default value
    end
  end

  describe "validate_params/1 testing" do
    test "validates parameters in isolation" do
      valid_params = %{name: "John", email: "john@example.com", age: 30}
      assert {:ok, validated} = ProcessUser.validate_params(valid_params)
      assert validated.name == "John"
    end

    test "returns error for invalid parameters" do
      invalid_params = %{name: "John"}  # missing required email
      assert {:error, _} = ProcessUser.validate_params(invalid_params)
    end
  end

  describe "context handling" do
    test "uses context for business logic" do
      params = %{
        name: "John Doe",
        email: "john@example.com",
        age: 30
      }
      
      context = %{user_id: "admin_123", role: :admin}
      
      assert {:ok, result} = Jido.Exec.run(ProcessUser, params, context)
      assert result.processed_by == "admin_123"
    end

    test "action receives metadata in context" do
      # Jido.Exec.run injects action_metadata into context
      params = %{name: "John", email: "john@example.com", age: 30}
      
      assert {:ok, result} = Jido.Exec.run(ProcessUser, params, %{})
      # Action can access context.action_metadata for name, description, etc.
    end
  end
end
```

### Testing Lifecycle Hooks

```elixir
defmodule MyApp.Actions.LifecycleActionTest do
  use ExUnit.Case

  # Test action with all lifecycle hooks
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      schema: [input: [type: :string, required: true]]

    @impl true
    def on_before_validate_params(params) do
      # Add test marker before validation
      {:ok, Map.put(params, :preprocessed, true)}
    end

    @impl true
    def run(params, _context) do
      {:ok, %{result: params.input, preprocessed: params.preprocessed}}
    end

    # Note: on_after_run receives the full result tuple, not just the result map
    @impl true
    def on_after_run({:ok, result}) do
      {:ok, Map.put(result, :postprocessed, true)}
    end
    def on_after_run({:error, _} = error), do: error

    @impl true
    def on_error(_params, _error, _context, _opts) do
      {:ok, %{error_handled: true}}
    end
  end

  test "lifecycle hooks are called via Exec.run" do
    # Note: Lifecycle hooks are invoked through Jido.Exec.run, not direct run/2 calls
    assert {:ok, result} = Jido.Exec.run(TestAction, %{input: "test"}, %{})
    
    # Check preprocessing happened
    assert result.preprocessed == true
    
    # Check post-processing happened  
    assert result.postprocessed == true
    
    # Check main logic ran
    assert result.result == "test"
  end

  test "validate_params/1 can be tested directly" do
    # Test parameter validation in isolation
    assert {:ok, validated} = TestAction.validate_params(%{input: "test"})
    assert validated.input == "test"
    assert validated.preprocessed == true  # on_before_validate_params was called

    # Test validation failure
    assert {:error, _} = TestAction.validate_params(%{wrong_key: "value"})
  end
end
```

## Testing with Execution Engine

### Testing Timeouts

```elixir
defmodule MyApp.Actions.TimeoutTest do
  use ExUnit.Case

  defmodule SlowAction do
    use Jido.Action,
      name: "slow_action",
      schema: [delay_ms: [type: :integer, default: 1000]]

    @impl true
    def run(%{delay_ms: delay}, _context) do
      Process.sleep(delay)
      {:ok, %{completed_after: delay}}
    end
  end

  test "respects timeout configuration" do
    # Should complete within timeout
    assert {:ok, result} = Jido.Exec.run(
      SlowAction,
      %{delay_ms: 100},
      %{},
      timeout: 500
    )
    
    assert result.completed_after == 100
  end

  test "times out when execution exceeds limit" do
    assert {:error, error} = Jido.Exec.run(
      SlowAction,
      %{delay_ms: 1000},
      %{},
      timeout: 100
    )
    
    # Timeout errors are Jido.Action.Error.TimeoutError
    assert error.__struct__ == Jido.Action.Error.TimeoutError
    assert Exception.message(error) =~ "timed out"
  end
end
```

### Testing Retries

```elixir
defmodule MyApp.Actions.RetryTest do
  use ExUnit.Case

  # Use an ETS table to track retry attempts
  defmodule FlakyAction do
    use Jido.Action,
      name: "flaky_action",
      schema: [
        fail_count: [type: :integer, default: 0],
        table_name: [type: :atom, required: true]
      ]

    @impl true
    def run(%{fail_count: fail_count, table_name: table_name}, _context) do
      # Track attempts using ETS
      attempt = :ets.update_counter(table_name, :attempts, 1, {:attempts, 0})
      
      if attempt <= fail_count do
        {:error, Jido.Action.Error.execution_error("Simulated failure")}
      else
        {:ok, %{succeeded_on_attempt: attempt}}
      end
    end
  end

  setup do
    table = :ets.new(:retry_test, [:set, :public])
    on_exit(fn -> :ets.delete(table) end)
    {:ok, table: table}
  end

  test "retries on failure and eventually succeeds", %{table: table} do
    # Should fail twice, succeed on third attempt
    assert {:ok, result} = Jido.Exec.run(
      FlakyAction,
      %{fail_count: 2, table_name: table},
      %{},
      max_retries: 3,
      backoff: 10  # Fast retries for tests
    )
    
    assert result.succeeded_on_attempt == 3
  end

  test "gives up after max retries", %{table: table} do
    assert {:error, error} = Jido.Exec.run(
      FlakyAction,
      %{fail_count: 10, table_name: table},  # Always fails
      %{},
      max_retries: 2,
      backoff: 10
    )
    
    assert is_exception(error)
    assert Exception.message(error) =~ "Simulated failure"
  end
end
```

## Testing Workflows

### Testing Chains

```elixir
defmodule MyApp.Workflows.ChainTest do
  use ExUnit.Case

  defmodule Step1 do
    use Jido.Action,
      name: "step1",
      schema: [input: [type: :string, required: true]]

    @impl true
    def run(%{input: input}, _context) do
      {:ok, %{step1_output: "processed_#{input}"}}
    end
  end

  defmodule Step2 do
    use Jido.Action,
      name: "step2",
      schema: [step1_output: [type: :string, required: true]]

    @impl true
    def run(%{step1_output: input}, _context) do
      {:ok, %{final_result: "final_#{input}"}}
    end
  end

  test "chain executes steps in sequence" do
    # Note: context is passed as a keyword option, not a 3rd positional arg
    {:ok, result} = Jido.Exec.Chain.chain(
      [Step1, Step2],
      %{input: "test"},
      context: %{}
    )
    
    # Chain merges results, so both step outputs are available
    assert result.final_result == "final_processed_test"
    assert result.step1_output == "processed_test"
  end

  test "chain stops on first error" do
    defmodule FailingStep do
      use Jido.Action,
        name: "failing_step"
      
      @impl true
      def run(_params, _context) do
        {:error, Jido.Action.Error.execution_error("Step failed")}
      end
    end

    # Chain returns {:error, error} on failure (no partial results tuple)
    assert {:error, error} = Jido.Exec.Chain.chain(
      [Step1, FailingStep, Step2],
      %{input: "test"},
      context: %{}
    )
    
    assert Exception.message(error) =~ "Step failed"
  end

  test "chain with action-specific parameters" do
    # Actions can receive additional params via tuple syntax
    {:ok, result} = Jido.Exec.Chain.chain(
      [
        Step1,
        {Step2, %{extra_param: "value"}}
      ],
      %{input: "test"}
    )
    
    assert result.final_result == "final_processed_test"
  end

  test "async chain execution" do
    task = Jido.Exec.Chain.chain(
      [Step1, Step2],
      %{input: "test"},
      async: true
    )
    
    assert %Task{} = task
    assert {:ok, result} = Task.await(task)
    assert result.final_result == "final_processed_test"
  end
end
```

### Testing Plans

```elixir
defmodule MyApp.Workflows.PlanTest do
  use ExUnit.Case

  # Define test actions
  defmodule InputAction do
    use Jido.Action, name: "input_action"
    @impl true
    def run(params, _context), do: {:ok, Map.put(params, :input_processed, true)}
  end

  defmodule ProcessA do
    use Jido.Action, name: "process_a"
    @impl true
    def run(params, _context), do: {:ok, Map.put(params, :process_a_done, true)}
  end

  defmodule ProcessB do
    use Jido.Action, name: "process_b"
    @impl true
    def run(params, _context), do: {:ok, Map.put(params, :process_b_done, true)}
  end

  defmodule MergeAction do
    use Jido.Action, name: "merge_action"
    @impl true
    def run(params, _context), do: {:ok, Map.put(params, :merged, true)}
  end

  describe "plan execution" do
    test "executes phases in correct order" do
      # Build a plan with dependencies
      plan = Jido.Plan.new()
      |> Jido.Plan.add("input", InputAction, %{}, [])
      |> Jido.Plan.add("process_a", ProcessA, %{}, depends_on: ["input"])
      |> Jido.Plan.add("process_b", ProcessB, %{}, depends_on: ["input"])
      |> Jido.Plan.add("merge", MergeAction, %{}, depends_on: ["process_a", "process_b"])
      
      # Execute the plan
      {:ok, results} = Jido.Exec.run(
        Jido.Tools.ActionPlan,
        %{plan: plan, initial_data: %{data: "test"}},
        %{}
      )
      
      # Verify all steps executed
      assert Map.has_key?(results, "input")
      assert Map.has_key?(results, "process_a")
      assert Map.has_key?(results, "process_b")
      assert Map.has_key?(results, "merge")
    end

    test "handles dependency failures" do
      defmodule FailingAction do
        use Jido.Action, name: "failing_action"
        @impl true
        def run(_params, _context) do
          {:error, Jido.Action.Error.execution_error("Intentional failure")}
        end
      end

      defmodule SuccessAction do
        use Jido.Action, name: "success_action"
        @impl true
        def run(params, _context), do: {:ok, params}
      end

      plan = Jido.Plan.new()
      |> Jido.Plan.add("step1", SuccessAction, %{}, [])
      |> Jido.Plan.add("step2", FailingAction, %{}, depends_on: ["step1"])
      |> Jido.Plan.add("step3", SuccessAction, %{}, depends_on: ["step2"])
      
      assert {:error, error} = Jido.Exec.run(
        Jido.Tools.ActionPlan,
        %{plan: plan, initial_data: %{}},
        %{}
      )
      
      assert is_exception(error)
    end
  end
end
```

## Property-Based Testing

### Using StreamData

```elixir
defmodule MyApp.Actions.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias MyApp.Actions.Calculator

  property "addition is commutative" do
    check all a <- integer(),
              b <- integer() do
      {:ok, result1} = Calculator.Add.run(%{value: a, amount: b}, %{})
      {:ok, result2} = Calculator.Add.run(%{value: b, amount: a}, %{})
      
      assert result1.result == result2.result
    end
  end

  property "string processing handles all valid inputs" do
    check all input <- string(:alphanumeric, min_length: 1, max_length: 100) do
      case MyApp.Actions.ProcessString.run(%{text: input}, %{}) do
        {:ok, result} ->
          # Result should always be a string
          assert is_binary(result.processed)
          # Result should not be empty
          assert String.length(result.processed) > 0
          
        {:error, error} ->
          # If it fails, should be a validation error
          assert error.type == :validation_error
      end
    end
  end

  property "user age validation" do
    check all age <- integer() do
      case MyApp.Actions.ValidateUser.run(%{
        name: "Test User",
        email: "test@example.com", 
        age: age
      }, %{}) do
        {:ok, result} when age >= 13 and age <= 150 ->
          assert result.age == age
          
        {:error, error} when age < 13 or age > 150 ->
          assert error.type == :validation_error
          assert error.message =~ "age"
      end
    end
  end
end
```

## Testing Error Scenarios

### Testing Error Types

```elixir
defmodule MyApp.Actions.ErrorHandlingTest do
  use ExUnit.Case

  # Error types in Jido.Action.Error:
  # - InvalidInputError - validation failures
  # - ExecutionFailureError - action execution failures
  # - TimeoutError - timeout exceeded
  # - ConfigurationError - invalid action configuration
  # - InternalError - unexpected internal errors
  # - UnknownError - fallback for unclassified errors

  alias Jido.Action.Error

  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      schema: [
        name: [type: :string, required: true],
        age: [type: :integer]
      ]

    @impl true
    def run(%{name: name}, _context), do: {:ok, %{name: name}}
  end

  describe "validation errors" do
    test "missing required parameter" do
      assert {:error, error} = Jido.Exec.run(TestAction, %{}, %{})
      assert error.__struct__ == Error.InvalidInputError
      assert Exception.message(error) =~ "name"
    end

    test "invalid parameter type" do
      assert {:error, error} = Jido.Exec.run(TestAction, %{name: "John", age: "not_a_number"}, %{})
      assert error.__struct__ == Error.InvalidInputError
    end

    test "test validate_params/1 directly" do
      assert {:error, msg} = TestAction.validate_params(%{})
      assert is_binary(msg)
      assert msg =~ "name"
    end
  end

  describe "execution errors" do
    defmodule FailingAction do
      use Jido.Action, name: "failing_action"
      @impl true
      def run(_params, _context) do
        {:error, Error.execution_error("Service unavailable")}
      end
    end

    test "action returns execution error" do
      assert {:error, error} = Jido.Exec.run(FailingAction, %{}, %{})
      assert error.__struct__ == Error.ExecutionFailureError
      assert Exception.message(error) =~ "Service unavailable"
    end

    test "action raises exception" do
      defmodule RaisingAction do
        use Jido.Action, name: "raising_action"
        @impl true
        def run(_params, _context), do: raise "Unexpected error"
      end

      assert {:error, error} = Jido.Exec.run(RaisingAction, %{}, %{})
      assert error.__struct__ == Error.ExecutionFailureError
      assert Exception.message(error) =~ "Unexpected error"
    end
  end

  describe "compensation" do
    defmodule CompensatingAction do
      use Jido.Action,
        name: "compensating_action",
        compensation: [enabled: true]
      
      @impl true
      def run(%{should_fail: true}, _context) do
        {:error, Error.execution_error("Intentional failure")}
      end
      def run(_params, _context), do: {:ok, %{result: "success"}}

      @impl true
      def on_error(params, error, _context, _opts) do
        {:ok, Map.merge(params, %{compensated: true, original_error: error})}
      end
    end

    test "compensation runs on error when enabled" do
      assert {:error, error} = Jido.Exec.run(
        CompensatingAction,
        %{should_fail: true},
        %{},
        timeout: 100
      )
      
      # Error contains compensation details
      assert error.details.compensated == true
      assert error.details.original_error != nil
    end
  end
end
```

## Testing AI Integration

### Testing Tool Conversion

```elixir
defmodule MyApp.Actions.AIIntegrationTest do
  use ExUnit.Case

  # Define a test action for AI integration
  defmodule SearchUsers do
    use Jido.Action,
      name: "search_users",
      description: "Search for users by query",
      schema: [
        query: [type: :string, required: true, doc: "Search query"],
        limit: [type: :integer, default: 10, doc: "Maximum results"]
      ]

    @impl true
    def run(%{query: query, limit: limit}, _context) do
      # Mock search results
      {:ok, %{users: [%{email: query}], count: 1}}
    end
  end

  test "action converts to valid tool definition" do
    tool_def = SearchUsers.to_tool()
    
    # Tool definition structure
    assert is_binary(tool_def.name)
    assert tool_def.name == "search_users"
    assert is_binary(tool_def.description)
    assert is_function(tool_def.function, 2)
    assert is_map(tool_def.parameters_schema)
    
    # Parameters schema follows JSON Schema format
    params = tool_def.parameters_schema
    assert params["type"] == "object"
    assert is_map(params["properties"])
  end

  test "tool execution from AI parameters" do
    # AI systems typically send string keys
    ai_params = %{
      "query" => "john@example.com",
      "limit" => 5
    }
    
    # execute_action handles string-to-atom key conversion
    {:ok, json_result} = Jido.Action.Tool.execute_action(
      SearchUsers,
      ai_params,
      %{}
    )
    
    # Result is JSON-encoded for AI consumption
    result = Jason.decode!(json_result)
    assert is_list(result["users"])
  end

  test "handles invalid AI parameters" do
    invalid_params = %{
      # Missing required "query" parameter
      "limit" => "not_a_number"
    }
    
    assert {:error, json_error} = Jido.Action.Tool.execute_action(
      SearchUsers,
      invalid_params,
      %{}
    )
    
    # Error is JSON-encoded
    error = Jason.decode!(json_error)
    assert Map.has_key?(error, "error")
  end
end
```

## Testing Helpers and Utilities

### Custom Test Helpers

```elixir
defmodule MyApp.TestHelpers do
  @moduledoc "Utilities for testing actions"

  import ExUnit.Assertions

  def assert_success(result) do
    case result do
      {:ok, data} -> data
      {:ok, data, _directive} -> data
      {:error, error} -> 
        flunk("Expected success, got error: #{inspect(error)}")
    end
  end

  def assert_error(result) do
    case result do
      {:error, error} -> error
      {:error, error, _directive} -> error
      {:ok, data} ->
        flunk("Expected error, got success: #{inspect(data)}")
    end
  end

  def assert_exception_type(result, expected_module) do
    error = assert_error(result)
    assert error.__struct__ == expected_module,
      "Expected #{inspect(expected_module)}, got #{inspect(error.__struct__)}"
    error
  end

  def with_timeout(action, params, context, timeout_ms) do
    Jido.Exec.run(action, params, context, timeout: timeout_ms)
  end

  def run_async_and_wait(action, params, context, timeout_ms \\ 5000) do
    async_ref = Jido.Exec.run_async(action, params, context)
    Jido.Exec.await(async_ref, timeout_ms)
  end
end

# Use in tests
defmodule MyApp.Actions.SomeTest do
  use ExUnit.Case
  import MyApp.TestHelpers

  # Assume MyAction is defined elsewhere
  alias MyApp.Actions.MyAction

  test "action succeeds via Exec.run" do
    result = assert_success(Jido.Exec.run(MyAction, %{valid: "params"}, %{}))
    assert result.processed == true
  end

  test "action fails with validation error" do
    error = assert_error(Jido.Exec.run(MyAction, %{}, %{}))
    assert Exception.message(error) =~ "required"
  end

  test "action fails with specific error type" do
    error = assert_exception_type(
      Jido.Exec.run(MyAction, %{}, %{}),
      Jido.Action.Error.InvalidInputError
    )
    assert Exception.message(error) =~ "required"
  end

  test "async action execution" do
    result = run_async_and_wait(MyAction, %{valid: "params"}, %{})
    assert {:ok, data} = result
    assert data.processed == true
  end
end
```

### Test Configuration

```elixir
# test/support/test_config.ex
defmodule MyApp.TestConfig do
  def setup_test_environment do
    # Configure for fast tests
    Application.put_env(:jido_action, :default_timeout, 1_000)
    Application.put_env(:jido_action, :default_max_retries, 0)
    Application.put_env(:jido_action, :telemetry_enabled, false)
    
    # Mock external dependencies
    Application.put_env(:my_app, :external_api_base_url, "http://localhost:4002")
    Application.put_env(:my_app, :use_real_database, false)
  end

  def cleanup_test_environment do
    # Cleanup any test data
    File.rm_rf("/tmp/test_files")
    :ets.delete_all_objects(:test_cache)
  end
end

# In test_helper.exs
MyApp.TestConfig.setup_test_environment()

ExUnit.configure(exclude: [:integration, :slow])
ExUnit.start()
```

## Integration Testing

### Testing with External Services

```elixir
defmodule MyApp.Actions.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  setup_all do
    # Start test server or ensure external services are available
    {:ok, server} = start_test_server(port: 4002)
    on_exit(fn -> stop_test_server(server) end)
    %{server: server}
  end

  test "real HTTP API integration" do
    {:ok, result} = MyApp.Actions.FetchUserProfile.run(%{
      user_id: "test_user_123"
    }, %{})
    
    assert result.user_id == "test_user_123"
    assert is_binary(result.name)
    assert is_binary(result.email)
  end

  test "database integration" do
    # Use test database
    {:ok, result} = MyApp.Actions.CreateUser.run(%{
      name: "Test User",
      email: "test@example.com"
    }, %{})
    
    # Verify user was actually created in database
    user = MyApp.Repo.get_by(User, email: "test@example.com")
    assert user.name == "Test User"
    
    # Cleanup
    MyApp.Repo.delete(user)
  end
end
```

## Best Practices

### Test Organization
- **Unit Tests**: Test actions in isolation
- **Integration Tests**: Test with real external dependencies
- **Property Tests**: Test with generated inputs
- **Error Tests**: Test all error scenarios

### Test Data
- **Fixtures**: Use consistent test data
- **Factories**: Generate test data programmatically
- **Mocking**: Mock external dependencies in unit tests
- **Cleanup**: Clean up test data after tests

### Performance
- **Fast Tests**: Keep unit tests fast (< 100ms)
- **Parallel Execution**: Run tests in parallel when possible
- **Selective Running**: Tag slow tests for selective execution
- **Resource Management**: Avoid resource leaks in tests

### Coverage
- **Happy Path**: Test successful execution
- **Error Cases**: Test all error conditions
- **Edge Cases**: Test boundary conditions
- **Lifecycle Hooks**: Test all lifecycle callbacks

## Next Steps

**→ [FAQ](faq.md)** - Common testing questions and solutions  
**→ [Configuration Guide](configuration.md)** - Test configuration  
**→ [Security Guide](security.md)** - Security testing

---
← [AI Integration](ai-integration.md) | **Next: [FAQ](faq.md)** →
