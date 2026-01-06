defmodule JidoTest.HTN.DomainValidateTest do
  use ExUnit.Case, async: true

  # alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  # alias Jido.HTN.Method
  # alias Jido.HTN.PrimitiveTask
  @moduletag :capture_log
  defmodule TestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  defmodule AnotherTestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "validate/1" do
    test "validates a correct domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects duplicate task names" do
      # Note: The builder now catches duplicate names before build(), so this test
      # verifies that duplicate detection happens during building, not validation
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task", {TestAction, []})
        |> Domain.compound("task", methods: [])
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task' already exists in the domain"
    end

    test "detects undefined subtasks" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["undefined_subtask"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Subtask 'undefined_subtask' does not refer to a valid task"
    end

    test "detects disallowed actions" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task", {TestAction, []})
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain must contain at least one allowed workflow"
    end

    test "detects duplicate callbacks" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("callback", fn _ -> true end)
        |> Domain.callback("callback", fn _ -> false end)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain must contain at least one task"
    end

    # test "detects invalid primitive task structure" do
    #   result =
    #     "Test Domain"
    #     |> Domain.new()
    #     |> Domain.primitive("task", {"not_a_module", []})
    #     |> Domain.allow("not_a_module", TestAction)
    #     |> Domain.build()
    #     |> Domain.validate()

    #   assert {:error, error_message} = result
    #   assert error_message =~ "Invalid action: \"not_a_module\""
    # end

    test "validates a domain with multiple tasks and workflows" do
      {:ok, domain} =
        "Complex Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask1", "subtask2"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.primitive("subtask2", {AnotherTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects missing root task" do
      result =
        "No Root Domain"
        |> Domain.new()
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain must have at least one root task"
    end

    test "validates naming conventions" do
      result =
        "Invalid Names Domain"
        |> Domain.new()
        |> Domain.compound("Root", methods: [%{subtasks: ["Sub_Task"]}])
        |> Domain.primitive("Sub_Task", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("Root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Invalid names found: Root, Sub_Task"
    end

    test "detects invalid callback signatures" do
      result =
        "Invalid Callback Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("invalid_callback", fn _, _ -> true end)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid callback function"
    end

    test "validates a domain with callbacks" do
      {:ok, domain} =
        "Callback Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("valid_callback", fn _ -> true end)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects methods without subtasks" do
      result =
        "Empty Method Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: []}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Compound task 'root' has methods without subtasks"
    end

    test "validates a domain with multiple compound tasks" do
      {:ok, domain} =
        "Multi-Compound Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask1", "compound2"]}])
        |> Domain.compound("compound2", methods: [%{subtasks: ["subtask2"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.primitive("subtask2", {AnotherTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects name conflicts between tasks and callbacks" do
      result =
        "Conflict Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["conflict"]}])
        |> Domain.primitive("conflict", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("conflict", fn _ -> true end)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain contains duplicate names: conflict"
    end

    test "validates cost and duration in primitive tasks" do
      # Test valid cost and duration
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, cost: 10, duration: 1000)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)

      # Test negative cost
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, cost: -1)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Cost must be non-negative"

      # Test negative duration
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, duration: -1)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Duration must be non-negative"

      # Test invalid cost type - Zoi now validates at construction time
      assert_raise ArgumentError, ~r/cost|Invalid PrimitiveTask/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, cost: "invalid")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
      end

      # Test invalid duration type - Zoi now validates at construction time
      assert_raise ArgumentError, ~r/duration|Invalid PrimitiveTask/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, duration: "invalid")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
      end
    end

    test "validates costs and durations" do
      # Test invalid cost
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: -1)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, errors} = result

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Cost must be non-negative")
             )

      # Test invalid duration
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, duration: -1000)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, errors} = result

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Duration must be non-negative")
             )

      # Test both invalid
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: -1, duration: -1000)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, errors} = result

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Cost must be non-negative")
             )

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Duration must be non-negative")
             )

      # Test valid values
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: 0, duration: 0)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert :ok = result
    end

    test "detects callback with invalid return type that raises" do
      # Tests the rescue branch in valid_callback_return?
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("raising_callback", fn _ -> raise "error" end)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Callback 'raising_callback' does not return a boolean or map"
    end

    test "detects callback with non-boolean/non-map return value" do
      # Tests valid_callback_return? with invalid return type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("string_callback", fn _ -> "invalid" end)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Callback 'string_callback' does not return a boolean or map"
    end

    test "validates subtasks with map-based methods having undefined references" do
      # Tests map-based method structure with invalid subtasks
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["undefined1", "undefined2"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate(verbose: true)

      assert {:error, errors} = result
      assert Enum.any?(errors, &(&1 =~ "Subtask 'undefined1' does not refer to a valid task"))
    end

    test "collects multiple disallowed action errors in verbose mode" do
      # Tests error accumulation in validate_allowed_workflows
      domain = %Jido.HTN.Domain{
        name: "Multiple Invalid Actions",
        tasks: %{
          "root" => %Jido.HTN.CompoundTask{
            name: "root",
            methods: [%Jido.HTN.Method{name: "m1", subtasks: ["task1", "task2"]}]
          },
          "task1" => %Jido.HTN.PrimitiveTask{name: "task1", task: {UnallowedAction1, []}},
          "task2" => %Jido.HTN.PrimitiveTask{name: "task2", task: {UnallowedAction2, []}}
        },
        allowed_workflows: %{},
        callbacks: %{},
        root_tasks: MapSet.new(["root"])
      }

      result = Jido.HTN.Domain.ValidationHelpers.validate(domain, verbose: true)

      assert {:error, errors} = result
      assert Enum.any?(errors, &(&1 =~ "Domain must contain at least one allowed workflow"))
    end

    test "validates non-domain input types" do
      # Tests the catch-all validation clause for invalid input
      result = Jido.HTN.Domain.ValidationHelpers.validate("not a domain", [])
      assert {:error, "Invalid domain structure"} = result
    end

    test "detects when root task is not defined in tasks map" do
      # Manually construct a domain with invalid root task reference
      domain = %Jido.HTN.Domain{
        name: "Invalid Root Domain",
        tasks: %{
          "task1" => %Jido.HTN.CompoundTask{
            name: "task1",
            methods: [%Jido.HTN.Method{name: "method1", subtasks: ["subtask"]}]
          },
          "subtask" => %Jido.HTN.PrimitiveTask{
            name: "subtask",
            task: {TestAction, []}
          }
        },
        allowed_workflows: %{"TestAction" => TestAction},
        callbacks: %{},
        root_tasks: MapSet.new(["nonexistent_root"])
      }

      result = Domain.validate(domain)

      assert {:error, [error]} = result
      assert error =~ "Some root tasks are not defined: nonexistent_root"
    end

    test "detects when root task is primitive instead of compound" do
      # Tests the branch checking if root tasks are compound tasks
      domain = %Jido.HTN.Domain{
        name: "Invalid Root Type Domain",
        tasks: %{
          "root" => %Jido.HTN.PrimitiveTask{
            name: "root",
            task: {TestAction, []}
          }
        },
        allowed_workflows: %{"TestAction" => TestAction},
        callbacks: %{},
        root_tasks: MapSet.new(["root"])
      }

      result = Domain.validate(domain)

      assert {:error, [error]} = result
      assert error =~ "All root tasks must be compound tasks"
    end

    test "validates scheduling constraints" do
      # Test valid constraints
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: 1000, latest_end_time: 2000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)

      # Test invalid earliest_start_time type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: "1000"}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': earliest_start_time must be an integer"

      # Test invalid latest_end_time type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{latest_end_time: "2000"}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': latest_end_time must be an integer"

      # Test negative earliest_start_time
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: -1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result

      assert error =~
               "Invalid task structure for 'task1': earliest_start_time must be non-negative"

      # Test negative latest_end_time
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{latest_end_time: -2000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': latest_end_time must be non-negative"

      # Test earliest_start_time > latest_end_time
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: 2000, latest_end_time: 1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result

      assert error =~
               "Invalid task structure for 'task1': earliest_start_time cannot be greater than latest_end_time"

      # Test invalid constraint keys
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{invalid_key: 1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result

      assert error =~
               "Invalid task structure for 'task1': scheduling_constraints can only contain earliest_start_time and latest_end_time"

      # Test non-map constraints - Zoi now validates at construction time
      assert_raise ArgumentError, ~r/scheduling_constraints|Invalid PrimitiveTask/, fn ->
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, scheduling_constraints: "invalid")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
      end
    end
  end

  describe "validate/2 with verbose mode" do
    test "returns only first error in default mode" do
      result =
        "Multiple Errors Domain"
        |> Domain.new()
        |> Domain.compound("Root", methods: [%{subtasks: ["undefined_task"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("Root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Subtask 'undefined_task' does not refer to a valid task"
    end

    test "returns all errors in verbose mode" do
      result =
        "Multiple Errors Domain"
        |> Domain.new()
        |> Domain.compound("Root", methods: [%{subtasks: ["undefined_task"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("Root")
        |> Domain.build()
        |> Domain.validate(verbose: true)

      assert {:error, errors} = result
      assert length(errors) > 1
      assert Enum.any?(errors, &(&1 =~ "Invalid names found: Root"))
      assert Enum.any?(errors, &(&1 =~ "Subtask 'undefined_task' does not refer to a valid task"))
    end

    test "collects multiple validation errors across different validators" do
      result =
        "Many Issues Domain"
        |> Domain.new()
        |> Domain.compound("BadName123", methods: [%{subtasks: []}])
        |> Domain.compound("Another_Bad", methods: [%{subtasks: ["missing"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("BadName123")
        |> Domain.build()
        |> Domain.validate(verbose: true)

      assert {:error, errors} = result
      assert length(errors) > 1
      assert Enum.any?(errors, &(&1 =~ "Invalid names found"))
      assert Enum.any?(errors, &(&1 =~ "methods without subtasks"))
      assert Enum.any?(errors, &(&1 =~ "Subtask 'missing' does not refer to a valid task"))
    end

    test "collects errors from cost and duration validation" do
      # With Zoi, type errors are caught at build time, not validation time
      # This test now validates that negative values are caught by domain validation
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: -5, duration: -100)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate(verbose: true)

      assert {:error, errors} = result
      assert length(errors) >= 2

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Cost must be non-negative")
             )

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Duration must be non-negative")
             )
    end

    test "returns :ok when domain is valid in both modes" do
      {:ok, domain} =
        "Valid Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
      assert :ok = Domain.validate(domain, verbose: true)
    end

    test "collects scheduling constraint errors with other validation errors" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("Root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: 2000, latest_end_time: 1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("Root")
        |> Domain.build()
        |> Domain.validate(verbose: true)

      assert {:error, errors} = result
      assert length(errors) >= 2
      assert Enum.any?(errors, &(&1 =~ "Invalid names found: Root"))

      assert Enum.any?(
               errors,
               &(&1 =~ "earliest_start_time cannot be greater than latest_end_time")
             )
    end

    test "verbose mode collects errors from missing root task and other issues" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("Invalid_Name", methods: [%{subtasks: ["undefined"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate(verbose: true)

      assert {:error, errors} = result
      assert length(errors) >= 3
      assert Enum.any?(errors, &(&1 =~ "Domain must have at least one root task"))
      assert Enum.any?(errors, &(&1 =~ "Invalid names found: Invalid_Name"))
      assert Enum.any?(errors, &(&1 =~ "Subtask 'undefined' does not refer to a valid task"))
    end
  end
end
