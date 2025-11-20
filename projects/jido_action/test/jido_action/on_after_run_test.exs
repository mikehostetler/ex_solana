defmodule Jido.Action.OnAfterRunTest do
  use ExUnit.Case, async: true

  defmodule PassThroughAction do
    use Jido.Action,
      name: "pass_through",
      description: "Tests default on_after_run behavior",
      schema: []

    @impl true
    def run(_params, _context) do
      {:ok, %{foo: "bar"}}
    end
  end

  defmodule ErrorAction do
    use Jido.Action,
      name: "error_action",
      description: "Tests on_after_run with errors",
      schema: []

    @impl true
    def run(_params, _context) do
      {:error, :some_error}
    end
  end

  defmodule CustomAfterRunAction do
    use Jido.Action,
      name: "custom_after_run",
      description: "Tests custom on_after_run override",
      schema: []

    @impl true
    def run(_params, _context) do
      {:ok, %{value: 42}}
    end

    @impl true
    def on_after_run({:ok, result}) do
      {:ok, Map.put(result, :modified, true)}
    end

    def on_after_run(error), do: error
  end

  describe "default on_after_run/1" do
    test "passes through {:ok, result} unchanged" do
      assert {:ok, %{foo: "bar"}} = PassThroughAction.on_after_run({:ok, %{foo: "bar"}})
    end

    test "passes through {:error, reason} unchanged" do
      assert {:error, :some_error} = ErrorAction.on_after_run({:error, :some_error})
    end

    test "does not double-wrap ok tuples" do
      result = PassThroughAction.run(%{}, %{})
      assert {:ok, %{foo: "bar"}} = result

      # Verify on_after_run doesn't double wrap
      after_run_result = PassThroughAction.on_after_run(result)
      assert {:ok, %{foo: "bar"}} = after_run_result
      refute match?({:ok, {:ok, _}}, after_run_result)
    end
  end

  describe "custom on_after_run/1" do
    test "allows modification of results" do
      result = CustomAfterRunAction.run(%{}, %{})
      assert {:ok, %{value: 42}} = result

      after_run_result = CustomAfterRunAction.on_after_run(result)
      assert {:ok, %{value: 42, modified: true}} = after_run_result
    end

    test "can pass through errors" do
      assert {:error, :test_error} =
               CustomAfterRunAction.on_after_run({:error, :test_error})
    end
  end
end
