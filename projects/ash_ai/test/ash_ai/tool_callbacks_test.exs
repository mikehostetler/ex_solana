# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolCallbacksTest do
  use ExUnit.Case, async: true
  alias __MODULE__.{TestDomain, TestResource}

  defmodule TestResource do
    use Ash.Resource, domain: TestDomain, data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_v7_primary_key(:id, writable?: true)
      attribute :name, :string, public?: true, allow_nil?: false
      attribute :status, :string, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
      default_accept [:id, :name, :status]

      action :custom_action, :string do
        argument :message, :string, allow_nil?: false

        run fn input, _context ->
          {:ok, "Processed: #{input.arguments.message}"}
        end
      end
    end
  end

  defmodule TestDomain do
    use Ash.Domain, extensions: [AshAi]

    resources do
      resource TestResource
    end

    tools do
      tool :read_test_resources, TestResource, :read
      tool :create_test_resource, TestResource, :create
      tool :update_test_resource, TestResource, :update
      tool :destroy_test_resource, TestResource, :destroy
      tool :custom_test_action, TestResource, :custom_action
    end
  end

  describe "on_tool_start callback" do
    test "called with correct parameters for read action" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end
        }
      }

      callback.(%{"limit" => 10}, context)

      assert_receive {:tool_start, %AshAi.ToolStartEvent{} = event}
      assert event.tool_name == "read_test_resources"
      assert event.action == :read
      assert event.resource == TestResource
      assert event.arguments == %{"limit" => 10}
      assert is_nil(event.actor)
      assert is_nil(event.tenant)
    end

    test "includes actor and tenant when provided" do
      test_pid = self()
      actor = %{id: "user_123"}
      tenant = "tenant_456"

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: actor,
        tenant: tenant,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end
        }
      }

      callback.(%{}, context)

      assert_receive {:tool_start, event}
      assert event.actor == actor
      assert event.tenant == tenant
    end

    test "called for create action" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "create_test_resource")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end
        }
      }

      callback.(%{"input" => %{"name" => "Test Item"}}, context)

      assert_receive {:tool_start, event}
      assert event.tool_name == "create_test_resource"
      assert event.action == :create
      assert event.arguments == %{"input" => %{"name" => "Test Item"}}
    end
  end

  describe "on_tool_end callback" do
    test "called with success result for read action" do
      test_pid = self()

      {:ok, _resource} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{name: "Test Item", status: "active"})
        |> Ash.create(domain: TestDomain)

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{}, context)

      assert_receive {:tool_end, %AshAi.ToolEndEvent{} = event}
      assert event.tool_name == "read_test_resources"
      assert {:ok, json_result, _raw_result} = event.result
      assert is_binary(json_result)
      assert {:ok, decoded} = Jason.decode(json_result)
      assert is_list(decoded)
      assert length(decoded) > 0
    end

    test "called with error result for invalid input" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "create_test_resource")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{"input" => %{}}, context)

      assert_receive {:tool_end, %AshAi.ToolEndEvent{} = event}
      assert event.tool_name == "create_test_resource"
      assert {:error, error_json} = event.result
      assert is_binary(error_json)
      assert {:ok, errors} = Jason.decode(error_json)
      assert is_list(errors)
    end

    test "called for destroy action" do
      test_pid = self()

      {:ok, resource} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{name: "To Delete"})
        |> Ash.create(domain: TestDomain)

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "destroy_test_resource")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{"id" => resource.id}, context)

      assert_receive {:tool_end, event}
      assert event.tool_name == "destroy_test_resource"
      assert {:ok, json_result, _raw_result} = event.result
      assert is_binary(json_result)
      resources = Ash.read!(TestResource, domain: TestDomain)
      refute Enum.find(resources, &(&1.id == resource.id))
    end

    test "called for custom action" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "custom_test_action")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{"input" => %{"message" => "Hello"}}, context)

      assert_receive {:tool_end, event}
      assert event.tool_name == "custom_test_action"
      assert {:ok, json_result, _raw_result} = event.result
      assert json_result == "\"Processed: Hello\""
    end
  end

  describe "both callbacks together" do
    test "called in sequence" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event, System.monotonic_time()})
          end,
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event, System.monotonic_time()})
          end
        }
      }

      callback.(%{}, context)

      assert_receive {:tool_start, %AshAi.ToolStartEvent{} = start_event, start_time}
      assert_receive {:tool_end, %AshAi.ToolEndEvent{} = end_event, end_time}

      assert start_event.tool_name == end_event.tool_name
      assert start_time < end_time
    end

    test "called for destroy action in sequence" do
      test_pid = self()

      {:ok, resource} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{name: "To Delete", status: "active"})
        |> Ash.create(domain: TestDomain)

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "destroy_test_resource")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end,
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{"id" => resource.id}, context)

      assert_receive {:tool_start, start_event}
      assert_receive {:tool_end, end_event}

      assert start_event.tool_name == "destroy_test_resource"
      assert start_event.action == :destroy
      assert start_event.arguments == %{"id" => resource.id}
      assert end_event.tool_name == "destroy_test_resource"
      assert elem(end_event.result, 0) == :ok
    end

    test "handle tool execution with invalid filter" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end,
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{"filter" => %{"invalid_field" => "value"}}, context)

      assert_receive {:tool_start, _}
      assert_receive {:tool_end, end_event}
      assert {:error, _} = end_event.result
    end
  end

  describe "backward compatibility" do
    test "tools work without any callbacks" do
      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, json_result, _raw_result} = callback.(%{}, context)
      assert is_binary(json_result)
    end

    test "actor passed without callbacks still sets context" do
      actor = %{id: "user_123"}

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "create_test_resource")

      context = %{
        actor: actor,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      assert {:ok, json_result, _raw_result} =
               callback.(%{"input" => %{"name" => "Test with Actor"}}, context)

      assert json_result =~ "Test with Actor"
    end

    test "handles nil callbacks in custom context" do
      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: nil
      }

      assert {:ok, json_result, _raw_result} = callback.(%{}, context)
      assert is_binary(json_result)
    end

    test "only on_tool_start callback works" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end
        }
      }

      callback.(%{}, context)

      assert_receive {:tool_start, _}
      refute_receive {:tool_end, _}
    end

    test "only on_tool_end callback works" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      callback.(%{}, context)

      refute_receive {:tool_start, _}
      assert_receive {:tool_end, _}
    end
  end

  describe "multiple tools execution" do
    test "callbacks called for each tool" do
      test_pid = self()
      call_count = :counters.new(2, [])

      {:ok, resource} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{
          id: "0197b375-4daa-7112-a9d8-7f0104485646",
          name: "Initial",
          status: "pending"
        })
        |> Ash.create(domain: TestDomain)

      {_tools, registry} = get_tools_and_registry()
      read_callback = Map.fetch!(registry, "read_test_resources")
      update_callback = Map.fetch!(registry, "update_test_resource")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            :counters.add(call_count, 1, 1)
            send(test_pid, {:tool_start, event})
          end,
          on_tool_end: fn event ->
            :counters.add(call_count, 2, 1)
            send(test_pid, {:tool_end, event})
          end
        }
      }

      read_callback.(%{}, context)
      update_callback.(%{"id" => resource.id, "input" => %{"status" => "active"}}, context)

      assert :counters.get(call_count, 1) == 2
      assert :counters.get(call_count, 2) == 2

      assert_receive {:tool_start, %{tool_name: "read_test_resources"}}
      assert_receive {:tool_start, %{tool_name: "update_test_resource"}}
      assert_receive {:tool_end, %{tool_name: "read_test_resources"}}
      assert_receive {:tool_end, %{tool_name: "update_test_resource"}}
    end
  end

  describe "callback error handling" do
    test "on_tool_start exceptions propagate" do
      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn _event ->
            raise "Callback error"
          end
        }
      }

      assert_raise RuntimeError, "Callback error", fn ->
        callback.(%{}, context)
      end
    end

    test "on_tool_end exceptions propagate" do
      test_pid = self()

      {_tools, registry} = get_tools_and_registry()
      callback = Map.fetch!(registry, "read_test_resources")

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start_called, event})
          end,
          on_tool_end: fn _event ->
            raise "End callback error"
          end
        }
      }

      assert_raise RuntimeError, "End callback error", fn ->
        callback.(%{}, context)
      end

      assert_receive {:tool_start_called, _}
    end
  end

  defp get_tools_and_registry do
    opts = [otp_app: :ash_ai, actions: [{TestResource, :*}]]

    # Get exposed tools
    tool_defs = AshAi.exposed_tools(opts)

    # Convert to {tool, callback} tuples
    tool_tuples = Enum.map(tool_defs, &AshAi.tool/1)

    # Separate tools and callbacks
    {tools, callbacks} = Enum.unzip(tool_tuples)

    # Build registry mapping tool name to callback function (function/2)
    registry =
      Enum.zip(tools, callbacks)
      |> Enum.into(%{}, fn {tool, callback} -> {tool.name, callback} end)

    {tools, registry}
  end
end
