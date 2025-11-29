# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi do
  @moduledoc """
  Documentation for `AshAi`.
  """

  alias AshAi.Tool.Errors
  alias ReqLLM.Context

  defstruct []

  require Logger
  require Ash.Expr

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

  @full_text %Spark.Dsl.Entity{
    name: :full_text,
    imports: [Ash.Expr],
    target: FullText,
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        default: :full_text_vector,
        doc: "The name of the attribute to store the text vector in"
      ],
      used_attributes: [
        type: {:list, :atom},
        doc: "If set, a vector is only regenerated when these attributes are changed"
      ],
      text: [
        type: {:fun, 1},
        required: true,
        doc:
          "A function or expr that takes a list of records and computes a full text string that will be vectorized. If given an expr, use `atomic_ref` to refer to new values, as this is set as an atomic update."
      ]
    ]
  }

  @vectorize %Spark.Dsl.Section{
    name: :vectorize,
    entities: [
      @full_text
    ],
    schema: [
      attributes: [
        type: :keyword_list,
        doc:
          "A keyword list of attributes to vectorize, and the name of the attribute to store the vector in",
        default: []
      ],
      strategy: [
        type: {:one_of, [:after_action, :manual, :ash_oban, :ash_oban_manual]},
        default: :after_action,
        doc:
          "How to compute the vector. Currently supported strategies are `:after_action`, `:manual`, and `:ash_oban`."
      ],
      define_update_action_for_manual_strategy?: [
        type: :boolean,
        default: true,
        doc:
          "If true, an `ash_ai_update_embeddings` update action will be defined, which will automatically update the embeddings when run."
      ],
      ash_oban_trigger_name: [
        type: :atom,
        default: :ash_ai_update_embeddings,
        doc:
          "The name of the AshOban-trigger that will be run in order to update the record's embeddings. Defaults to `:ash_ai_update_embeddings`."
      ],
      embedding_model: [
        type: {:spark_behaviour, AshAi.EmbeddingModel},
        required: true
      ]
    ]
  }

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
      __spark_metadata__: nil
    ]
  end

  defmodule ToolStartEvent do
    @moduledoc """
    Event data passed to the `on_tool_start` callback passed to `AshAi.setup_ash_ai/2`.

    Contains information about the tool execution that is about to begin.
    """
    @type t :: %__MODULE__{
            tool_name: String.t(),
            action: atom(),
            resource: module(),
            arguments: map(),
            actor: any() | nil,
            tenant: any() | nil
          }

    defstruct [:tool_name, :action, :resource, :arguments, :actor, :tenant]
  end

  defmodule ToolEndEvent do
    @moduledoc """
    Event data passed to the `on_tool_end` callback passed to `AshAi.setup_ash_ai/2`.

    Contains the tool name and execution result.
    """
    @type t :: %__MODULE__{
            tool_name: String.t(),
            result: {:ok, String.t(), any()} | {:error, String.t()}
          }

    defstruct [:tool_name, :result]
  end

  @tool %Spark.Dsl.Entity{
    name: :tool,
    target: Tool,
    describe: """
    Expose an Ash action as a tool that can be called by LLMs.

    Tools allow LLMs to interact with your application by calling specific actions on resources.
    Only public attributes can be used for filtering, sorting, and aggregation, but the `load`
    option allows including private attributes in the response data.
    """,
    schema: [
      name: [type: :atom, required: true],
      resource: [type: {:spark, Ash.Resource}, required: true],
      action: [type: :atom, required: true],
      action_parameters: [
        type: {:list, :atom},
        required: false,
        doc:
          "A list of action specific parameters to allow for the underlying action. Only relevant for reads, and defaults to allowing `[:sort, :offset, :limit, :result_type, :filter]`"
      ],
      load: [
        type: :any,
        default: [],
        doc:
          "A list of relationships and calculations to load on the returned records. Note that loaded fields can include private attributes, which will then be included in the tool's response. However, private attributes cannot be used for filtering, sorting, or aggregation."
      ],
      async: [type: :boolean, default: true],
      description: [
        type: :string,
        doc: "A description for the tool. Defaults to the action's description."
      ],
      identity: [
        type: :atom,
        default: nil,
        doc:
          "The identity to use for update/destroy actions. Defaults to the primary key. Set to `false` to disable entirely."
      ]
    ],
    args: [:name, :resource, :action]
  }

  @tools %Spark.Dsl.Section{
    name: :tools,
    entities: [
      @tool
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@tools, @vectorize],
    imports: [AshAi.Actions],
    transformers: [AshAi.Transformers.Vectorize]

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
        model: [
          type: :string,
          default: "openai:gpt-4o-mini",
          doc: """
          The LLM model to use for chat. Format: "provider:model-name".
          Examples: "openai:gpt-4o-mini", "anthropic:claude-haiku-4-5", "openai:gpt-4o".
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
        req_llm: [
          type: :atom,
          default: ReqLLM,
          doc: """
          The ReqLLM module to use for LLM operations. Defaults to `ReqLLM`.

          This is primarily intended for testing purposes, allowing you to inject
          a mock ReqLLM implementation to control responses and validate behavior
          without making actual API calls.

          Example for testing:
          ```
          iex_chat(nil, req_llm: FakeReqLLM, ...)
          ```
          """
        ]
      ]
  end

  def functions(opts) do
    opts
    |> exposed_tools()
    |> Enum.map(fn tool_def ->
      {tool, _callback} = tool(tool_def)
      tool
    end)
  end

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

    {tools, tool_registry} = build_tools_and_registry(opts)

    run_loop(opts.model, base_messages, tools, tool_registry, opts, true)
  end

  defp build_tools_and_registry(opts) do
    # Get tool definitions from DSL and convert to {tool, callback} tuples
    tool_tuples =
      opts
      |> exposed_tools()
      |> Enum.map(&tool/1)

    # Separate tools and callbacks
    {tools, callbacks} = Enum.unzip(tool_tuples)

    # Build registry mapping tool name to callback function (function/2)
    registry =
      Enum.zip(tools, callbacks)
      |> Enum.into(%{}, fn {tool, callback} -> {tool.name, callback} end)

    {tools, registry}
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

    # LangChain integration (deprecated - use iex_chat for ReqLLM integration)
    lang_chain
    |> LangChain.Chains.LLMChain.add_tools(tools)
    |> LangChain.Chains.LLMChain.update_custom_context(%{
      actor: opts.actor,
      tenant: opts.tenant,
      context: opts.context,
      tool_callbacks: %{
        on_tool_start: opts.on_tool_start,
        on_tool_end: opts.on_tool_end
      }
    })
  end

  defp run_loop(model, messages, tools, registry, opts, _first?) do
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

    cond do
      acc.tool_calls != [] ->
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

        messages =
          Enum.reduce(acc.tool_calls, messages, fn tc, msgs ->
            fun = Map.get(registry, tc.name)

            if is_nil(fun) do
              msgs ++
                [
                  Context.tool_result(tc.id, Jason.encode!(%{error: "Unknown tool: #{tc.name}"}))
                ]
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

        run_loop(model, messages, tools, registry, opts, false)

      true ->
        messages =
          if acc.text != "" do
            messages ++ [Context.assistant(acc.text)]
          else
            messages
          end

        IO.write("\n")

        user_message = get_user_message()
        messages = messages ++ [Context.user(user_message)]
        run_loop(model, messages, tools, registry, opts, false)
    end
  end

  defp get_user_message do
    case Mix.shell().prompt("> ") do
      nil -> get_user_message()
      "" -> get_user_message()
      "\n" -> get_user_message()
      message -> message
    end
  end

  # Create a ReqLLM.Tool and callback from an AshAi.Tool DSL entity
  # Returns {tool, callback} tuple where callback is function/2
  @deprecated "Use AshAi.Tool.Builder.build/2 instead"
  @doc false
  def tool(%Tool{} = tool_def) do
    AshAi.Tool.Builder.build(tool_def, %{})
  end

  defdelegate to_json_api_errors(domain, resource, errors, type), to: Errors
  defdelegate class_to_status(class), to: Errors
  defdelegate serialize_errors(errors), to: Errors
  defdelegate with_source_pointer(built_error, error), to: Errors
  defdelegate source_pointer(field, path), to: Errors

  @deprecated "Use AshAi.Tools.discovery/1 instead"
  @doc false
  def exposed_tools(opts) when is_list(opts) do
    exposed_tools(Options.validate!(opts))
  end

  @deprecated "Use AshAi.Tools.discovery/1 instead"
  def exposed_tools(opts) do
    # Convert struct to map if needed
    opts_map =
      if is_struct(opts) do
        Map.from_struct(opts)
      else
        opts
      end

    AshAi.Tools.discovery(opts_map)
  end

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
end
