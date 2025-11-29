# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tools do
  @moduledoc """
  Public API for tool discovery and registry building.

  This module provides the stable public API for discovering Ash actions exposed as tools
  and building ReqLLM tool definitions with their callbacks.

  ## Overview

  The typical workflow is:

  1. Define tools in your Ash domains using the `tools` DSL
  2. Call `build/1` to discover and build tools with their callback registry
  3. Pass tools to your LLM chain and registry to your tool execution loop

  ## Options

  All functions in this module accept the following options:

    * `:otp_app` - The OTP application to discover domains from. Required unless `:actions` is provided.
    * `:domains` - Explicit list of domains to search for tools. Overrides `:otp_app`.
    * `:actions` - List of `{Resource, [:action_names]}` or `{Resource, :*}` tuples to filter by.
    * `:tools` - List of tool names to include. Acts as a filter on discovered tools.
    * `:exclude_actions` - List of `{Resource, :action_name}` tuples to exclude.
    * `:filter` - Custom predicate function `(tool_definition -> boolean())` for filtering.
    * `:actor` - The actor to use for authorization checks.
    * `:tenant` - The tenant to use for multi-tenancy.
    * `:context` - Additional context map to pass to tool callbacks.
    * `:tool_callbacks` - Map with `:on_tool_start` and `:on_tool_end` callbacks.

  ## Examples

      # Discover all tools from configured domains
      {tools, registry} = AshAi.Tools.build(otp_app: :my_app)

      # Filter to specific tools
      {tools, registry} = AshAi.Tools.build(
        otp_app: :my_app,
        tools: [:read_posts, :create_post]
      )

      # Use explicit actions
      {tools, registry} = AshAi.Tools.build(
        actions: [
          {MyApp.Blog.Post, [:read, :create]},
          {MyApp.Accounts.User, :*}
        ]
      )

      # Just get the tool list
      tools = AshAi.Tools.list(otp_app: :my_app)

      # Just get the registry
      registry = AshAi.Tools.registry(otp_app: :my_app)

      # Get raw tool definitions
      tool_defs = AshAi.Tools.discovery(otp_app: :my_app)

  ## Tool Callbacks

  You can provide lifecycle callbacks that are invoked when tools execute:

      {tools, registry} = AshAi.Tools.build(
        otp_app: :my_app,
        tool_callbacks: %{
          on_tool_start: fn %AshAi.ToolStartEvent{} = event ->
            Logger.info("Starting tool: \#{event.tool_name}")
          end,
          on_tool_end: fn %AshAi.ToolEndEvent{} = event ->
            Logger.info("Finished tool with result: \#{inspect(event.result)}")
          end
        }
      )

  ## Integration with LangChain

  The built tools are compatible with LangChain's tool interface:

      {tools, registry} = AshAi.Tools.build(otp_app: :my_app)

      chain =
        LLMChain.new!(%{
          llm: ChatOpenAI.new!(%{model: "gpt-4"}),
          tools: tools
        })

      # In your tool execution loop, use the registry to find callbacks
      def execute_tool(tool_name, arguments, context) do
        callback = Map.fetch!(registry, tool_name)
        callback.(arguments, context)
      end
  """

  require Logger

  alias AshAi.Tool

  @type tool_definition :: Tool.t()
  @type req_llm_tool :: ReqLLM.Tool.t()
  @type callback :: (map(), map() -> any())
  @type registry :: %{required(String.t()) => callback()}
  @type opts :: keyword()

  @doc """
  Build tools and registry from discovered tool definitions.

  Returns a tuple of `{tools, registry}` where:
  - `tools` is a list of `ReqLLM.Tool` structs suitable for LLM chains
  - `registry` is a map of tool names to callback functions

  The registry callbacks are functions with signature `(arguments, context) -> result`
  that delegate to `AshAi.Tool.Execution.run/4` with the appropriate configuration.

  ## Examples

      # Basic usage
      {tools, registry} = AshAi.Tools.build(otp_app: :my_app)

      # With filtering
      {tools, registry} = AshAi.Tools.build(
        otp_app: :my_app,
        tools: [:read_posts],
        actor: current_user
      )
  """
  @spec build(opts()) :: {[req_llm_tool()], registry()}
  def build(opts) do
    opts = normalize_opts(opts)

    # Discover tool definitions
    tool_defs = discovery(opts)

    # Build {tool, callback} tuples
    context = build_context(opts)
    tool_tuples = Enum.map(tool_defs, &Tool.Builder.build(&1, context))

    # Separate tools and callbacks
    {tools, callbacks} = Enum.unzip(tool_tuples)

    # Build registry mapping tool name to callback
    registry =
      Enum.zip(tools, callbacks)
      |> Enum.into(%{}, fn {tool, callback} -> {tool.name, callback} end)

    {tools, registry}
  end

  @doc """
  List all tools without building the registry.

  Returns just the list of `ReqLLM.Tool` structs.

  ## Examples

      tools = AshAi.Tools.list(otp_app: :my_app)
      Enum.each(tools, fn tool ->
        IO.puts("\#{tool.name}: \#{tool.description}")
      end)
  """
  @spec list(opts()) :: [req_llm_tool()]
  def list(opts) do
    {tools, _registry} = build(opts)
    tools
  end

  @doc """
  Build just the registry without returning tools.

  Returns a map of tool names to callback functions.

  ## Examples

      registry = AshAi.Tools.registry(otp_app: :my_app)
      callback = Map.fetch!(registry, "read_posts")
      result = callback.(%{limit: 10}, %{actor: user})
  """
  @spec registry(opts()) :: registry()
  def registry(opts) do
    {_tools, registry} = build(opts)
    registry
  end

  @doc """
  Discover tool definitions from domains without building them.

  Returns raw `AshAi.Tool` DSL definitions before they are converted
  to `ReqLLM.Tool` structs. Useful for introspection and testing.

  ## Discovery Process

  1. Find domains from `:otp_app` or explicit `:domains` list
  2. Extract tool definitions from each domain's `tools` DSL
  3. Hydrate tool definitions with domain and action metadata
  4. Apply filtering based on `:actions`, `:tools`, `:exclude_actions`
  5. Apply custom `:filter` predicate if provided
  6. Filter by authorization using `:actor` and `:tenant`

  ## Examples

      # Discover all tools
      tool_defs = AshAi.Tools.discovery(otp_app: :my_app)

      # Discover from specific domains
      tool_defs = AshAi.Tools.discovery(
        domains: [MyApp.Blog, MyApp.Accounts]
      )

      # Discover with custom filter
      tool_defs = AshAi.Tools.discovery(
        otp_app: :my_app,
        filter: fn tool -> tool.action.type == :read end
      )
  """
  @spec discovery(opts()) :: [tool_definition()]
  def discovery(opts) do
    opts = normalize_opts(opts)

    # Get raw tool definitions from domains
    tool_defs = discover_from_domains(opts)

    # Apply filtering
    tool_defs
    |> filter_by_actions(opts)
    |> filter_by_tools(opts)
    |> filter_by_exclude_actions(opts)
    |> filter_by_custom_predicate(opts)
    |> filter_by_authorization(opts)
    |> Enum.uniq()
  end

  # Private Functions

  defp normalize_opts(opts) when is_list(opts) do
    # Extract domains, filter, and tool_callbacks before validation (not valid options in AshAi.Options)
    domains = Keyword.get(opts, :domains)
    filter = Keyword.get(opts, :filter)
    tool_callbacks = Keyword.get(opts, :tool_callbacks, %{})

    opts =
      opts
      |> Keyword.delete(:domains)
      |> Keyword.delete(:filter)
      |> Keyword.delete(:tool_callbacks)

    case AshAi.Options.validate(opts) do
      {:ok, normalized} ->
        # Convert struct to map and add back domains/filter/tool_callbacks
        Map.from_struct(normalized)
        |> Map.put(:domains, domains)
        |> Map.put(:filter, filter)
        |> Map.put(:tool_callbacks, tool_callbacks)

      {:error, error} ->
        raise ArgumentError, Exception.message(error)
    end
  end

  defp normalize_opts(opts) when is_map(opts), do: opts

  defp build_context(opts) do
    %{
      actor: Map.get(opts, :actor),
      tenant: Map.get(opts, :tenant),
      context: Map.get(opts, :context, %{}),
      tool_callbacks: Map.get(opts, :tool_callbacks, %{})
    }
  end

  defp discover_from_domains(opts) do
    cond do
      # Explicit actions list - use that
      Map.get(opts, :actions) ->
        discover_from_actions(Map.get(opts, :actions))

      # Explicit domains list - use that
      Map.get(opts, :domains) ->
        discover_from_domain_list(Map.get(opts, :domains))

      # Use otp_app
      Map.get(opts, :otp_app) ->
        discover_from_otp_app(Map.get(opts, :otp_app))

      true ->
        raise ArgumentError, "Must specify :otp_app, :domains, or :actions"
    end
  end

  defp discover_from_actions(actions) do
    Enum.flat_map(actions, fn {resource, action_names} ->
      domain = Ash.Resource.Info.domain(resource)

      if !domain do
        raise ArgumentError,
              "Resource #{inspect(resource)} does not have a domain. " <>
                "Ensure it is configured with a domain using `use Ash.Resource, domain: YourDomain`"
      end

      tools = AshAi.Info.tools(domain)

      # Validate that requested actions are actually exposed as tools
      if !Enum.any?(tools, fn tool ->
           tool.resource == resource && (action_names == :* || tool.action in action_names)
         end) do
        raise ArgumentError,
              "No tools found for #{inspect(resource)} with actions #{inspect(action_names)}. " <>
                "Ensure the actions are exposed in the domain's tools DSL."
      end

      # Filter and hydrate tools
      tools
      |> Enum.filter(fn tool ->
        tool.resource == resource &&
          (action_names == :* || tool.action in action_names)
      end)
      |> Enum.map(&hydrate_tool(&1, domain, resource))
    end)
  end

  defp discover_from_domain_list(domains) do
    for domain <- domains,
        tool <- AshAi.Info.tools(domain) do
      hydrate_tool(tool, domain, tool.resource)
    end
  end

  defp discover_from_otp_app(otp_app) do
    domains = Application.get_env(otp_app, :ash_domains, [])

    if Enum.empty?(domains) do
      Logger.warning(
        "No domains found for otp_app #{inspect(otp_app)}. " <>
          "Ensure :ash_domains is configured in config.exs"
      )
    end

    discover_from_domain_list(domains)
  end

  defp hydrate_tool(tool, domain, resource) do
    action = Ash.Resource.Info.action(resource, tool.action)

    %{tool | domain: domain, action: action}
  end

  defp filter_by_actions(tools, opts) do
    # If opts has :actions, we already filtered during discovery
    # This is for the case where we discover from otp_app/domains
    # but still want to filter by actions
    case Map.get(opts, :actions) do
      nil ->
        tools

      actions ->
        action_set =
          MapSet.new(actions, fn
            {resource, :*} -> {resource, :*}
            {resource, action_name} when is_atom(action_name) -> {resource, action_name}
            {resource, action_names} when is_list(action_names) -> {resource, action_names}
          end)

        Enum.filter(tools, fn tool ->
          Enum.any?(action_set, fn
            {resource, :*} ->
              tool.resource == resource

            {resource, action_name} when is_atom(action_name) ->
              tool.resource == resource && tool.action.name == action_name

            {resource, action_names} when is_list(action_names) ->
              tool.resource == resource && tool.action.name in action_names
          end)
        end)
    end
  end

  defp filter_by_tools(tools, opts) do
    case Map.get(opts, :tools) do
      nil ->
        tools

      # Special case for :ash_dev_tools
      :ash_dev_tools ->
        allowed = [
          :list_ash_resources,
          :list_generators,
          :get_usage_rules,
          :list_packages_with_rules
        ]

        Enum.filter(tools, fn tool -> tool.name in allowed end)

      allowed_tools when is_list(allowed_tools) ->
        Enum.filter(tools, fn tool -> tool.name in allowed_tools end)

      allowed_tool when is_atom(allowed_tool) ->
        Enum.filter(tools, fn tool -> tool.name == allowed_tool end)
    end
  end

  defp filter_by_exclude_actions(tools, opts) do
    case Map.get(opts, :exclude_actions) do
      nil ->
        tools

      exclude_list when is_list(exclude_list) ->
        exclude_set = MapSet.new(exclude_list)

        Enum.reject(tools, fn tool ->
          MapSet.member?(exclude_set, {tool.resource, tool.action.name})
        end)

      _ ->
        tools
    end
  end

  defp filter_by_custom_predicate(tools, opts) do
    case Map.get(opts, :filter) do
      nil ->
        tools

      filter_fn when is_function(filter_fn, 1) ->
        Enum.filter(tools, filter_fn)

      _ ->
        tools
    end
  end

  defp filter_by_authorization(tools, opts) do
    actor = Map.get(opts, :actor)
    tenant = Map.get(opts, :tenant)

    Enum.filter(tools, fn tool ->
      can_execute?(actor, tool.domain, tool.resource, tool.action, tenant)
    end)
  end

  defp can_execute?(actor, domain, resource, action, tenant) do
    if Enum.empty?(Ash.Resource.Info.authorizers(resource)) do
      true
    else
      Ash.can?({resource, action}, actor,
        tenant: tenant,
        domain: domain,
        maybe_is: true,
        run_queries?: false,
        pre_flight?: false
      )
    end
  rescue
    e ->
      Logger.error(
        """
        Error raised while checking permissions for #{inspect(resource)}.#{action.name}

        When checking permissions, we check the action using an empty input.
        Your action should be prepared for this.

        For create/update/destroy actions, you may need to add `only_when_valid?: true`
        to the changes, for other things, you may want to check validity of the changeset,
        query or action input.

        #{Exception.format(:error, e, __STACKTRACE__)}
        """,
        __STACKTRACE__
      )

      false
  end
end
