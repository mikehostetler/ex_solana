defmodule TestAction do
  @moduledoc false
  def run(_, _, _), do: {:ok, %{}}
end

defmodule TestConditions do
  @moduledoc false
  def check_condition1(state), do: Map.get(state, :condition1, false)
  def check_condition2(state), do: Map.get(state, :condition2, false)
  def check_precondition1(state), do: Map.get(state, :precondition1, false)
  def check_precondition2(state), do: Map.get(state, :precondition2, false)
  def apply_effect1(state), do: Map.put(state, :effect1, true)
  def apply_effect2(state), do: Map.put(state, :effect2, true)
  def apply_expected1(state), do: Map.put(state, :expected1, true)
  def apply_expected2(state), do: Map.put(state, :expected2, true)
  def on_start(domain), do: {:ok, domain}
  def on_complete(domain), do: {:ok, domain}
end

defmodule Jido.HTN.SerializerTest do
  use ExUnit.Case
  alias Jido.HTN.{Domain, CompoundTask, PrimitiveTask, Method, Domain.Serializer}

  describe "domain serialization" do
    test "successfully serializes and deserializes a complex domain" do
      # Create a test domain with various task types and references
      domain = create_test_domain()

      # Serialize the domain
      serialized = Serializer.serialize(domain)

      # Verify the serialized string contains expected content
      assert serialized =~ "test_domain"
      assert serialized =~ "root_task"
      assert serialized =~ "subtask1"
      assert serialized =~ "subtask2"
      assert serialized =~ "name"

      # Deserialize the domain
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify the deserialized domain matches the original
      assert deserialized_domain.name == domain.name
      assert deserialized_domain.root_tasks == domain.root_tasks
      assert map_size(deserialized_domain.tasks) == map_size(domain.tasks)
      assert map_size(deserialized_domain.allowed_workflows) == map_size(domain.allowed_workflows)
      assert map_size(deserialized_domain.callbacks) == map_size(domain.callbacks)

      # Verify task structure and references
      verify_task_structure(deserialized_domain)
    end

    test "handles primitive tasks with cost and duration" do
      domain = create_domain_with_cost_and_duration()

      # Serialize and deserialize
      serialized = Serializer.serialize(domain)
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify cost and duration are preserved
      task = Map.get(deserialized_domain.tasks, "costly_task")
      assert task.cost == 10
      assert task.duration == 5
    end

    test "handles function references in callbacks" do
      domain = create_domain_with_callbacks()

      # Serialize and deserialize
      serialized = Serializer.serialize(domain)
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify callback functions are preserved
      assert Map.has_key?(deserialized_domain.callbacks, "on_start")
      assert Map.has_key?(deserialized_domain.callbacks, "on_complete")
    end

    test "successfully round-trips named functions through MFA serialization" do
      domain = create_test_domain()

      # Serialize
      serialized = Serializer.serialize(domain)

      # Verify MFA format in JSON
      assert serialized =~ "__jido_mfa__"
      assert serialized =~ "TestConditions"
      assert serialized =~ "check_condition1"

      # Deserialize
      {:ok, deserialized_domain} = Serializer.deserialize(serialized)

      # Verify functions are callable
      root_task = Map.get(deserialized_domain.tasks, "root_task")
      [method] = root_task.methods
      [condition1, _condition2] = method.conditions

      assert is_function(condition1)
      assert condition1.(%{condition1: true}) == true
      assert condition1.(%{}) == false

      # Verify primitive task functions
      subtask1 = Map.get(deserialized_domain.tasks, "subtask1")
      [precondition] = subtask1.preconditions
      [effect] = subtask1.effects

      assert is_function(precondition)
      assert is_function(effect)
      assert precondition.(%{precondition1: true}) == true
      assert effect.(%{}) == %{effect1: true}
    end

    test "rejects anonymous functions during serialization" do
      domain = %Domain{
        name: "invalid_domain",
        tasks: %{
          "bad_task" => %PrimitiveTask{
            name: "bad_task",
            task: {TestAction, []},
            preconditions: [fn state -> Map.get(state, :test) end],
            effects: [],
            expected_effects: []
          }
        },
        allowed_workflows: %{},
        callbacks: %{},
        root_tasks: MapSet.new(["bad_task"])
      }

      assert_raise RuntimeError, ~r/Anonymous functions cannot be reliably serialized/, fn ->
        Serializer.serialize(domain)
      end
    end

    test "returns error for non-existent MFA during deserialization" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {
          "test_task": {
            "type": "primitive",
            "name": "test_task",
            "task": {"module": "TestAction", "opts": []},
            "preconditions": [{"__jido_mfa__": {"m": "NonExistentModule", "f": "test_func", "a": 1}}],
            "effects": [],
            "expected_effects": []
          }
        },
        "allowed_workflows": {},
        "callbacks": {},
        "root_tasks": ["test_task"]
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Cannot deserialize MFA"
    end

    @tag :capture_log
    test "returns error for invalid JSON during deserialization" do
      invalid_json = "{invalid json structure"

      assert {:error, message} = Serializer.deserialize(invalid_json)
      assert message =~ "Failed to deserialize domain"
    end

    @tag :capture_log
    test "returns error for invalid task format during deserialization" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {
          "bad_task": {
            "type": "unknown_type",
            "name": "bad_task"
          }
        },
        "allowed_workflows": {},
        "callbacks": {},
        "root_tasks": ["bad_task"]
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Failed to deserialize domain"
    end

    @tag :capture_log
    test "returns error for non-existent module in allowed_workflows" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {},
        "allowed_workflows": {"NonExistentWorkflow": "NonExistentModule"},
        "callbacks": {},
        "root_tasks": []
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Module NonExistentModule does not exist"
    end

    @tag :capture_log
    test "returns error for invalid method format" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {
          "compound_task": {
            "type": "compound",
            "name": "compound_task",
            "methods": [
              {
                "invalid_field": "value"
              }
            ]
          }
        },
        "allowed_workflows": {},
        "callbacks": {},
        "root_tasks": ["compound_task"]
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Invalid method format"
    end

    test "successfully round-trips a minimal domain" do
      domain = %Domain{
        name: "minimal_domain",
        tasks: %{},
        allowed_workflows: %{},
        callbacks: %{},
        root_tasks: MapSet.new([])
      }

      serialized = Serializer.serialize(domain)
      {:ok, deserialized} = Serializer.deserialize(serialized)

      assert deserialized.name == domain.name
      assert deserialized.tasks == domain.tasks
      assert deserialized.allowed_workflows == domain.allowed_workflows
      assert deserialized.callbacks == domain.callbacks
      assert deserialized.root_tasks == domain.root_tasks
    end

    test "preserves primitive task without cost and duration" do
      domain = %Domain{
        name: "no_cost_domain",
        tasks: %{
          "task_without_cost" => %PrimitiveTask{
            name: "task_without_cost",
            task: {TestAction, []},
            preconditions: [],
            effects: [],
            expected_effects: []
          }
        },
        allowed_workflows: %{"TestAction" => TestAction},
        callbacks: %{},
        root_tasks: MapSet.new(["task_without_cost"])
      }

      serialized = Serializer.serialize(domain)
      assert serialized =~ "task_without_cost"
      refute serialized =~ "\"cost\""
      refute serialized =~ "\"duration\""

      {:ok, deserialized} = Serializer.deserialize(serialized)
      task = Map.get(deserialized.tasks, "task_without_cost")
      assert task.cost == nil
      assert task.duration == nil
    end

    test "handles method with minimal fields (conditions and subtasks only)" do
      domain = %Domain{
        name: "minimal_method_domain",
        tasks: %{
          "root" => %CompoundTask{
            name: "root",
            methods: [
              %Method{
                conditions: [],
                subtasks: ["subtask"]
              }
            ]
          },
          "subtask" => %PrimitiveTask{
            name: "subtask",
            task: {TestAction, []},
            preconditions: [],
            effects: [],
            expected_effects: []
          }
        },
        allowed_workflows: %{"TestAction" => TestAction},
        callbacks: %{},
        root_tasks: MapSet.new(["root"])
      }

      serialized = Serializer.serialize(domain)
      {:ok, deserialized} = Serializer.deserialize(serialized)

      root_task = Map.get(deserialized.tasks, "root")
      [method] = root_task.methods
      assert method.conditions == []
      assert method.subtasks == ["subtask"]
    end

    test "round-trips non-function values in conditions and effects" do
      domain = %Domain{
        name: "mixed_values_domain",
        tasks: %{
          "task" => %PrimitiveTask{
            name: "task",
            task: {TestAction, []},
            preconditions: [true, false],
            effects: ["effect_string"],
            expected_effects: [true]
          }
        },
        allowed_workflows: %{"TestAction" => TestAction},
        callbacks: %{},
        root_tasks: MapSet.new(["task"])
      }

      serialized = Serializer.serialize(domain)
      {:ok, deserialized} = Serializer.deserialize(serialized)

      task = Map.get(deserialized.tasks, "task")
      assert task.preconditions == [true, false]
      assert task.effects == ["effect_string"]
      assert task.expected_effects == [true]
    end

    @tag :capture_log
    test "returns error for invalid function format" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {
          "test_task": {
            "type": "primitive",
            "name": "test_task",
            "task": {"module": "TestAction", "opts": []},
            "preconditions": [123],
            "effects": [],
            "expected_effects": []
          }
        },
        "allowed_workflows": {},
        "callbacks": {},
        "root_tasks": ["test_task"]
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Invalid function format"
    end

    @tag :capture_log
    test "returns error for invalid callback function" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {},
        "allowed_workflows": {},
        "callbacks": {"on_start": {"__jido_mfa__": {"m": "NonExistentModule", "f": "func", "a": 1}}},
        "root_tasks": []
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Cannot deserialize MFA"
    end

    @tag :capture_log
    test "returns error for MFA with non-existent function" do
      serialized = """
      {
        "name": "test_domain",
        "tasks": {
          "test_task": {
            "type": "primitive",
            "name": "test_task",
            "task": {"module": "TestAction", "opts": []},
            "preconditions": [{"__jido_mfa__": {"m": "TestConditions", "f": "non_existent_function", "a": 1}}],
            "effects": [],
            "expected_effects": []
          }
        },
        "allowed_workflows": {},
        "callbacks": {},
        "root_tasks": ["test_task"]
      }
      """

      assert {:error, message} = Serializer.deserialize(serialized)
      assert message =~ "Cannot deserialize MFA"
    end
  end

  # Helper functions

  defp create_test_domain do
    %Domain{
      name: "test_domain",
      tasks: %{
        "root_task" => %CompoundTask{
          name: "root_task",
          methods: [
            %Method{
              name: "method1",
              priority: 1,
              conditions: [
                &TestConditions.check_condition1/1,
                &TestConditions.check_condition2/1
              ],
              subtasks: ["subtask1", "subtask2"],
              ordering: [{"subtask1", "subtask2"}]
            }
          ]
        },
        "subtask1" => %PrimitiveTask{
          name: "subtask1",
          task: {TestAction, []},
          preconditions: [&TestConditions.check_precondition1/1],
          effects: [&TestConditions.apply_effect1/1],
          expected_effects: [&TestConditions.apply_expected1/1],
          cost: 1,
          duration: 1
        },
        "subtask2" => %PrimitiveTask{
          name: "subtask2",
          task: {TestAction, []},
          preconditions: [&TestConditions.check_precondition2/1],
          effects: [&TestConditions.apply_effect2/1],
          expected_effects: [&TestConditions.apply_expected2/1],
          cost: 2,
          duration: 2
        }
      },
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{
        "on_start" => &TestConditions.on_start/1,
        "on_complete" => &TestConditions.on_complete/1
      },
      root_tasks: MapSet.new(["root_task"])
    }
  end

  defp create_domain_with_cost_and_duration do
    %Domain{
      name: "cost_domain",
      tasks: %{
        "costly_task" => %PrimitiveTask{
          name: "costly_task",
          task: {TestAction, []},
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 10,
          duration: 5
        }
      },
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{},
      root_tasks: MapSet.new(["costly_task"])
    }
  end

  defp create_domain_with_callbacks do
    %Domain{
      name: "callback_domain",
      tasks: %{
        "simple_task" => %PrimitiveTask{
          name: "simple_task",
          task: {TestAction, []},
          preconditions: [],
          effects: [],
          expected_effects: [],
          cost: 1,
          duration: 1
        }
      },
      allowed_workflows: %{"TestAction" => TestAction},
      callbacks: %{
        "on_start" => &TestConditions.on_start/1,
        "on_complete" => &TestConditions.on_complete/1
      },
      root_tasks: MapSet.new(["simple_task"])
    }
  end

  defp verify_task_structure(domain) do
    # Verify root task exists and has correct structure
    root_task = Map.get(domain.tasks, "root_task")
    assert %CompoundTask{} = root_task
    assert length(root_task.methods) == 1
    assert length(List.first(root_task.methods).subtasks) == 2

    # Verify subtasks exist and have correct structure
    subtask1 = Map.get(domain.tasks, "subtask1")
    assert %PrimitiveTask{} = subtask1
    assert subtask1.cost == 1
    assert subtask1.duration == 1
    assert length(subtask1.preconditions) == 1
    assert length(subtask1.effects) == 1
    assert length(subtask1.expected_effects) == 1

    subtask2 = Map.get(domain.tasks, "subtask2")
    assert %PrimitiveTask{} = subtask2
    assert subtask2.cost == 2
    assert subtask2.duration == 2
    assert length(subtask2.preconditions) == 1
    assert length(subtask2.effects) == 1
    assert length(subtask2.expected_effects) == 1
  end
end
