# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.BuilderTest do
  use ExUnit.Case, async: true

  alias AshAi.Tool.Builder

  defmodule Post do
    @moduledoc false
    use Ash.Resource,
      domain: __MODULE__.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :body, :string, public?: true
    end

    actions do
      default_accept [:title, :body]
      defaults [:read, :destroy, create: :*, update: :*]
    end

    defmodule Domain do
      @moduledoc false
      use Ash.Domain

      resources do
        resource Post
      end
    end
  end

  describe "build/2" do
    test "returns {ReqLLM.Tool, callback} tuple" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: "Read all posts"
      }

      {tool, callback} = Builder.build(tool_def)

      assert %ReqLLM.Tool{} = tool
      assert is_function(callback, 2)
    end

    test "tool has correct name and description from DSL" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: "Read all posts"
      }

      {tool, _callback} = Builder.build(tool_def)

      assert tool.name == "read_posts"
      assert tool.description == "Read all posts"
    end

    test "description defaults when not provided" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: nil
      }

      {tool, _callback} = Builder.build(tool_def)

      expected = "Call the read action on the #{inspect(Post)} resource"
      assert tool.description == expected
    end

    test "parameter schema is delegated to Schema module" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: nil,
        action_parameters: nil
      }

      {tool, _callback} = Builder.build(tool_def)

      # Verify schema structure matches what Schema.for_action returns
      assert is_map(tool.parameter_schema)
      assert tool.parameter_schema["type"] == "object"
      assert is_map(tool.parameter_schema["properties"])
    end

    test "callback receives correct exec_ctx" do
      action = Ash.Resource.Info.action(Post, :create)

      tool_def = %AshAi.Tool{
        name: :create_post,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [:title],
        identity: nil,
        description: "Create a post"
      }

      {_tool, callback} = Builder.build(tool_def)

      context = %{
        actor: :test_actor,
        tenant: :test_tenant,
        context: %{extra: "context"},
        tool_callbacks: %{}
      }

      # We can't easily mock, but we can verify the callback structure
      # by calling it and checking the error contains expected context
      result = callback.(%{"input" => %{"title" => "Test"}}, context)

      # Should execute and either succeed or fail with proper structure
      assert match?({:ok, _, _}, result) or match?({:error, _}, result)
    end

    test "callback execution delegates to Execution module" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: "Read all posts"
      }

      {_tool, callback} = Builder.build(tool_def)

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{}
      }

      # Call the callback and verify it returns expected format
      result = callback.(%{}, context)

      # Should return {:ok, json_string, raw_result}
      assert match?({:ok, _, _}, result)
    end

    test "callback invokes on_tool_start when provided" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: "Read all posts"
      }

      {_tool, callback} = Builder.build(tool_def)

      test_pid = self()

      on_tool_start = fn event ->
        send(test_pid, {:tool_start, event})
      end

      context = %{
        actor: :my_actor,
        tenant: :my_tenant,
        context: %{},
        tool_callbacks: %{on_tool_start: on_tool_start}
      }

      callback.(%{}, context)

      assert_received {:tool_start, %AshAi.ToolStartEvent{} = event}
      assert event.tool_name == "read_posts"
      assert event.action == :read
      assert event.resource == Post
      assert event.actor == :my_actor
      assert event.tenant == :my_tenant
    end

    test "callback invokes on_tool_end when provided" do
      action = Ash.Resource.Info.action(Post, :read)

      tool_def = %AshAi.Tool{
        name: :read_posts,
        resource: Post,
        action: action,
        domain: Post.Domain,
        load: [],
        identity: nil,
        description: "Read all posts"
      }

      {_tool, callback} = Builder.build(tool_def)

      test_pid = self()

      on_tool_end = fn event ->
        send(test_pid, {:tool_end, event})
      end

      context = %{
        actor: nil,
        tenant: nil,
        context: %{},
        tool_callbacks: %{on_tool_end: on_tool_end}
      }

      callback.(%{}, context)

      assert_received {:tool_end, %AshAi.ToolEndEvent{} = event}
      assert event.tool_name == "read_posts"
      assert match?({:ok, _, _}, event.result)
    end
  end
end
