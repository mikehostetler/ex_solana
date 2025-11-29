# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ReqLLMToolTest do
  use ExUnit.Case, async: true
  alias __MODULE__.{TestDomain, TestResource}

  # Helper to get tool tuples (ReqLLM.Tool and callback function) from opts
  defp get_tool_tuples(opts) do
    # Ensure we have actions specified
    opts = Keyword.put_new(opts, :actions, [{TestResource, :*}])

    opts
    |> AshAi.exposed_tools()
    |> Enum.map(&AshAi.tool/1)
  end

  defmodule TestResource do
    use Ash.Resource, domain: TestDomain, data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_v7_primary_key(:id, writable?: true)
      attribute :name, :string, public?: true
      attribute :email, :string, public?: true
      attribute :age, :integer, public?: true
    end

    actions do
      defaults [:read, :create, :update, :destroy]
      default_accept [:id, :name, :email, :age]
    end
  end

  defmodule TestDomain do
    use Ash.Domain, extensions: [AshAi]

    resources do
      resource TestResource
    end

    tools do
      tool :read_users, TestResource, :read
      tool :create_user, TestResource, :create
    end
  end

  describe "ReqLLM.Tool creation" do
    test "creates valid ReqLLM.Tool from AshAi tool definition" do
      opts = [otp_app: :ash_ai, actions: [{TestResource, :*}]]
      tools = AshAi.functions(opts)

      assert is_list(tools)
      assert length(tools) >= 2

      # Check that tools are ReqLLM.Tool structs
      Enum.each(tools, fn tool ->
        assert %ReqLLM.Tool{} = tool
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.parameter_schema)
        # tool.callback is a 1-arity stub, real callbacks are in the registry
        assert is_function(tool.callback, 1)
      end)
    end

    test "tool has correct structure for read action" do
      opts = [tools: [:read_users]]
      [{tool, _callback}] = get_tool_tuples(opts)

      assert tool.name == "read_users"
      assert tool.description =~ "read"

      # Check parameter schema has filter, sort, limit, offset
      schema = tool.parameter_schema
      assert is_map(schema)
      assert Map.has_key?(schema, "type")
      assert schema["type"] == "object"

      properties = schema["properties"]
      assert Map.has_key?(properties, "filter")
      assert Map.has_key?(properties, "sort")
      assert Map.has_key?(properties, "limit")
      assert Map.has_key?(properties, "offset")
    end

    test "tool callback is executable" do
      opts = [tools: [:create_user]]
      [{tool, callback}] = get_tool_tuples(opts)

      # Verify tool structure
      assert %ReqLLM.Tool{} = tool
      assert tool.name == "create_user"

      # Create test data
      user_args = %{
        "input" => %{
          "name" => "Test User",
          "email" => "test@example.com",
          "age" => 30
        }
      }

      # Build context
      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      # Execute the real callback (function/2)
      result = callback.(user_args, context)

      # Should return success tuple
      assert {:ok, json_string, _raw_result} = result
      assert is_binary(json_string)

      # Verify JSON can be decoded
      assert {:ok, decoded} = Jason.decode(json_string)
      assert decoded["name"] == "Test User"
      assert decoded["email"] == "test@example.com"
      assert decoded["age"] == 30
    end

    test "tool callback handles errors gracefully" do
      opts = [tools: [:read_users]]
      [{_tool, callback}] = get_tool_tuples(opts)

      # Invalid arguments (filter with invalid structure)
      invalid_args = %{
        "filter" => "not a valid filter"
      }

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      # Execute the real callback (function/2)
      result = callback.(invalid_args, context)

      # Should return error tuple
      assert {:error, error_json} = result
      assert is_binary(error_json)

      # Verify error JSON can be decoded
      assert {:ok, _decoded_error} = Jason.decode(error_json)
    end
  end

  describe "tool callbacks" do
    test "on_tool_start callback is invoked" do
      test_pid = self()

      on_tool_start = fn event ->
        send(test_pid, {:tool_start, event})
      end

      opts = [tools: [:create_user], on_tool_start: on_tool_start]
      [{_tool, callback}] = get_tool_tuples(opts)

      args = %{"input" => %{"name" => "Test", "email" => "test@test.com"}}

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{on_tool_start: on_tool_start}
      }

      callback.(args, context)

      # Verify callback was called
      assert_receive {:tool_start, %AshAi.ToolStartEvent{tool_name: "create_user"}}
    end

    test "on_tool_end callback is invoked" do
      test_pid = self()

      on_tool_end = fn event ->
        send(test_pid, {:tool_end, event})
      end

      opts = [tools: [:create_user], on_tool_end: on_tool_end]
      [{_tool, callback}] = get_tool_tuples(opts)

      args = %{"input" => %{"name" => "Test", "email" => "test@test.com"}}

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{on_tool_end: on_tool_end}
      }

      callback.(args, context)

      # Verify callback was called
      assert_receive {:tool_end,
                      %AshAi.ToolEndEvent{tool_name: "create_user", result: {:ok, _, _}}}
    end
  end
end
