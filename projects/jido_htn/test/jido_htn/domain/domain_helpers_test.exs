defmodule JidoTest.HTN.Domain.HelpersTest do
  use ExUnit.Case, async: true

  import Jido.HTN.Domain.Helpers
  @moduletag :capture_log
  describe "merge/1" do
    test "merges changes into a map" do
      original = %{a: 1, b: %{c: 2}}
      changes = %{b: %{d: 3}, e: 4}
      merged = merge(changes).(original)
      assert merged == %{a: 1, b: %{c: 2, d: 3}, e: 4}
    end
  end

  describe "noop/0" do
    test "returns the input unchanged" do
      input = %{a: 1}
      assert noop().(input) == input
    end
  end

  describe "op/3" do
    test "returns an error tuple for undefined workflows" do
      domain = %{allowed_workflows: %{}}

      assert {:error, error_message} = op(domain, "test_op")
      assert error_message =~ "Workflow test_op not allowed in this domain"
    end

    test "returns an ok tuple with a function for defined workflows" do
      mock_module = MockModule
      domain = %{allowed_workflows: %{"test_op" => mock_module}}

      assert {:ok, workflow_func} = op(domain, "test_op")
      assert is_function(workflow_func, 1)
    end
  end

  describe "camel_case/1" do
    test "converts string to camel case" do
      assert camel_case("test_string") == "TestString"
      assert camel_case("already_camel_case") == "AlreadyCamelCase"
    end
  end

  describe "function_to_string/1" do
    test "converts anonymous function to string representation" do
      fun = fn -> :ok end
      assert function_to_string(fun) =~ ~r/&.+\/0/
    end

    test "converts named function reference to string" do
      fun = &String.upcase/1
      result = function_to_string(fun)
      assert result == "&Elixir.String.upcase/1"
    end

    test "converts module tuple with opts to string" do
      result = function_to_string({MyModule, [key: "value"]})
      assert result == "{Elixir.MyModule, [key: \"value\"]}"
    end

    test "handles non-function values with inspect" do
      assert function_to_string("string") == "\"string\""
      assert function_to_string(123) == "123"
      assert function_to_string(true) == "true"
      assert function_to_string(nil) == "nil"
    end

    test "handles multi-arity anonymous functions" do
      fun = fn x, y -> x + y end
      result = function_to_string(fun)
      assert result =~ ~r/&.+\/2/
    end

    test "handles captured local functions" do
      defmodule LocalFunctionTest do
        def local_func(x), do: x * 2

        def get_captured do
          &local_func/1
        end
      end

      fun = LocalFunctionTest.get_captured()
      result = function_to_string(fun)
      assert result =~ ~r/&.+\.local_func\/1/
    end
  end

  describe "op/3 edge cases" do
    test "passes opts to workflow module" do
      defmodule TestWorkflowWithOpts do
        def run(world_state, _state, opts) do
          if Keyword.get(opts, :should_succeed, true) do
            {:ok, Map.put(world_state, :processed, true)}
          else
            {:error, "Failed as requested"}
          end
        end
      end

      domain = %{allowed_workflows: %{"test_workflow" => TestWorkflowWithOpts}}

      assert {:ok, workflow_func} = op(domain, "test_workflow", should_succeed: true)
      assert {:ok, result} = workflow_func.(%{initial: :state})
      assert result.processed == true
    end

    test "handles workflow returning error tuple" do
      defmodule FailingWorkflow do
        def run(_world_state, _state, _opts) do
          {:error, "Workflow failed"}
        end
      end

      domain = %{allowed_workflows: %{"failing" => FailingWorkflow}}

      assert {:ok, workflow_func} = op(domain, "failing")
      assert {:error, "Workflow failed"} = workflow_func.(%{})
    end

    test "handles workflow returning unexpected value" do
      defmodule BadWorkflow do
        def run(_world_state, _state, _opts) do
          :unexpected_return
        end
      end

      domain = %{allowed_workflows: %{"bad" => BadWorkflow}}

      assert {:ok, workflow_func} = op(domain, "bad")
      assert {:error, error} = workflow_func.(%{})
      assert error =~ "Unexpected return from workflow"
      assert error =~ ":unexpected_return"
    end
  end

  describe "merge/1 edge cases" do
    test "handles empty changes" do
      original = %{a: 1, b: 2}
      merged = merge(%{}).(original)
      assert merged == original
    end

    test "handles nested deep merge" do
      original = %{a: %{b: %{c: 1, d: 2}}}
      changes = %{a: %{b: %{c: 3}}}
      merged = merge(changes).(original)
      assert merged == %{a: %{b: %{c: 3, d: 2}}}
    end

    test "handles merging into empty map" do
      changes = %{a: 1, b: 2}
      merged = merge(changes).(%{})
      assert merged == changes
    end
  end

  describe "camel_case/1 edge cases" do
    test "handles strings with special characters" do
      assert camel_case("test-string") == "Test-string"
      assert camel_case("test.string") == "Test.string"
    end

    test "handles single word" do
      assert camel_case("test") == "Test"
    end

    test "handles already capitalized strings" do
      assert camel_case("TestString") == "TestString"
    end

    test "handles empty string" do
      assert camel_case("") == ""
    end
  end
end
