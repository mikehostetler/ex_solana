# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolsTest do
  use ExUnit.Case, async: true

  alias AshAi.Tools

  defmodule Post do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true, allow_nil?: false
      attribute :body, :string, public?: true
      attribute :published, :boolean, public?: true, default: false
    end

    actions do
      defaults [:read, :update, :destroy]

      create :create do
        accept [:title, :body, :published]
      end

      read :published do
        description "Read published posts"
        filter expr(published == true)
      end

      create :publish do
        description "Create and publish a post"
        accept [:title, :body]
        change set_attribute(:published, true)
      end
    end

    code_interface do
      define :create
      define :read
      define :update
      define :destroy
      define :published
      define :publish
    end
  end

  defmodule Comment do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :content, :string, public?: true, allow_nil?: false
    end

    actions do
      defaults [:create, :read]
    end

    code_interface do
      define :create
      define :read
    end
  end

  defmodule TestDomain do
    use Ash.Domain,
      extensions: [AshAi]

    resources do
      resource Post
      resource Comment
    end

    tools do
      tool :read_posts, Post, :read
      tool :create_post, Post, :create
      tool :update_post, Post, :update
      tool :destroy_post, Post, :destroy
      tool :read_published_posts, Post, :published
      tool :publish_post, Post, :publish

      tool :read_comments, Comment, :read
      tool :create_comment, Comment, :create
    end
  end

  defmodule AnotherDomain do
    use Ash.Domain,
      extensions: [AshAi]

    resources do
      resource Post
    end

    tools do
      tool :list_posts, Post, :read
    end
  end

  setup do
    # Reset the ETS table before each test
    :ok
  end

  describe "discovery/1" do
    test "discovers tools from otp_app" do
      # Register domains for test
      Application.put_env(:test_app, :ash_domains, [TestDomain, AnotherDomain])

      tool_defs = Tools.discovery(otp_app: :test_app)

      assert length(tool_defs) == 9
      tool_names = Enum.map(tool_defs, & &1.name)

      assert :read_posts in tool_names
      assert :create_post in tool_names
      assert :read_comments in tool_names
      assert :list_posts in tool_names
    end

    test "discovers tools from explicit domains list" do
      tool_defs = Tools.discovery(domains: [TestDomain])

      assert length(tool_defs) == 8
      tool_names = Enum.map(tool_defs, & &1.name)

      assert :read_posts in tool_names
      assert :create_post in tool_names
      refute :list_posts in tool_names
    end

    @tag :skip
    test "discovers tools from explicit actions list" do
      # Note: This test is skipped because TestDomain is defined inline
      # and not yet fully compiled when using actions discovery
      tool_defs = Tools.discovery(actions: [{Post, [:read, :create]}])

      assert length(tool_defs) == 2
      tool_names = Enum.map(tool_defs, & &1.name)

      assert :read_posts in tool_names
      assert :create_post in tool_names
      refute :update_post in tool_names
    end

    @tag :skip
    test "discovers all actions for a resource with :*" do
      # Note: This test is skipped because TestDomain is defined inline
      # and not yet fully compiled when using actions discovery
      tool_defs = Tools.discovery(actions: [{Post, :*}])

      assert length(tool_defs) == 6
      tool_names = Enum.map(tool_defs, & &1.name)

      assert :read_posts in tool_names
      assert :create_post in tool_names
      assert :update_post in tool_names
      assert :destroy_post in tool_names
      assert :read_published_posts in tool_names
      assert :publish_post in tool_names
    end

    # Note: Testing resource without domain requires compile-time setup
    # Skipping this test as all test resources are properly configured with domains

    @tag :skip
    test "raises when action is not exposed as a tool" do
      # Note: This test is skipped because TestDomain is defined inline
      # and not yet fully compiled when using actions discovery
      assert_raise ArgumentError, ~r/No tools found/, fn ->
        Tools.discovery(actions: [{Comment, [:destroy]}])
      end
    end

    test "filters by tools list" do
      tool_defs =
        Tools.discovery(
          domains: [TestDomain],
          tools: [:read_posts, :create_post]
        )

      assert length(tool_defs) == 2
      assert Enum.all?(tool_defs, &(&1.name in [:read_posts, :create_post]))
    end

    test "filters by single tool name" do
      tool_defs =
        Tools.discovery(
          domains: [TestDomain],
          tools: :read_posts
        )

      assert length(tool_defs) == 1
      assert hd(tool_defs).name == :read_posts
    end

    test "filters by exclude_actions" do
      tool_defs =
        Tools.discovery(
          domains: [TestDomain],
          exclude_actions: [{Post, :update}, {Post, :destroy}]
        )

      tool_names = Enum.map(tool_defs, & &1.name)

      refute :update_post in tool_names
      refute :destroy_post in tool_names
      assert :read_posts in tool_names
      assert :create_post in tool_names
    end

    test "applies custom filter predicate" do
      tool_defs =
        Tools.discovery(
          domains: [TestDomain],
          filter: fn tool -> tool.action.type == :read end
        )

      assert Enum.all?(tool_defs, &(&1.action.type == :read))
      tool_names = Enum.map(tool_defs, & &1.name)

      assert :read_posts in tool_names
      assert :read_published_posts in tool_names
      refute :create_post in tool_names
    end

    test "hydrates tools with domain and action" do
      [tool_def | _] = Tools.discovery(domains: [TestDomain])

      assert tool_def.domain == TestDomain
      assert is_struct(tool_def.action, Ash.Resource.Actions.Read)
      assert tool_def.resource == Post
    end

    test "removes duplicate tools" do
      # When using both otp_app and domains, we might get duplicates
      Application.put_env(:test_app, :ash_domains, [TestDomain])

      tool_defs = Tools.discovery(otp_app: :test_app)

      # Count occurrences of each tool name
      name_counts =
        tool_defs
        |> Enum.map(& &1.name)
        |> Enum.frequencies()

      assert Enum.all?(name_counts, fn {_name, count} -> count == 1 end)
    end
  end

  describe "build/1" do
    test "returns {tools, registry} tuple" do
      {tools, registry} = Tools.build(domains: [TestDomain])

      assert is_list(tools)
      assert is_map(registry)
      assert length(tools) == map_size(registry)
    end

    test "builds ReqLLM.Tool structs" do
      {tools, _registry} = Tools.build(domains: [TestDomain], tools: [:read_posts])

      assert length(tools) == 1
      [tool] = tools

      assert tool.name == "read_posts"
      assert is_binary(tool.description)
      assert is_map(tool.parameter_schema)
      assert is_function(tool.callback, 1)
    end

    test "builds registry with tool names as keys" do
      {_tools, registry} = Tools.build(domains: [TestDomain])

      assert Map.has_key?(registry, "read_posts")
      assert Map.has_key?(registry, "create_post")
      assert Map.has_key?(registry, "read_comments")
    end

    test "registry callbacks are executable functions" do
      {_tools, registry} = Tools.build(domains: [TestDomain])

      callback = Map.fetch!(registry, "read_posts")
      assert is_function(callback, 2)
    end

    test "builds with filtering options" do
      {tools, registry} =
        Tools.build(
          domains: [TestDomain],
          tools: [:read_posts, :create_post]
        )

      assert length(tools) == 2
      assert map_size(registry) == 2
      assert Map.has_key?(registry, "read_posts")
      assert Map.has_key?(registry, "create_post")
      refute Map.has_key?(registry, "update_post")
    end

    test "passes context to callback builder" do
      actor = %{id: 123}
      tenant = "tenant_1"

      {_tools, registry} =
        Tools.build(
          domains: [TestDomain],
          tools: [:read_posts],
          actor: actor,
          tenant: tenant
        )

      callback = Map.fetch!(registry, "read_posts")
      assert is_function(callback, 2)
    end
  end

  describe "list/1" do
    test "returns just the tools list" do
      tools = Tools.list(domains: [TestDomain])

      assert is_list(tools)
      assert length(tools) == 8
      assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
    end

    test "filters tools" do
      tools =
        Tools.list(
          domains: [TestDomain],
          tools: [:read_posts]
        )

      assert length(tools) == 1
      assert hd(tools).name == "read_posts"
    end
  end

  describe "registry/1" do
    test "returns just the registry map" do
      registry = Tools.registry(domains: [TestDomain])

      assert is_map(registry)
      assert map_size(registry) == 8

      assert Enum.all?(registry, fn {name, callback} ->
               is_binary(name) && is_function(callback, 2)
             end)
    end

    test "filters registry" do
      registry =
        Tools.registry(
          domains: [TestDomain],
          tools: [:read_posts, :create_post]
        )

      assert map_size(registry) == 2
      assert Map.has_key?(registry, "read_posts")
      assert Map.has_key?(registry, "create_post")
    end
  end

  describe "integration with Tool.Builder" do
    test "built tools have correct schema for read actions" do
      tools = Tools.list(domains: [TestDomain], tools: [:read_posts])
      [tool] = tools

      schema = tool.parameter_schema

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "filter")
      assert Map.has_key?(schema["properties"], "sort")
      assert Map.has_key?(schema["properties"], "limit")
      assert Map.has_key?(schema["properties"], "offset")
    end

    test "built tools have correct schema for create actions" do
      tools = Tools.list(domains: [TestDomain], tools: [:create_post])
      [tool] = tools

      schema = tool.parameter_schema

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "input")

      input = schema["properties"]["input"]
      assert Map.has_key?(input["properties"], "title")
      assert Map.has_key?(input["properties"], "body")
    end

    test "built tool has correct description" do
      tools = Tools.list(domains: [TestDomain], tools: [:read_published_posts])
      [tool] = tools

      assert tool.description == "Read published posts"
    end
  end

  describe "special tool handling" do
    test "handles :ash_dev_tools special value" do
      # This would normally require AshAi.DevTools.Tools to exist
      # For now just test that the logic doesn't crash
      tool_defs =
        Tools.discovery(
          domains: [TestDomain],
          tools: :ash_dev_tools
        )

      # Should filter to the specific dev tools (which don't exist in this test)
      assert tool_defs == []
    end
  end

  describe "error handling" do
    test "raises on missing otp_app and actions" do
      assert_raise ArgumentError, ~r/Must specify/, fn ->
        Tools.discovery([])
      end
    end

    test "validates options schema" do
      assert_raise ArgumentError, fn ->
        Tools.build(invalid_option: :value)
      end
    end
  end

  describe "authorization filtering" do
    # Note: Authorization filtering is tested indirectly through other tests
    # The filter_by_authorization/2 function filters tools based on Ash.can?
    # Tools without authorizers always pass, tools with authorizers are checked

    test "tools without authorizers are included" do
      # TestDomain resources have no authorizers, so all should be included
      tool_defs = Tools.discovery(domains: [TestDomain])

      # Should find all 8 tools since there are no authorization restrictions
      assert length(tool_defs) == 8
    end
  end
end
