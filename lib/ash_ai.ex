# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi do
  @moduledoc """
  Documentation for `AshAi`.

  AshAi provides AI capabilities for Ash applications, including:
  - Tool exposure for LLM agents (LangChain and ReqLLM)
  - Interactive IEx chat with tool calling
  - MCP (Model Context Protocol) server support
  - Vectorization for semantic search

  ## Architecture

  The tool functionality is organized into specialized modules:
  - `AshAi.Tool.Schema` - Generates JSON schemas for tool parameters
  - `AshAi.Tool.Execution` - Executes Ash actions from tool calls
  - `AshAi.Tool.Errors` - Formats errors as JSON:API responses
  - `AshAi.Tool.Builder` - Creates ReqLLM.Tool structs and callbacks
  - `AshAi.Tools` - High-level API for tool discovery and building
  - `AshAi.ToolLoop` - Manages LLM conversation loops with tools
  """

  alias LangChain.Chains.LLMChain
  alias ReqLLM.Context

  defstruct []

  require Logger

  use Spark.Dsl.Extension,
    sections: AshAi.Dsl.sections(),
    imports: [AshAi.Actions],
    transformers: [AshAi.Transformers.Vectorize],
    verifiers: [AshAi.Verifiers.McpResourceActionsReturnString]

  defmodule Tool do
    @moduledoc "An action exposed to LLM agents"
    defstruct [
      :name,
      :resource,
      :action,
      :load,
      :async,
      :domain,
      :identity,
      :description,
      :action_parameters,
      :_meta,
      __spark_metadata__: nil
    ]

    def has_meta?(%__MODULE__{_meta: meta})
        when not is_nil(meta) and meta != %{},
        do: true

    def has_meta?(_), do: false
  end

  defmodule McpResource do
    @moduledoc """
    An MCP resource to expose via the Model Context Protocol (MCP).

    MCP resources provide LLMs with access to static or dynamic content like UI components,
    data files, or images. Unlike tools which perform actions, resources return content that
    the LLM can read and reference.

    ## Example

    ```elixir
    defmodule MyApp.Blog do
      use Ash.Domain, extensions: [AshAi]

      mcp_resources do
        # Description inherited from :render_card action
        mcp_resource :post_card, "file://ui/post_card.html", Post, :render_card,
          mime_type: "text/html"

        # Custom description overrides action description
        mcp_resource :post_data, "file://data/post.json", Post, :to_json,
          description: "JSON metadata including author, tags, and timestamps",
          mime_type: "application/json"
      end
    end
    ```

    The action is called when an MCP client requests the resource, and its return value
    (which must be a string) is sent to the client with the specified MIME type.

    ## Description Behavior

    Resource descriptions default to the action's description. You can provide a custom
    `description` option in the DSL which takes precedence over the action description.
    This helps LLMs understand when to use each resource.
    """
    @type t :: %__MODULE__{
            name: atom(),
            resource: Ash.Resource.t(),
            action: atom() | Ash.Resource.Actions.Action.t(),
            domain: module() | nil,
            title: String.t(),
            description: String.t(),
            uri: String.t(),
            mime_type: String.t()
          }

    defstruct [
      :name,
      :resource,
      :action,
      :domain,
      :title,
      :description,
      :uri,
      :mime_type,
      __spark_metadata__: nil
    ]
  end

  defmodule FullText do
    @moduledoc "A section that defines how complex vectorized columns are defined"
    defstruct [
      :used_attributes,
      :text,
      :__identifier__,
      name: :full_text_vector,
      __spark_metadata__: nil
    ]
  end

  defmodule Options do
    @moduledoc false
    use Spark.Options.Validator,
      schema: [
        actions: [
          type:
            {:wrap_list,
             {:tuple, [{:spark, Ash.Resource}, {:or, [{:list, :atom}, {:literal, :*}]}]}},
          doc: """
          A set of {Resource, [:action]} pairs, or `{Resource, :*}` for all actions. Defaults to everything. If `tools` is also set, both are applied as filters.
          """
        ],
        tools: [
          type: {:wrap_list, :atom},
          doc: """
           A list of tool names. If not set. Defaults to everything. If `actions` is also set, both are applied as filters.
          """
        ],
        mcp_resources: [
          type: {:or, [{:wrap_list, :atom}, {:literal, :*}]},
          doc: """
          A list of MCP resource names to expose, or `:*` for all. If not set, defaults to everything.
          """
        ],
        exclude_actions: [
          type: {:wrap_list, {:tuple, [{:spark, Ash.Resource}, :atom]}},
          doc: """
          A set of {Resource, :action} pairs, or `{Resource, :*}` to be excluded from the added actions.
          """
        ],
        actor: [
          type: :any,
          doc: "The actor performing any actions."
        ],
        tenant: [
          type: {:protocol, Ash.ToTenant},
          doc: "The tenant to use for the action."
        ],
        messages: [
          type: {:list, :map},
          default: [],
          doc: """
          Used to provide conversation history.
          """
        ],
        context: [
          type: :map,
          default: %{},
          doc: """
          Context passed to each action invocation.
          """
        ],
        otp_app: [
          type: :atom,
          doc: "If present, allows discovering resource actions automatically."
        ],
        system_prompt: [
          type: {:or, [{:fun, 1}, {:literal, :none}]},
          doc: """
          A system prompt that takes the provided options and returns a system prompt.

          You will want to include something like the actor's id if you are chatting as an
          actor.
          """
        ],
        on_tool_start: [
          type: {:fun, 1},
          required: false,
          doc: """
          A callback function that is called when a tool execution starts.

          Receives an `AshAi.ToolStartEvent` struct with the following fields:
          - `:tool_name` - The name of the tool being called
          - `:action` - The action being performed
          - `:resource` - The resource the action is on
          - `:arguments` - The arguments passed to the tool
          - `:actor` - The actor performing the action
          - `:tenant` - The tenant context

          Example:
          ```
          on_tool_start: fn %AshAi.ToolStartEvent{} = event ->
            IO.puts("Starting tool: \#{event.tool_name}")
          end
          ```
          """
        ],
        on_tool_end: [
          type: {:fun, 1},
          required: false,
          doc: """
          A callback function that is called when a tool execution completes.

          Receives an `AshAi.ToolEndEvent` struct with the following fields:
          - `:tool_name` - The name of the tool
          - `:result` - The result of the tool execution (either {:ok, ...} or {:error, ...})

          Example:
          ```
          on_tool_end: fn %AshAi.ToolEndEvent{} = event ->
            IO.puts("Completed tool: \#{event.tool_name}")
          end
          ```
          """
        ],
        model: [
          type: :string,
          default: "openai:gpt-4o-mini",
          doc: """
          The LLM model to use for chat. Format: "provider:model-name".
          Examples: "openai:gpt-4o-mini", "anthropic:claude-haiku-4-5", "openai:gpt-4o".
          """
        ],
        req_llm: [
          type: :atom,
          default: ReqLLM,
          doc: """
          The ReqLLM module to use for streaming. Defaults to ReqLLM.
          Can be overridden for testing with a mock module.
          """
        ],
        max_iterations: [
          type: :pos_integer,
          default: 10,
          doc: """
          Maximum number of iterations for tool calling loops.
          Each iteration allows the LLM to make tool calls and receive results.
          """
        ]
      ]
  end

  # ============================================================================
  # LangChain Integration
  # ============================================================================

  @doc """
  Returns a list of LangChain.Function structs for the given options.
  """
  def functions(opts) do
    opts
    |> exposed_tools()
    |> Enum.map(&AshAi.Tools.to_function/1)
  end

  @doc """
  Adds the requisite context and tool calls to allow an agent to interact with your app.
  """
  def setup_ash_ai(lang_chain, opts \\ [])

  def setup_ash_ai(lang_chain, opts) when is_list(opts) do
    opts = Options.validate!(opts)
    setup_ash_ai(lang_chain, opts)
  end

  def setup_ash_ai(lang_chain, opts) do
    tools = functions(opts)

    lang_chain
    |> LLMChain.add_tools(tools)
    |> LLMChain.update_custom_context(%{
      actor: opts.actor,
      tenant: opts.tenant,
      context: opts.context,
      tool_callbacks: %{
        on_tool_start: opts.on_tool_start,
        on_tool_end: opts.on_tool_end
      }
    })
  end

  # ============================================================================
  # ReqLLM Integration
  # ============================================================================

  @doc """
  Returns a list of ReqLLM.Tool structs for the given options.

  This is the ReqLLM equivalent of `functions/1` which returns LangChain.Function structs.
  """
  def reqllm_functions(opts) do
    opts
    |> exposed_tools()
    |> Enum.map(fn tool_def ->
      {tool, _callback} = reqllm_tool(tool_def)
      tool
    end)
  end

  @doc """
  Builds a ReqLLM.Tool and callback function from an AshAi.Tool definition.

  Delegates to `AshAi.Tool.Builder.build/2`.

  Returns a tuple of `{ReqLLM.Tool, callback_fn}` where:
  - `ReqLLM.Tool` contains the tool schema for the LLM
  - `callback_fn` is a function/2 that takes (arguments, context) and executes the Ash action

  ## Example

      {tool, callback} = AshAi.reqllm_tool(tool_def)
      result = callback.(%{"input" => %{"name" => "foo"}}, %{actor: current_user})
  """
  def reqllm_tool(%Tool{} = tool_def) do
    AshAi.Tool.Builder.build(tool_def)
  end

  # ============================================================================
  # IEx Chat
  # ============================================================================

  @doc """
  Interactive IEx chat using ReqLLM.

  The first `lang_chain` argument is ignored and kept only for backward compatibility.
  Use the `:model` option to specify which LLM to use (defaults to "openai:gpt-4o-mini").

  ## Example

      # Using default model
      iex_chat(nil, otp_app: :my_app)

      # Using a specific model
      iex_chat(nil, otp_app: :my_app, model: "anthropic:claude-haiku-4-5")

      # With a custom system prompt
      iex_chat(nil,
        otp_app: :my_app,
        system_prompt: fn _opts -> "You are a helpful coding assistant." end
      )
  """
  def iex_chat(_lang_chain \\ nil, opts \\ []) do
    opts = Options.validate!(opts)

    base_messages =
      case opts.system_prompt do
        :none ->
          []

        nil ->
          [
            Context.system("""
            You are a helpful assistant.
            Your purpose is to operate the application on behalf of the user.
            """)
          ]

        system_prompt when is_function(system_prompt, 1) ->
          [Context.system(system_prompt.(opts))]
      end

    {tools, tool_registry} = AshAi.Tools.build_tools_and_registry(opts)

    run_iex_loop(opts.model, base_messages, tools, tool_registry, opts, true)
  end

  defp run_iex_loop(model, messages, tools, registry, opts, first?) do
    req_llm = opts.req_llm
    {:ok, response} = req_llm.stream_text(model, messages, tools: tools)

    acc = %{text: "", tool_calls: []}

    acc =
      response.stream
      |> Enum.reduce(acc, fn chunk, acc ->
        case chunk.type do
          :content ->
            text = chunk.text || ""
            IO.write(text)
            %{acc | text: acc.text <> text}

          :tool_call ->
            tc = %{id: chunk.id, name: chunk.name, arguments: chunk.arguments}
            %{acc | tool_calls: acc.tool_calls ++ [tc]}

          _ ->
            acc
        end
      end)

    if acc.tool_calls != [] do
      assistant_with_tools =
        Context.assistant(%{
          tool_calls:
            Enum.map(acc.tool_calls, fn tc ->
              %{
                id: tc.id,
                type: "function",
                function: %{name: tc.name, arguments: tc.arguments}
              }
            end)
        })

      messages = messages ++ [assistant_with_tools]

      ctx = %{
        actor: opts.actor,
        tenant: opts.tenant,
        context: opts.context || %{},
        tool_callbacks: %{on_tool_start: opts.on_tool_start, on_tool_end: opts.on_tool_end}
      }

      messages = run_iex_tools(acc.tool_calls, messages, registry, ctx)

      run_iex_loop(model, messages, tools, registry, opts, false)
    else
      messages =
        if acc.text != "" do
          messages ++ [Context.assistant(acc.text)]
        else
          messages
        end

      if !first? do
        IO.write("\n")
      end

      user_message = get_user_message()
      messages = messages ++ [Context.user(user_message)]
      run_iex_loop(model, messages, tools, registry, opts, false)
    end
  end

  defp run_iex_tools(tool_calls, messages, registry, ctx) do
    Enum.reduce(tool_calls, messages, fn tc, msgs ->
      fun = Map.get(registry, tc.name)

      if is_nil(fun) do
        msgs ++ [Context.tool_result(tc.id, Jason.encode!(%{error: "Unknown tool: #{tc.name}"}))]
      else
        args =
          case tc.arguments do
            s when is_binary(s) -> Jason.decode!(s)
            m -> m
          end

        result =
          try do
            fun.(args, ctx)
          rescue
            e ->
              {:error, Jason.encode!(%{error: Exception.message(e)})}
          end

        content =
          case result do
            {:ok, content, _raw} -> content
            {:error, content} -> content
          end

        msgs ++ [Context.tool_result(tc.id, content)]
      end
    end)
  end

  defp get_user_message do
    case Mix.shell().prompt("> ") do
      nil -> get_user_message()
      "" -> get_user_message()
      "\n" -> get_user_message()
      message -> message
    end
  end

  # ============================================================================
  # Error Handling
  # ============================================================================

  def to_json_api_errors(domain, resource, errors, type) when is_list(errors) do
    Enum.flat_map(errors, &to_json_api_errors(domain, resource, &1, type))
  end

  def to_json_api_errors(domain, resource, %mod{errors: errors}, type)
      when mod in [Forbidden, Framework, Invalid, Unknown] do
    Enum.flat_map(errors, &to_json_api_errors(domain, resource, &1, type))
  end

  def to_json_api_errors(_domain, _resource, %AshJsonApi.Error{} = error, _type) do
    [error]
  end

  def to_json_api_errors(domain, _resource, %{class: :invalid} = error, _type) do
    if AshJsonApi.ToJsonApiError.impl_for(error) do
      error
      |> AshJsonApi.ToJsonApiError.to_json_api_error()
      |> List.wrap()
      |> Enum.flat_map(&with_source_pointer(&1, error))
    else
      uuid = Ash.UUID.generate()

      stacktrace =
        case error do
          %{stacktrace: %{stacktrace: v}} ->
            v

          _ ->
            nil
        end

      Logger.warning(
        "`#{uuid}`: AshJsonApi.Error not implemented for error:\n\n#{Exception.format(:error, error, stacktrace)}"
      )

      if AshJsonApi.Domain.Info.show_raised_errors?(domain) do
        [
          %AshJsonApi.Error{
            id: uuid,
            status_code: class_to_status(error.class),
            code: "something_went_wrong",
            title: "SomethingWentWrong",
            detail: """
            Raised error: #{uuid}

            #{Exception.format(:error, error, stacktrace)}"
            """
          }
        ]
      else
        [
          %AshJsonApi.Error{
            id: uuid,
            status_code: class_to_status(error.class),
            code: "something_went_wrong",
            title: "SomethingWentWrong",
            detail: "Something went wrong. Error id: #{uuid}"
          }
        ]
      end
    end
  end

  def to_json_api_errors(_domain, _resource, %{class: :forbidden} = error, _type) do
    [
      %AshJsonApi.Error{
        id: Ash.UUID.generate(),
        status_code: class_to_status(error.class),
        code: "forbidden",
        title: "Forbidden",
        detail: "forbidden"
      }
    ]
  end

  def to_json_api_errors(_domain, _resource, error, _type) do
    uuid = Ash.UUID.generate()

    stacktrace =
      case error do
        %{stacktrace: %{stacktrace: v}} ->
          v

        _ ->
          nil
      end

    Logger.warning(
      "`#{uuid}`: AshJsonApi.Error not implemented for error:\n\n#{Exception.format(:error, error, stacktrace)}"
    )

    [
      %AshJsonApi.Error{
        id: uuid,
        status_code: class_to_status(error.class),
        code: "something_went_wrong",
        title: "SomethingWentWrong",
        detail: "Something went wrong. Error id: #{uuid}"
      }
    ]
  end

  @doc "Turns an error class into an HTTP status code"
  def class_to_status(:forbidden), do: 403
  def class_to_status(:invalid), do: 400
  def class_to_status(_), do: 500

  def with_source_pointer(%{source_pointer: source_pointer} = built_error, _)
      when source_pointer not in [nil, :undefined] do
    [built_error]
  end

  def with_source_pointer(built_error, %{fields: fields, path: path})
      when is_list(fields) and fields != [] do
    Enum.map(fields, fn field ->
      %{built_error | source_pointer: source_pointer(field, path)}
    end)
  end

  def with_source_pointer(built_error, %{field: field, path: path})
      when not is_nil(field) do
    [
      %{built_error | source_pointer: source_pointer(field, path)}
    ]
  end

  def with_source_pointer(built_error, _) do
    [built_error]
  end

  defp source_pointer(field, path) do
    "/input/#{Enum.join(List.wrap(path) ++ [field], "/")}"
  end

  # ============================================================================
  # MCP Resources
  # ============================================================================

  @doc false
  def exposed_mcp_resources(opts) when is_list(opts) do
    exposed_mcp_resources(Options.validate!(opts))
  end

  def exposed_mcp_resources(opts) do
    if !opts.otp_app and !opts.actions do
      raise "Must specify `otp_app` if you do not specify `actions`"
    end

    domains =
      if opts.actions do
        opts.actions
        |> Enum.map(fn {resource, _actions} ->
          domain = Ash.Resource.Info.domain(resource)

          if !domain do
            raise "Cannot use an ash resource that does not have a domain"
          end

          domain
        end)
        |> Enum.uniq()
      else
        Application.get_env(opts.otp_app, :ash_domains) || []
      end

    domains
    |> Enum.flat_map(fn domain ->
      domain
      |> AshAi.Info.mcp_resources()
      |> Enum.filter(fn mcp_resource ->
        valid_mcp_resource(mcp_resource, opts.mcp_resources, opts.actions, opts.exclude_actions)
      end)
      |> Enum.map(fn mcp_resource ->
        action = Ash.Resource.Info.action(mcp_resource.resource, mcp_resource.action)

        %{
          mcp_resource
          | domain: domain,
            action: action,
            description: mcp_resource.description || action.description
        }
      end)
    end)
  end

  defp valid_mcp_resource(mcp_resource, allowed_mcp_resources, allowed_actions, exclude_actions) do
    passes_mcp_resources_filter =
      case allowed_mcp_resources do
        [:*] -> true
        :* -> true
        nil -> true
        [] -> false
        list when is_list(list) -> Enum.member?(list, mcp_resource.name)
      end

    passes_actions_filter =
      if allowed_actions && allowed_actions != [] do
        Enum.any?(allowed_actions, fn
          {resource, :*} ->
            mcp_resource.resource == resource

          {resource, actions} when is_list(actions) ->
            mcp_resource.resource == resource && mcp_resource.action in actions
        end)
      else
        true
      end

    is_excluded =
      if exclude_actions && exclude_actions != [] do
        Enum.any?(exclude_actions, fn {resource, action} ->
          mcp_resource.resource == resource && mcp_resource.action == action
        end)
      else
        false
      end

    passes_mcp_resources_filter && passes_actions_filter && !is_excluded
  end

  # ============================================================================
  # Tool Discovery
  # ============================================================================

  def exposed_tools(opts) when is_list(opts) do
    exposed_tools(Options.validate!(opts))
  end

  def exposed_tools(opts) do
    if opts.actions do
      Enum.flat_map(opts.actions, fn
        {resource, actions} ->
          domain = Ash.Resource.Info.domain(resource)

          if !domain do
            raise "Cannot use an ash resource that does not have a domain"
          end

          tools = AshAi.Info.tools(domain)

          if !Enum.any?(tools, fn tool ->
               tool.resource == resource && (actions == :* || tool.action in actions)
             end) do
            raise "Cannot use an action that is not exposed as a tool"
          end

          if actions == :* do
            tools
            |> Enum.filter(&(&1.resource == resource))
            |> Enum.map(fn tool ->
              %{tool | domain: domain, action: Ash.Resource.Info.action(resource, tool.action)}
            end)
          else
            tools
            |> Enum.filter(&(&1.resource == resource && &1.action in actions))
            |> Enum.map(fn tool ->
              %{tool | domain: domain, action: Ash.Resource.Info.action(resource, tool.action)}
            end)
          end
      end)
    else
      if !opts.otp_app do
        raise "Must specify `otp_app` if you do not specify `actions`"
      end

      for domain <- Application.get_env(opts.otp_app, :ash_domains) || [],
          tool <- AshAi.Info.tools(domain) do
        %{tool | domain: domain, action: Ash.Resource.Info.action(tool.resource, tool.action)}
      end
    end
    |> Enum.uniq()
    |> then(fn tools ->
      if is_list(opts.exclude_actions) do
        Enum.reject(tools, fn tool ->
          {tool.resource, tool.action.name} in opts.exclude_actions
        end)
      else
        tools
      end
    end)
    |> then(fn tools ->
      if allowed_tools = opts.tools do
        Enum.filter(tools, fn tool ->
          tool.name in List.wrap(allowed_tools)
        end)
      else
        tools
      end
    end)
    |> Enum.filter(
      &can?(
        opts.actor,
        &1.domain,
        &1.resource,
        &1.action,
        opts.tenant
      )
    )
  end

  # ============================================================================
  # Vectorization
  # ============================================================================

  def has_vectorize_change?(%Ash.Changeset{} = changeset) do
    full_text_attrs =
      AshAi.Info.vectorize(changeset.resource) |> Enum.flat_map(& &1.used_attributes)

    vectorized_attrs =
      AshAi.Info.vectorize_attributes!(changeset.resource)
      |> Enum.map(fn {attr, _} -> attr end)

    Enum.any?(vectorized_attrs ++ full_text_attrs, fn attr ->
      Ash.Changeset.changing_attribute?(changeset, attr)
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp can?(actor, domain, resource, action, tenant) do
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
