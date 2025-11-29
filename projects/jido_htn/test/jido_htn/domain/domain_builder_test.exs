defmodule JidoTest.HTN.Domain.BuilderTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  @moduletag :capture_log

  defmodule TestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "root/2" do
    test "marks a task as a root task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.root("task1")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      assert MapSet.member?(domain.root_tasks, "task1")
    end

    test "can mark multiple tasks as root tasks" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.compound("task2", methods: [%{subtasks: ["subtask2"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.primitive("subtask2", {TestAction, []})
        |> Domain.root("task1")
        |> Domain.root("task2")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()

      assert MapSet.member?(domain.root_tasks, "task1")
      assert MapSet.member?(domain.root_tasks, "task2")
    end

    test "raises error when marking non-existent task as root" do
      assert_raise ArgumentError, "Cannot mark 'nonexistent' as root: task not found", fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.root("nonexistent")
        |> Domain.build()
      end
    end

    test "raises error when marking primitive task as root" do
      assert_raise ArgumentError, "Cannot mark 'task1' as root: must be a compound task", fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.root("task1")
        |> Domain.build()
      end
    end
  end

  describe "duplicate task name detection" do
    test "detects duplicate compound task names" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask2"]}])
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task1' already exists in the domain"
    end

    test "detects duplicate primitive task names" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task1' already exists in the domain"
    end

    test "detects compound task with same name as existing primitive" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task1' already exists in the domain"
    end

    test "detects primitive task with same name as existing compound" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [%{subtasks: ["subtask1"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task1' already exists in the domain"
    end

    test "returns error without calling Domain.validate()" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.compound("task1", methods: [])
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task1' already exists in the domain"
    end
  end

  describe "error propagation" do
    test "errors propagate through builder chain" do
      result =
        Domain.new(123)
        |> Domain.compound("task1", methods: [])
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Domain name must be a string"
    end

    test "builder operations after error don't execute" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [])
        |> Domain.compound(:invalid_name, methods: [])
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid task name"
    end

    test "build! raises on error state" do
      assert_raise RuntimeError, ~r/Domain name must be a string/, fn ->
        Domain.new(123)
        |> Domain.build!()
      end
    end

    test "build! raises on list of errors" do
      defmodule FailingValidator do
        def validate(_domain), do: {:error, ["error 1", "error 2"]}
      end

      assert_raise RuntimeError, ~r/error 1\nerror 2/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.build!(custom_validators: [&FailingValidator.validate/1])
      end
    end

    test "build! raises on non-string/non-list error" do
      defmodule StructErrorValidator do
        def validate(_domain), do: {:error, %{reason: "complex error"}}
      end

      assert_raise RuntimeError, ~r/%\{reason: "complex error"\}/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.build!(custom_validators: [&StructErrorValidator.validate/1])
      end
    end
  end

  describe "input validation edge cases" do
    test "compound with invalid task name returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound(:atom_name, methods: [])
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid task name"
    end

    test "primitive with tuple action and params" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, [key: "value"]}, cost: 10)
        |> Domain.build()

      task = Map.get(domain.tasks, "task1")
      assert task.cost == 10
      assert elem(task.task, 1) == [key: "value"]
    end

    test "primitive with simple action atom" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", TestAction, duration: 10)
        |> Domain.build()

      task = Map.get(domain.tasks, "task1")
      assert task.duration == 10
      # When action is passed as atom, it's stored directly in the task tuple
      assert is_atom(elem(task.task, 0))
    end

    test "root with non-string name returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [])
        |> Domain.root(:atom_name)
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid task name"
    end

    test "allow with non-string workflow name returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.allow(:atom_name, TestAction)
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid workflow name"
    end

    test "allow with non-atom module returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.allow("workflow", "not_a_module")
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid workflow module"
    end

    test "callback with non-string name returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback(:atom_name, fn _ -> true end)
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid callback name"
    end

    test "callback with non-function returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("callback1", "not_a_function")
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid callback function"
    end
  end

  describe "method normalization" do
    test "normalizes method with all fields" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1",
          methods: [
            %{
              name: "method1",
              priority: 10,
              conditions: [true, "cond1", fn _ -> true end],
              subtasks: ["task2", "task3"],
              ordering: [{"task2", "task3"}]
            }
          ]
        )
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.primitive("task3", {TestAction, []})
        |> Domain.build()

      task = Map.get(domain.tasks, "task1")
      method = List.first(task.methods)
      assert method.name == "method1"
      assert method.priority == 10
      assert length(method.conditions) == 3
      assert method.subtasks == ["task2", "task3"]
      assert method.ordering == [{"task2", "task3"}]
    end

    test "normalizes method with minimal fields" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1",
          methods: [%{conditions: [], subtasks: []}]
        )
        |> Domain.build()

      task = Map.get(domain.tasks, "task1")
      method = List.first(task.methods)
      assert is_nil(method.name)
      assert is_nil(method.priority)
      assert method.conditions == []
      assert method.subtasks == []
      assert method.ordering == []
    end

    test "normalizes method without conditions key" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1",
          methods: [%{subtasks: ["task2"]}]
        )
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.build()

      task = Map.get(domain.tasks, "task1")
      method = List.first(task.methods)
      assert method.conditions == []
      assert method.subtasks == ["task2"]
    end

    test "handles already-normalized method struct" do
      alias Jido.HTN.Method

      method_struct = %Method{
        name: "pre_normalized",
        priority: 5,
        conditions: [true],
        subtasks: ["task2"],
        ordering: []
      }

      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [method_struct])
        |> Domain.primitive("task2", {TestAction, []})
        |> Domain.build()

      task = Map.get(domain.tasks, "task1")
      method = List.first(task.methods)
      assert method.name == "pre_normalized"
      assert method.priority == 5
    end
  end

  describe "replace/3" do
    alias Jido.HTN.Domain.BuilderHelpers

    test "replaces existing compound task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1", methods: [])
        |> Domain.build()

      new_task = Jido.HTN.CompoundTask.new("task1", [%{subtasks: ["new"]}])
      {:ok, updated} = BuilderHelpers.replace(domain, "task1", new_task)

      task = Map.get(updated.tasks, "task1")
      assert length(task.methods) == 1
    end

    test "replaces existing primitive task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build()

      new_task = Jido.HTN.PrimitiveTask.new("task1", {TestAction, []}, cost: 20)
      {:ok, updated} = BuilderHelpers.replace(domain, "task1", new_task)

      task = Map.get(updated.tasks, "task1")
      assert task.cost == 20
    end

    test "returns error when task not found" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.build()

      new_task = Jido.HTN.PrimitiveTask.new("task1", {TestAction, []})
      result = BuilderHelpers.replace(domain, "task1", new_task)

      assert {:error, "Task 'task1' not found"} = result
    end

    test "returns error for invalid arguments" do
      result = BuilderHelpers.replace("not_a_domain", "task1", "not_a_task")
      assert {:error, "Invalid arguments for replace"} = result
    end
  end

  describe "custom validator integration" do
    defmodule PassingValidator do
      def validate(domain), do: {:ok, domain}
    end

    defmodule TransformingValidator do
      def validate(domain) do
        {:ok, %{domain | name: "Transformed"}}
      end
    end

    defmodule OkValidator do
      def validate(_domain), do: :ok
    end

    defmodule FailingValidator1 do
      def validate(_domain), do: {:error, "Validator 1 failed"}
    end

    defmodule FailingValidator2 do
      def validate(_domain), do: {:error, "Validator 2 failed"}
    end

    test "build with passing custom validator" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build(custom_validators: [&PassingValidator.validate/1])

      assert domain.name == "Test Domain"
    end

    test "build with transforming validator updates domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build(custom_validators: [&TransformingValidator.validate/1])

      assert domain.name == "Transformed"
    end

    test "build with :ok validator continues chain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build(custom_validators: [&OkValidator.validate/1])

      assert domain.name == "Test Domain"
    end

    test "build with failing custom validator returns error" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build(custom_validators: [&FailingValidator1.validate/1])

      assert {:error, "Validator 1 failed"} = result
    end

    test "build with multiple validators stops at first failure" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.build(
          custom_validators: [
            &FailingValidator1.validate/1,
            &FailingValidator2.validate/1
          ]
        )

      assert {:error, "Validator 1 failed"} = result
    end

    test "build with validate: true runs default validation first" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.build(validate: true, custom_validators: [&PassingValidator.validate/1])

      assert {:error, errors} = result
      assert is_list(errors)
    end
  end
end
