defmodule JidoTest.ExecReturnShapeTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec

  @moduletag :capture_log

  describe "strict return shape validation" do
    test "accepts {:ok, map} - happy path" do
      defmodule ValidOkAction do
        use Jido.Action, name: "valid_ok"

        def run(_params, _context), do: {:ok, %{result: "success"}}
      end

      assert {:ok, %{result: "success"}} = Exec.run(ValidOkAction, %{}, %{})
    end

    test "accepts {:ok, map, directive} - happy path with directive" do
      defmodule ValidOkWithDirectiveAction do
        use Jido.Action, name: "valid_ok_directive"

        def run(_params, _context), do: {:ok, %{result: "success"}, %{meta: "data"}}
      end

      assert {:ok, %{result: "success"}, %{meta: "data"}} =
               Exec.run(ValidOkWithDirectiveAction, %{}, %{})
    end

    test "accepts {:error, exception} - happy path error" do
      defmodule ValidErrorAction do
        use Jido.Action, name: "valid_error"

        def run(_params, _context), do: {:error, Error.execution_error("failed")}
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} = Exec.run(ValidErrorAction, %{}, %{})
      end)
    end

    test "accepts {:error, exception, directive} - error with directive" do
      defmodule ValidErrorWithDirectiveAction do
        use Jido.Action, name: "valid_error_directive"

        def run(_params, _context), do: {:error, Error.execution_error("failed"), %{meta: "data"}}
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}, %{meta: "data"}} =
                 Exec.run(ValidErrorWithDirectiveAction, %{}, %{})
      end)
    end

    test "accepts {:error, string} and wraps in execution error" do
      defmodule ValidErrorStringAction do
        use Jido.Action, name: "valid_error_string"

        def run(_params, _context), do: {:error, "something went wrong"}
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: "something went wrong"}} =
                 Exec.run(ValidErrorStringAction, %{}, %{})
      end)
    end

    test "rejects :ok atom - unexpected shape" do
      defmodule AtomOkAction do
        use Jido.Action, name: "atom_ok"

        @dialyzer {:nowarn_function, run: 2}
        def run(_params, _context), do: :ok
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(AtomOkAction, %{}, %{})

        assert message =~ "Unexpected return shape: :ok"
      end)
    end

    test "rejects plain string - unexpected shape" do
      defmodule StringResultAction do
        use Jido.Action, name: "string_result"

        @dialyzer {:nowarn_function, run: 2}
        def run(_params, _context), do: "result"
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(StringResultAction, %{}, %{})

        assert message =~ ~s(Unexpected return shape: "result")
      end)
    end

    test "rejects plain map - unexpected shape" do
      defmodule PlainMapAction do
        use Jido.Action, name: "plain_map"

        @dialyzer {:nowarn_function, run: 2}
        def run(_params, _context), do: %{foo: 1, bar: 2}
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(PlainMapAction, %{}, %{})

        assert message =~ "Unexpected return shape: %{"
        assert message =~ "foo: 1"
        assert message =~ "bar: 2"
      end)
    end

    test "rejects integer - unexpected shape" do
      defmodule IntegerResultAction do
        use Jido.Action, name: "integer_result"

        @dialyzer {:nowarn_function, run: 2}
        def run(_params, _context), do: 42
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(IntegerResultAction, %{}, %{})

        assert message =~ "Unexpected return shape: 42"
      end)
    end

    test "rejects list - unexpected shape" do
      defmodule ListResultAction do
        use Jido.Action, name: "list_result"

        @dialyzer {:nowarn_function, run: 2}
        def run(_params, _context), do: [1, 2, 3]
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(ListResultAction, %{}, %{})

        assert message =~ "Unexpected return shape: [1, 2, 3]"
      end)
    end

    test "output validation only runs on {:ok, result} branch" do
      defmodule OutputValidationAction do
        use Jido.Action,
          name: "output_validation",
          output_schema: [
            required_field: [type: :string, required: true]
          ]

        def run(%{return_type: :ok_valid}, _context) do
          {:ok, %{required_field: "valid"}}
        end

        def run(%{return_type: :ok_invalid}, _context) do
          {:ok, %{wrong_field: "invalid"}}
        end

        def run(%{return_type: :raw_map}, _context) do
          # Raw map should fail before output validation
          %{required_field: "this won't be validated"}
        end
      end

      # Valid output passes validation
      assert {:ok, %{required_field: "valid"}} =
               Exec.run(OutputValidationAction, %{return_type: :ok_valid}, %{})

      # Invalid output fails validation
      capture_log(fn ->
        assert {:error, %Error.InvalidInputError{}} =
                 Exec.run(OutputValidationAction, %{return_type: :ok_invalid}, %{})
      end)

      # Raw map fails with execution error, not validation error
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{message: message}} =
                 Exec.run(OutputValidationAction, %{return_type: :raw_map}, %{})

        assert message =~ "Unexpected return shape"
        refute message =~ "validation"
      end)
    end

    test "error handling unchanged for {:error, reason}" do
      defmodule ErrorHandlingAction do
        use Jido.Action, name: "error_handling"

        def run(%{error_type: :execution}, _context) do
          {:error, Error.execution_error("execution failed")}
        end

        def run(%{error_type: :invalid_input}, _context) do
          {:error, Error.validation_error("validation failed")}
        end

        def run(%{error_type: :timeout}, _context) do
          {:error, Error.timeout_error("timeout")}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ErrorHandlingAction, %{error_type: :execution}, %{})

        assert {:error, %Error.InvalidInputError{}} =
                 Exec.run(ErrorHandlingAction, %{error_type: :invalid_input}, %{})

        assert {:error, %Error.TimeoutError{}} =
                 Exec.run(ErrorHandlingAction, %{error_type: :timeout}, %{})
      end)
    end
  end
end
