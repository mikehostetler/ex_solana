defmodule Jido.AI.Directive do
  @moduledoc """
  Generic LLM-related directives for Jido agents.

  These directives are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They represent side effects that the AgentServer runtime should execute.

  ## Available Directives

  - `Jido.AI.Directive.LLMStream` - Stream an LLM response with optional tool support
  - `Jido.AI.Directive.ToolExec` - Execute a Jido.Action as a tool

  ## Usage

      alias Jido.AI.Directive

      # Create an LLM streaming directive
      directive = Directive.LLMStream.new!(%{
        id: "call_123",
        model: "anthropic:claude-haiku-4-5",
        context: messages,
        tools: tools
      })

      # Create a tool execution directive
      directive = Directive.ToolExec.new!(%{
        id: "tool_456",
        tool_name: "calculator",
        action_module: MyApp.Actions.Calculator,
        arguments: %{a: 1, b: 2, operation: "add"}
      })
  """

  defmodule LLMStream do
    @moduledoc """
    Directive asking the runtime to stream an LLM response.

    Uses ReqLLM for streaming. The runtime will execute this asynchronously
    and send the result back as an `ai.llm_result` signal.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model: Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4-5'"),
                context: Zoi.any(description: "List of messages or ReqLLM.Context"),
                tools:
                  Zoi.list(Zoi.any(), description: "List of ReqLLM.Tool definitions")
                  |> Zoi.default([]),
                tool_choice:
                  Zoi.any(description: "Tool choice: :auto | :none | {:required, name}")
                  |> Zoi.default(:auto),
                max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
                temperature: Zoi.number(description: "Sampling temperature") |> Zoi.default(0.2),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema

    @doc "Create a new LLMStream directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid LLMStream: #{inspect(errors)}"
      end
    end
  end

  defmodule ToolExec do
    @moduledoc """
    Directive to execute a Jido.Action as a tool.

    The runtime will execute this asynchronously and send the result back
    as an `ai.tool_result` signal.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Tool call ID from LLM for correlation"),
                tool_name: Zoi.string(description: "Name of the tool being called"),
                action_module: Zoi.any(description: "The Jido.Action module to execute"),
                arguments: Zoi.map(description: "Arguments for the action") |> Zoi.default(%{}),
                context: Zoi.map(description: "Execution context for the action") |> Zoi.default(%{}),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema

    @doc "Create a new ToolExec directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ToolExec: #{inspect(errors)}"
      end
    end
  end
end
