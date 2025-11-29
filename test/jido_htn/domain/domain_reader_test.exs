defmodule JidoTest.HTN.Domain.ReadHelpersTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.ReadHelpers
  alias Jido.HTN.CompoundTask
  alias Jido.HTN.PrimitiveTask
  alias Jido.HTN.Method

  @moduletag :capture_log

  setup do
    primitive = %PrimitiveTask{
      name: "test_primitive",
      task: {TestAction, []},
      preconditions: [],
      effects: []
    }

    compound = %CompoundTask{
      name: "test_compound",
      methods: [
        %Method{
          name: "method1",
          conditions: [],
          subtasks: []
        }
      ]
    }

    domain = %Domain{
      name: "test_domain",
      tasks: %{
        "test_primitive" => primitive,
        "test_compound" => compound
      },
      allowed_workflows: %{
        "workflow1" => WorkflowModule
      },
      callbacks: %{
        "callback1" => fn -> :ok end
      }
    }

    %{domain: domain, primitive: primitive, compound: compound}
  end

  describe "get_primitive/2" do
    test "returns primitive task when found", %{domain: domain, primitive: primitive} do
      assert {:ok, ^primitive} = ReadHelpers.get_primitive(domain, "test_primitive")
    end

    @tag :capture_log
    test "returns error when task not found", %{domain: domain} do
      assert {:error, "Task 'nonexistent' not found"} =
               ReadHelpers.get_primitive(domain, "nonexistent")
    end

    @tag :capture_log
    test "returns error when task is compound", %{domain: domain} do
      assert {:error, "Task 'test_compound' is not a primitive task"} =
               ReadHelpers.get_primitive(domain, "test_compound")
    end

    @tag :capture_log
    test "returns error with invalid arguments - non-binary name", %{domain: domain} do
      assert {:error, "Invalid arguments for get_primitive"} =
               ReadHelpers.get_primitive(domain, :atom_name)
    end

    @tag :capture_log
    test "returns error with invalid arguments - nil domain" do
      assert {:error, "Invalid arguments for get_primitive"} =
               ReadHelpers.get_primitive(nil, "test")
    end

    @tag :capture_log
    test "returns error with invalid arguments - empty string", %{domain: domain} do
      assert {:error, "Task '' not found"} = ReadHelpers.get_primitive(domain, "")
    end
  end

  describe "get_compound/2" do
    test "returns compound task when found", %{domain: domain, compound: compound} do
      assert {:ok, ^compound} = ReadHelpers.get_compound(domain, "test_compound")
    end

    @tag :capture_log
    test "returns error when task not found", %{domain: domain} do
      assert {:error, "Task 'nonexistent' not found"} =
               ReadHelpers.get_compound(domain, "nonexistent")
    end

    @tag :capture_log
    test "returns error when task is primitive", %{domain: domain} do
      assert {:error, "Task 'test_primitive' is not a compound task"} =
               ReadHelpers.get_compound(domain, "test_primitive")
    end

    @tag :capture_log
    test "returns error with invalid arguments - non-binary name", %{domain: domain} do
      assert {:error, "Invalid arguments for get_compound"} =
               ReadHelpers.get_compound(domain, :atom_name)
    end

    @tag :capture_log
    test "returns error with invalid arguments - nil domain" do
      assert {:error, "Invalid arguments for get_compound"} =
               ReadHelpers.get_compound(nil, "test")
    end

    @tag :capture_log
    test "returns error with invalid arguments - empty string", %{domain: domain} do
      assert {:error, "Task '' not found"} = ReadHelpers.get_compound(domain, "")
    end
  end

  describe "tasks_to_map/1" do
    test "returns tasks map", %{domain: domain} do
      result = ReadHelpers.tasks_to_map(domain)
      assert is_map(result)
      assert Map.has_key?(result, "test_primitive")
      assert Map.has_key?(result, "test_compound")
    end

    test "returns empty map for domain with no tasks" do
      empty_domain = %Domain{name: "empty", tasks: %{}}
      assert %{} = ReadHelpers.tasks_to_map(empty_domain)
    end
  end

  describe "list_tasks/1" do
    test "returns list of task names", %{domain: domain} do
      result = ReadHelpers.list_tasks(domain)
      assert is_list(result)
      assert "test_primitive" in result
      assert "test_compound" in result
      assert length(result) == 2
    end

    test "returns empty list for domain with no tasks" do
      empty_domain = %Domain{name: "empty", tasks: %{}}
      assert [] = ReadHelpers.list_tasks(empty_domain)
    end
  end

  describe "list_allowed_workflows/1" do
    test "returns list of workflow names", %{domain: domain} do
      result = ReadHelpers.list_allowed_workflows(domain)
      assert is_list(result)
      assert "workflow1" in result
      assert length(result) == 1
    end

    test "returns empty list for domain with no workflows" do
      empty_domain = %Domain{name: "empty", allowed_workflows: %{}}
      assert [] = ReadHelpers.list_allowed_workflows(empty_domain)
    end
  end

  describe "list_callbacks/1" do
    test "returns list of callback names", %{domain: domain} do
      result = ReadHelpers.list_callbacks(domain)
      assert is_list(result)
      assert "callback1" in result
      assert length(result) == 1
    end

    test "returns empty list for domain with no callbacks" do
      empty_domain = %Domain{name: "empty", callbacks: %{}}
      assert [] = ReadHelpers.list_callbacks(empty_domain)
    end
  end
end
