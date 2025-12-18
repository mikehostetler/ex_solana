# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ReqLLMToolTest do
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

  describe "reqllm_tool/1" do
    test "creates valid ReqLLM.Tool struct from AshAi tool definition" do
      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))

      {req_tool, callback} = AshAi.reqllm_tool(tool_def)

      assert %ReqLLM.Tool{} = req_tool
      assert req_tool.name == "read_test_resources"
      assert is_binary(req_tool.description)
      assert is_map(req_tool.parameter_schema)
      assert is_function(callback, 2)
    end

    test "tool parameter_schema includes expected read action properties" do
      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))

      {req_tool, _callback} = AshAi.reqllm_tool(tool_def)
      schema = req_tool.parameter_schema

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "filter")
      assert Map.has_key?(schema["properties"], "limit")
      assert Map.has_key?(schema["properties"], "offset")
      assert Map.has_key?(schema["properties"], "sort")
    end

    test "tool parameter_schema includes input for create action" do
      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :create_test_resource))

      {req_tool, _callback} = AshAi.reqllm_tool(tool_def)
      schema = req_tool.parameter_schema

      assert Map.has_key?(schema["properties"], "input")
      assert schema["properties"]["input"]["type"] == "object"
    end
  end

  describe "reqllm_functions/1" do
    test "returns list of ReqLLM.Tool structs" do
      tools = AshAi.reqllm_functions(actions: [{TestResource, :*}])

      assert is_list(tools)
      assert length(tools) > 0
      assert Enum.all?(tools, &match?(%ReqLLM.Tool{}, &1))
    end

    test "includes all exposed tools" do
      tools = AshAi.reqllm_functions(actions: [{TestResource, :*}])
      tool_names = Enum.map(tools, & &1.name)

      assert "read_test_resources" in tool_names
      assert "create_test_resource" in tool_names
      assert "update_test_resource" in tool_names
      assert "destroy_test_resource" in tool_names
      assert "custom_test_action" in tool_names
    end
  end

  describe "tool callbacks" do
    test "callback executes read action and returns JSON result" do
      {:ok, _resource} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{name: "Test Item", status: "active"})
        |> Ash.create(domain: TestDomain)

      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{actor: nil, tenant: nil, context: %{}, tool_callbacks: %{}}
      {:ok, result, _raw} = callback.(%{}, ctx)

      assert is_binary(result)
      assert {:ok, decoded} = Jason.decode(result)
      assert is_list(decoded)
    end

    test "callback executes create action" do
      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :create_test_resource))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{actor: nil, tenant: nil, context: %{}, tool_callbacks: %{}}
      {:ok, result, _raw} = callback.(%{"input" => %{"name" => "New Item"}}, ctx)

      assert is_binary(result)
      assert {:ok, decoded} = Jason.decode(result)
      assert decoded["name"] == "New Item"
    end

    test "callback executes custom action" do
      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :custom_test_action))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{actor: nil, tenant: nil, context: %{}, tool_callbacks: %{}}
      {:ok, result, _raw} = callback.(%{"input" => %{"message" => "Hello"}}, ctx)

      assert result == "\"Processed: Hello\""
    end

    test "callback handles nil arguments" do
      {:ok, _resource} =
        TestResource
        |> Ash.Changeset.for_create(:create, %{name: "Test for nil args"})
        |> Ash.create(domain: TestDomain)

      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{actor: nil, tenant: nil, context: %{}, tool_callbacks: %{}}

      {:ok, result, _raw} = callback.(nil, ctx)

      assert is_binary(result)
    end

    test "callback returns error for invalid input" do
      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :create_test_resource))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{actor: nil, tenant: nil, context: %{}, tool_callbacks: %{}}
      {:error, error_json} = callback.(%{"input" => %{}}, ctx)

      assert is_binary(error_json)
      assert {:ok, errors} = Jason.decode(error_json)
      assert is_list(errors)
    end
  end

  describe "on_tool_start and on_tool_end callbacks" do
    test "on_tool_start callback is invoked" do
      test_pid = self()

      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_start: fn event ->
            send(test_pid, {:tool_start, event})
          end
        }
      }

      _ = callback.(%{}, ctx)

      assert_receive {:tool_start, %AshAi.ToolStartEvent{} = event}
      assert event.tool_name == "read_test_resources"
      assert event.action == :read
      assert event.resource == TestResource
    end

    test "on_tool_end callback is invoked" do
      test_pid = self()

      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{
          on_tool_end: fn event ->
            send(test_pid, {:tool_end, event})
          end
        }
      }

      _ = callback.(%{}, ctx)

      assert_receive {:tool_end, %AshAi.ToolEndEvent{} = event}
      assert event.tool_name == "read_test_resources"
      assert {:ok, _, _} = event.result
    end

    test "both callbacks called in sequence" do
      test_pid = self()

      tools = AshAi.exposed_tools(actions: [{TestResource, :*}])
      tool_def = Enum.find(tools, &(&1.name == :read_test_resources))
      {_req_tool, callback} = AshAi.reqllm_tool(tool_def)

      ctx = %{
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

      _ = callback.(%{}, ctx)

      assert_receive {:tool_start, %AshAi.ToolStartEvent{}, start_time}
      assert_receive {:tool_end, %AshAi.ToolEndEvent{}, end_time}

      assert start_time < end_time
    end
  end

  describe "Options validation" do
    test "model option defaults to openai:gpt-4o-mini" do
      opts = AshAi.Options.validate!(actions: [{TestResource, :*}])
      assert opts.model == "openai:gpt-4o-mini"
    end

    test "model option can be overridden" do
      opts =
        AshAi.Options.validate!(actions: [{TestResource, :*}], model: "anthropic:claude-3-haiku")

      assert opts.model == "anthropic:claude-3-haiku"
    end

    test "req_llm option defaults to ReqLLM module" do
      opts = AshAi.Options.validate!(actions: [{TestResource, :*}])
      assert opts.req_llm == ReqLLM
    end
  end
end
