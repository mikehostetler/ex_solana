# Jido ReAct Agent Implementation Plan

**Goal**: Build an LLM agent implementing the ReAct (Reason-Act) pattern using Jido core + ReqLLM integration.

**Status**: Ready for Implementation  
**Effort**: L (1-2 days)  
**Location**: `projects/jido/lib/jido/examples/react/` (example code, not core)  
**Last Updated**: 2024-12-30 (v3: streaming, Zoi structs, Jido.Action tools)

---

## Overview

This is the most complex and important integration test for the Jido framework. It demonstrates:

- Agent + AgentServer runtime
- Custom Strategy with `__strategy__` state machine
- Custom directives + DirectiveExec protocol implementations  
- **Streaming LLM responses** via `ReqLLM.stream_text/3`
- **Jido.Action-based tools** with `to_tool()` conversion
- **Zoi schemas** for all struct definitions
- Signal-based feedback loop for multi-step reasoning
- Proper Elm/Redux architecture adherence

The code will eventually be refined and moved to `jido_ai`, but for now lives as an example in the jido project.

---

## Architecture

### Data Flow Diagram

```
User (CLI/test)
  │
  ▼
Jido.Signal "react.user_query"
  │
  ▼
Jido.AgentServer.call/cast
  │
  ▼
ReAct Agent.handle_signal/2
  │
  ▼
Agent.cmd/2  ───► Strategy: ReAct.Strategy.cmd/3
                           │
                           ▼
                  Directives: [%LLMStream{}, %ToolExec{}, ...]
                           │
                           ▼
                  AgentServer directive queue
                           │
                           ▼
               DirectiveExec for LLMStream / ToolExec
                           │
                           ▼
          LLMClient.stream_text → StreamResponse
                           │
                (async Task via Jido.TaskSupervisor)
                           │
                           ▼  (consumes stream, extracts tool_calls or text)
                      New Jido.Signal:
         - "react.llm_result"   (from LLMStream)
         - "react.tool_result"  (from ToolExec)
                           │
                           ▼
         Jido.AgentServer.cast(..., signal)
                           │
                           ▼
                   ReAct Agent.handle_signal/2
                           │
                           ▼
           Agent.cmd/2 → Strategy.cmd/3 (next step)
                           │
                           ▼
          ... repeat until Final Answer or max_iterations ...
                           │
                           ▼
             Strategy emits "react.final_answer" & Stop
```

### Module Structure

```
projects/jido/lib/jido/examples/react/
├── strategy.ex              # ReAct Strategy implementation
├── strategy_state.ex        # State helpers wrapping Jido.Agent.Strategy.State
├── directives.ex            # LLMStream and ToolExec directive structs (Zoi)
├── directive_exec.ex        # DirectiveExec protocol implementations
├── llm_client.ex            # LLMClient behaviour + ReqLLM implementation
├── agent.ex                 # ReAct Agent module
├── actions/                 # Jido.Action-based tools
│   ├── calculator.ex        # Calculator action
│   └── weather.ex           # Weather action  
├── tools.ex                 # Tool registry (converts Actions to tools)
├── signals.ex               # Signal constructors
└── types.ex                 # Shared Zoi types

projects/jido/examples/
└── react_agent.exs          # Standalone runner script

projects/jido/test/jido/examples/react/
├── strategy_test.exs        # Unit tests for strategy state machine
├── integration_test.exs     # Full loop with mock client
└── support/
    └── mock_llm_client.ex   # Mock implementation for testing
```

---

## Components

### 1. Shared Types (Zoi Schemas)

```elixir
defmodule Jido.Examples.ReAct.Types do
  @moduledoc """
  Shared Zoi types for ReAct agent.
  """

  @type status :: :idle | :awaiting_llm | :awaiting_tool | :completed | :error
  @type termination_reason :: :final_answer | :max_iterations | :error | nil

  @doc "Zoi schema for tool call from LLM."
  def tool_call_schema do
    Zoi.object(%{
      id: Zoi.string(description: "Tool call ID from LLM"),
      name: Zoi.string(description: "Tool name"),
      arguments: Zoi.map(description: "Tool arguments") |> Zoi.default(%{})
    })
  end

  @doc "Zoi schema for pending tool call tracking."
  def pending_tool_call_schema do
    Zoi.object(%{
      name: Zoi.string(description: "Tool name"),
      arguments: Zoi.map(description: "Tool arguments"),
      result: Zoi.any(description: "Tool result") |> Zoi.optional()
    })
  end
end
```

---

### 2. LLM Client Behaviour (Streaming)

**Purpose**: Decouple DirectiveExec from ReqLLM for testability. Uses `stream_text/3`.

```elixir
defmodule Jido.Examples.ReAct.LLMClient do
  @moduledoc """
  Behaviour for LLM streaming and tool execution.
  Allows swapping ReqLLM with mocks in tests.
  """

  @callback stream_text(
              model :: String.t(),
              context :: term(),
              opts :: keyword()
            ) :: {:ok, ReqLLM.StreamResponse.t()} | {:error, term()}

  @callback execute_action(
              action_module :: module(),
              arguments :: map(),
              context :: map()
            ) :: {:ok, term()} | {:error, term()}
end

defmodule Jido.Examples.ReAct.LLMClient.ReqLLM do
  @moduledoc """
  Production implementation using ReqLLM streaming.
  """
  @behaviour Jido.Examples.ReAct.LLMClient

  @impl true
  def stream_text(model, context, opts) do
    ReqLLM.stream_text(model, context, opts)
  end

  @impl true
  def execute_action(action_module, arguments, context) do
    # Use Jido.Exec to run the action
    Jido.Exec.run(action_module, arguments, context)
  end
end

defmodule Jido.Examples.ReAct.LLMClient.Mock do
  @moduledoc """
  Mock implementation for testing.
  Configure responses via process dictionary.
  """
  @behaviour Jido.Examples.ReAct.LLMClient

  @impl true
  def stream_text(_model, _context, _opts) do
    case Process.get(:mock_stream_response) do
      nil -> {:error, :no_mock_configured}
      response -> response
    end
  end

  @impl true
  def execute_action(action_module, arguments, _context) do
    case Process.get({:mock_action_response, action_module}) do
      nil -> {:ok, %{result: "mocked result for #{inspect(action_module)}"}}
      response -> response
    end
  end
end
```

---

### 3. Custom Directives (Zoi Schemas)

#### `Jido.Examples.ReAct.Directive.LLMStream`

Request a streaming LLM completion via ReqLLM.

```elixir
defmodule Jido.Examples.ReAct.Directive.LLMStream do
  @moduledoc """
  Directive asking the runtime to stream an LLM response.
  Uses ReqLLM.stream_text/3 for streaming responses.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique call ID / correlation ID"),
              model: Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4.5'"),
              context: Zoi.any(description: "ReqLLM.Context.t() or list of messages"),
              tools: Zoi.list(Zoi.any(), description: "List of tool definitions") |> Zoi.default([]),
              tool_choice:
                Zoi.any(description: "Tool choice: :auto | :none | {:required, name}")
                |> Zoi.default(:auto),
              max_tokens: Zoi.integer(description: "Max tokens") |> Zoi.default(1024),
              temperature: Zoi.number(description: "Temperature") |> Zoi.default(0.2),
              metadata: Zoi.map(description: "Arbitrary metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @doc "Create a new LLMStream directive."
  def new!(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid LLMStream: #{inspect(errors)}"
    end
  end
end
```

#### `Jido.Examples.ReAct.Directive.ToolExec`

Execute a Jido.Action-based tool.

```elixir
defmodule Jido.Examples.ReAct.Directive.ToolExec do
  @moduledoc """
  Directive asking the runtime to execute a Jido.Action tool.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Tool call ID from LLM"),
              tool_name: Zoi.string(description: "Tool name (matches Action name)"),
              action_module: Zoi.any(description: "The Jido.Action module to execute"),
              arguments: Zoi.map(description: "Arguments for the action") |> Zoi.default(%{}),
              metadata: Zoi.map(description: "Trace metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @doc "Create a new ToolExec directive."
  def new!(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid ToolExec: #{inspect(errors)}"
    end
  end
end
```

---

### 4. DirectiveExec Protocol Implementations

#### LLMStream Executor (Streaming)

Calls `LLMClient.stream_text`, consumes the stream, extracts results.

```elixir
defimpl Jido.AgentServer.DirectiveExec,
  for: Jido.Examples.ReAct.Directive.LLMStream do

  require Logger

  alias Jido.Examples.ReAct.Signals
  alias ReqLLM.StreamResponse

  @client Application.compile_env(
            :jido,
            :react_llm_client,
            Jido.Examples.ReAct.LLMClient.ReqLLM
          )

  def exec(
        %{
          id: id,
          model: model,
          context: ctx,
          tools: tools,
          tool_choice: tool_choice,
          max_tokens: max_tokens,
          temperature: temperature
        } = _directive,
        _signal,
        state
      ) do
    agent_id = state.id

    opts = [
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature
    ]

    case Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
           case @client.stream_text(model, ctx, opts) do
             {:ok, stream_response} ->
               # Consume stream and extract results
               result = consume_stream(stream_response)

               signal =
                 Signals.llm_result(%{
                   call_id: id,
                   result: {:ok, result}
                 })

               Jido.AgentServer.cast(agent_id, signal)

             {:error, reason} ->
               signal =
                 Signals.llm_result(%{
                   call_id: id,
                   result: {:error, reason}
                 })

               Jido.AgentServer.cast(agent_id, signal)
           end
         end) do
      {:ok, _pid} ->
        {:async, nil, state}

      {:error, reason} ->
        Logger.error("Failed to start LLM stream task: #{inspect(reason)}")
        error_signal =
          Signals.llm_result(%{
            call_id: id,
            result: {:error, {:task_supervisor_failed, reason}}
          })

        Jido.AgentServer.cast(agent_id, error_signal)
        {:ok, state}
    end
  end

  # Consume the stream and extract text + tool_calls
  defp consume_stream(stream_response) do
    # Extract tool calls (consumes stream)
    tool_calls = StreamResponse.extract_tool_calls(stream_response)

    if tool_calls != [] do
      # LLM wants to use tools
      %{
        type: :tool_calls,
        tool_calls: tool_calls,
        text: nil
      }
    else
      # Get the full text (stream already consumed by extract_tool_calls,
      # so we need a different approach)
      # Actually, extract_tool_calls consumes the stream, so we need to
      # collect both in one pass
      %{
        type: :final_answer,
        tool_calls: [],
        text: StreamResponse.text(stream_response)
      }
    end
  end
end
```

**Note**: The stream consumption needs refinement - we need to collect both text and tool_calls in a single pass. Updated implementation:

```elixir
  # Consume the stream once and extract both text and tool_calls
  defp consume_stream(stream_response) do
    # Collect all chunks
    chunks = Enum.to_list(stream_response.stream)

    # Extract tool calls from chunks
    tool_calls =
      chunks
      |> Enum.filter(&(&1.type == :tool_call))
      |> Enum.map(fn chunk ->
        %{
          id: Map.get(chunk.metadata, :id) || "call_#{:erlang.unique_integer()}",
          name: chunk.name,
          arguments: chunk.arguments || %{}
        }
      end)

    # Extract text from content chunks
    text =
      chunks
      |> Enum.filter(&(&1.type == :content))
      |> Enum.map_join("", & &1.text)

    if tool_calls != [] do
      %{type: :tool_calls, tool_calls: tool_calls, text: text}
    else
      %{type: :final_answer, tool_calls: [], text: text}
    end
  end
```

#### ToolExec Executor (Jido.Action)

Executes a Jido.Action via `Jido.Exec.run/3`.

```elixir
defimpl Jido.AgentServer.DirectiveExec,
  for: Jido.Examples.ReAct.Directive.ToolExec do

  require Logger

  alias Jido.Examples.ReAct.Signals

  @client Application.compile_env(
            :jido,
            :react_llm_client,
            Jido.Examples.ReAct.LLMClient.ReqLLM
          )

  def exec(
        %{id: id, action_module: action_module, arguments: args, tool_name: name} = _directive,
        _signal,
        state
      ) do
    agent_id = state.id

    case Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
           # Execute the Jido.Action
           result = @client.execute_action(action_module, args, %{agent_id: agent_id})

           signal =
             Signals.tool_result(%{
               call_id: id,
               tool_name: name,
               result: result
             })

           Jido.AgentServer.cast(agent_id, signal)
         end) do
      {:ok, _pid} ->
        {:async, nil, state}

      {:error, reason} ->
        Logger.error("Failed to start tool task: #{inspect(reason)}")
        error_signal =
          Signals.tool_result(%{
            call_id: id,
            tool_name: name,
            result: {:error, {:task_supervisor_failed, reason}}
          })

        Jido.AgentServer.cast(agent_id, error_signal)
        {:ok, state}
    end
  end
end
```

---

### 5. Jido.Action-Based Tools

#### Calculator Action

```elixir
defmodule Jido.Examples.ReAct.Actions.Calculator do
  @moduledoc """
  Calculator action for evaluating arithmetic expressions.
  Uses Jido.Action for proper schema validation and tool conversion.
  """

  use Jido.Action,
    name: "calculator",
    description: "Evaluate arithmetic expressions. Use for any math calculations.",
    schema: Zoi.object(%{
      expression: Zoi.string(description: "Math expression to evaluate, e.g. '(3 + 5) * 7'")
    })

  @impl true
  def run(params, _context) do
    expr = params.expression

    case Abacus.eval(expr) do
      {:ok, result} ->
        {:ok, %{result: result, expression: expr}}

      {:error, reason} ->
        {:error, "Invalid expression '#{expr}': #{inspect(reason)}"}
    end
  end
end
```

#### Weather Action

```elixir
defmodule Jido.Examples.ReAct.Actions.Weather do
  @moduledoc """
  Weather action for getting current weather (demo stub).
  Uses Jido.Action for proper schema validation and tool conversion.
  """

  use Jido.Action,
    name: "get_weather",
    description: "Get current weather for a city. Returns temperature and conditions.",
    schema: Zoi.object(%{
      location: Zoi.string(description: "City name, e.g. 'San Francisco'")
    })

  @impl true
  def run(params, _context) do
    location = params.location

    # Stub for demo purposes
    {:ok, %{
      location: location,
      temperature_celsius: 21,
      conditions: "sunny (demo data)"
    }}
  end
end
```

---

### 6. Tools Registry

Converts Jido.Actions to ReqLLM-compatible tools.

```elixir
defmodule Jido.Examples.ReAct.Tools do
  @moduledoc """
  Tool registry for ReAct agent.
  Converts Jido.Action modules to ReqLLM tool format.
  """

  alias Jido.Examples.ReAct.Actions.{Calculator, Weather}

  @actions [Calculator, Weather]

  @doc "Get all available actions."
  def actions, do: @actions

  @doc "Get all tools in ReqLLM format."
  def all do
    Enum.map(@actions, &action_to_tool/1)
  end

  @doc "Get action module by tool name."
  def get_action(tool_name) do
    Enum.find(@actions, fn action ->
      action.name() == tool_name
    end)
  end

  @doc "Get map of tool_name => action_module."
  def actions_by_name do
    Map.new(@actions, fn action -> {action.name(), action} end)
  end

  # Convert a Jido.Action to ReqLLM.Tool format
  defp action_to_tool(action_module) do
    tool_map = Jido.Action.Tool.to_tool(action_module)

    # Convert to ReqLLM.Tool struct
    ReqLLM.tool(
      name: tool_map.name,
      description: tool_map.description,
      parameters: action_module.schema(),
      callback: fn args ->
        # This callback is used by ReqLLM.Tool.execute/2
        # But we'll use Jido.Exec directly in DirectiveExec
        case Jido.Exec.run(action_module, args, %{}) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end
    )
  end
end
```

---

### 7. Strategy State Helper (Using Zoi)

```elixir
defmodule Jido.Examples.ReAct.StrategyState do
  @moduledoc """
  Helper for managing ReAct strategy state in agent.state.__strategy__.
  Built on top of Jido.Agent.Strategy.State. Uses Zoi for state schema.
  """

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: BaseState
  alias Jido.Examples.ReAct.Tools

  @schema Zoi.object(
            %{
              status:
                Zoi.enum([:idle, :awaiting_llm, :awaiting_tool, :completed, :error])
                |> Zoi.default(:idle),
              iteration: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
              max_iterations: Zoi.integer() |> Zoi.min(1) |> Zoi.default(10),
              conversation: Zoi.any(description: "ReqLLM.Context") |> Zoi.optional(),
              tools: Zoi.list(Zoi.any()) |> Zoi.default([]),
              actions_by_name: Zoi.map() |> Zoi.default(%{}),
              pending_tool_calls: Zoi.map() |> Zoi.default(%{}),
              current_llm_call_id: Zoi.string() |> Zoi.optional(),
              final_answer: Zoi.string() |> Zoi.optional(),
              termination_reason:
                Zoi.enum([:final_answer, :max_iterations, :error])
                |> Zoi.optional(),
              last_error: Zoi.any() |> Zoi.optional()
            },
            coerce: true
          )

  @type status :: :idle | :awaiting_llm | :awaiting_tool | :completed | :error
  @type t :: map()

  def schema, do: @schema

  @default_state %{
    status: :idle,
    iteration: 0,
    max_iterations: 10,
    conversation: nil,
    tools: [],
    actions_by_name: %{},
    pending_tool_calls: %{},
    current_llm_call_id: nil,
    final_answer: nil,
    termination_reason: nil,
    last_error: nil
  }

  @doc "Get strategy state with defaults."
  @spec get(Agent.t()) :: t()
  def get(%Agent{} = agent) do
    Map.merge(@default_state, BaseState.get(agent, %{}))
  end

  @doc "Put strategy state."
  @spec put(Agent.t(), t()) :: Agent.t()
  def put(%Agent{} = agent, state) when is_map(state) do
    BaseState.put(agent, state)
  end

  @doc "Update strategy state with a function."
  @spec update(Agent.t(), (t() -> t())) :: Agent.t()
  def update(%Agent{} = agent, fun) when is_function(fun, 1) do
    current = get(agent)
    put(agent, fun.(current))
  end

  @doc "Check if in terminal state (completed or error)."
  @spec terminal?(t()) :: boolean()
  def terminal?(%{status: status}), do: status in [:completed, :error]

  @doc "Generate unique call ID."
  @spec next_call_id() :: String.t()
  def next_call_id do
    "call-#{:erlang.unique_integer([:positive])}"
  end

  @doc "Initialize conversation with user query."
  @spec start_conversation(t(), String.t()) :: t()
  def start_conversation(state, query) do
    tools = Tools.all()
    actions_by_name = Tools.actions_by_name()

    context = ReqLLM.Context.new([
      ReqLLM.Context.system("""
      You are a helpful AI assistant with access to tools.
      Use tools when needed to answer questions accurately.
      After using tools, provide a clear final answer.
      """),
      ReqLLM.Context.user(query)
    ])

    %{state |
      status: :awaiting_llm,
      iteration: 1,
      conversation: context,
      tools: tools,
      actions_by_name: actions_by_name,
      pending_tool_calls: %{},
      current_llm_call_id: nil,
      final_answer: nil,
      termination_reason: nil,
      last_error: nil
    }
  end

  @doc "Append assistant message with tool calls to conversation."
  @spec append_assistant_tool_calls(t(), list()) :: t()
  def append_assistant_tool_calls(state, tool_calls) do
    # Create pending tool calls map
    pending = Map.new(tool_calls, fn tc ->
      {tc.id, %{name: tc.name, arguments: tc.arguments, result: nil}}
    end)

    %{state |
      pending_tool_calls: pending,
      status: :awaiting_tool
    }
  end

  @doc "Record tool result. Returns updated state and whether all tools complete."
  @spec record_tool_result(t(), String.t(), term()) :: {t(), boolean()}
  def record_tool_result(state, call_id, result) do
    case Map.get(state.pending_tool_calls, call_id) do
      nil ->
        # Stale or unknown call_id, ignore
        {state, false}

      tool_call ->
        updated_call = %{tool_call | result: result}
        pending = Map.put(state.pending_tool_calls, call_id, updated_call)
        state = %{state | pending_tool_calls: pending}

        # Check if all tools have results
        all_complete = Enum.all?(pending, fn {_id, tc} -> tc.result != nil end)
        {state, all_complete}
    end
  end

  @doc "Build context with all tool results appended."
  @spec append_all_tool_results(t()) :: t()
  def append_all_tool_results(state) do
    context =
      Enum.reduce(state.pending_tool_calls, state.conversation, fn {call_id, tc}, ctx ->
        result_str = case tc.result do
          {:ok, value} -> Jason.encode!(value)
          {:error, reason} -> "Error: #{inspect(reason)}"
        end
        ReqLLM.Context.append(ctx, ReqLLM.Context.tool_result(call_id, result_str))
      end)

    %{state |
      conversation: context,
      pending_tool_calls: %{},
      status: :awaiting_llm
    }
  end

  @doc "Set final answer and mark completed."
  @spec complete_with_answer(t(), String.t()) :: t()
  def complete_with_answer(state, answer) do
    %{state |
      status: :completed,
      final_answer: answer,
      termination_reason: :final_answer
    }
  end

  @doc "Mark completed due to max iterations."
  @spec complete_max_iterations(t(), String.t() | nil) :: t()
  def complete_max_iterations(state, partial_answer \\ nil) do
    %{state |
      status: :completed,
      final_answer: partial_answer || "Reached maximum iterations without final answer.",
      termination_reason: :max_iterations
    }
  end

  @doc "Mark error state."
  @spec set_error(t(), term()) :: t()
  def set_error(state, reason) do
    %{state |
      status: :error,
      last_error: reason,
      termination_reason: :error
    }
  end

  @doc "Increment iteration counter."
  @spec inc_iteration(t()) :: t()
  def inc_iteration(state) do
    %{state | iteration: state.iteration + 1}
  end
end
```

---

### 8. ReAct Strategy

The strategy implements a pure state machine. **No IO, only directives.**

```elixir
defmodule Jido.Examples.ReAct.Strategy do
  @moduledoc """
  ReAct (Reason-Act) execution strategy.

  Implements the ReAct loop:
  1. Receive user query → stream LLM
  2. LLM returns tool calls → execute Jido.Actions
  3. Tool results → stream LLM again
  4. Repeat until LLM provides final answer or max_iterations

  NO IO IN THIS MODULE - only pure state transformations and directive emission.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Examples.ReAct.{StrategyState, Signals}
  alias Jido.Examples.ReAct.Directive, as: ReactDirective
  alias Jido.Examples.ReAct.Action

  require Logger

  @impl true
  def init(agent, ctx) do
    max_iter = ctx[:strategy_opts][:max_iterations] || 10

    agent = StrategyState.update(agent, fn state ->
      %{state | max_iterations: max_iter}
    end)

    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    state = StrategyState.get(agent)

    # GUARD: Ignore events in terminal states
    if StrategyState.terminal?(state) do
      Logger.debug("ReAct: Ignoring instruction in terminal state #{state.status}")
      {agent, []}
    else
      handle_instruction(agent, state, instructions, ctx)
    end
  end

  defp handle_instruction(agent, state, [%{action: action, params: params} | _], ctx) do
    case action do
      Action.Start -> handle_start(agent, state, params, ctx)
      Action.LLMResult -> handle_llm_result(agent, state, params, ctx)
      Action.ToolResult -> handle_tool_result(agent, state, params, ctx)
      _ -> {agent, []}
    end
  end

  defp handle_instruction(agent, _state, _instructions, _ctx), do: {agent, []}

  # --- Start: User query received ---
  defp handle_start(agent, state, %{query: query}, _ctx) do
    state = StrategyState.start_conversation(state, query)
    call_id = StrategyState.next_call_id()
    state = %{state | current_llm_call_id: call_id}
    agent = StrategyState.put(agent, state)

    directive = ReactDirective.LLMStream.new!(%{
      id: call_id,
      model: "anthropic:claude-haiku-4.5",
      context: state.conversation,
      tools: state.tools
    })

    {agent, [directive]}
  end

  # --- LLM Result: Parse response and decide next step ---
  defp handle_llm_result(agent, state, %{call_id: call_id, result: result}, ctx) do
    if call_id != state.current_llm_call_id do
      Logger.warning("ReAct: Ignoring stale LLM result #{call_id}")
      {agent, []}
    else
      handle_llm_response(agent, state, result, ctx)
    end
  end

  defp handle_llm_response(agent, state, {:error, reason}, _ctx) do
    state = StrategyState.set_error(state, reason)
    agent = StrategyState.put(agent, state)

    error_signal = Signals.final_answer(%{
      answer: "Error: #{inspect(reason)}",
      iterations: state.iteration,
      termination_reason: :error
    })

    {agent, [Directive.emit(error_signal), Directive.stop(:normal)]}
  end

  defp handle_llm_response(agent, state, {:ok, result}, _ctx) do
    case result.type do
      :tool_calls ->
        handle_tool_calls(agent, state, result.tool_calls)

      :final_answer ->
        handle_final_answer(agent, state, result.text)
    end
  end

  defp handle_tool_calls(agent, state, tool_calls) do
    state = StrategyState.append_assistant_tool_calls(state, tool_calls)
    agent = StrategyState.put(agent, state)

    # Emit directive for each tool call
    directives = Enum.map(tool_calls, fn tc ->
      action_module = state.actions_by_name[tc.name]

      ReactDirective.ToolExec.new!(%{
        id: tc.id,
        tool_name: tc.name,
        action_module: action_module,
        arguments: tc.arguments
      })
    end)

    {agent, directives}
  end

  defp handle_final_answer(agent, state, answer) do
    state = StrategyState.complete_with_answer(state, answer)
    agent = StrategyState.put(agent, state)

    final_signal = Signals.final_answer(%{
      answer: answer,
      iterations: state.iteration,
      termination_reason: :final_answer
    })

    {agent, [Directive.emit(final_signal), Directive.stop(:normal)]}
  end

  # --- Tool Result: Record and continue ---
  defp handle_tool_result(agent, state, %{call_id: call_id, tool_name: name, result: result}, _ctx) do
    Logger.debug("ReAct: Tool #{name} completed")

    {state, all_complete} = StrategyState.record_tool_result(state, call_id, result)

    if all_complete do
      state = StrategyState.append_all_tool_results(state)
      state = StrategyState.inc_iteration(state)

      if state.iteration > state.max_iterations do
        state = StrategyState.complete_max_iterations(state)
        agent = StrategyState.put(agent, state)

        final_signal = Signals.final_answer(%{
          answer: state.final_answer,
          iterations: state.iteration,
          termination_reason: :max_iterations
        })

        {agent, [Directive.emit(final_signal), Directive.stop(:normal)]}
      else
        call_id = StrategyState.next_call_id()
        state = %{state | current_llm_call_id: call_id}
        agent = StrategyState.put(agent, state)

        directive = ReactDirective.LLMStream.new!(%{
          id: call_id,
          model: "anthropic:claude-haiku-4.5",
          context: state.conversation,
          tools: state.tools
        })

        {agent, [directive]}
      end
    else
      agent = StrategyState.put(agent, state)
      {agent, []}
    end
  end
end
```

---

### 9. Action Structs (Zoi)

```elixir
defmodule Jido.Examples.ReAct.Action do
  @moduledoc """
  Action structs for ReAct strategy.
  These are used as action types in cmd/2 calls.
  All use Zoi schemas for validation.
  """

  defmodule Start do
    @moduledoc "Start a new ReAct conversation."

    @schema Zoi.struct(
              __MODULE__,
              %{
                query: Zoi.string(description: "User query"),
                user_id: Zoi.string() |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  defmodule LLMResult do
    @moduledoc "LLM streaming response received."

    @schema Zoi.struct(
              __MODULE__,
              %{
                call_id: Zoi.string(description: "Correlation ID"),
                result: Zoi.any(description: "{:ok, result} | {:error, reason}")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  defmodule ToolResult do
    @moduledoc "Tool execution completed."

    @schema Zoi.struct(
              __MODULE__,
              %{
                call_id: Zoi.string(description: "Tool call ID"),
                tool_name: Zoi.string(description: "Tool name"),
                result: Zoi.any(description: "{:ok, result} | {:error, reason}")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end
end
```

---

### 10. ReAct Agent Module

```elixir
defmodule Jido.Examples.ReAct.Agent do
  @moduledoc """
  ReAct demo agent using Jido + ReqLLM streaming.

  Demonstrates:
  - Custom ReAct strategy with state machine
  - Streaming LLM integration via directives
  - Jido.Action-based tool execution
  - Signal-based completion notification
  """

  use Jido.Agent,
    name: "react_agent",
    description: "LLM ReAct demo agent using Jido + ReqLLM streaming",
    strategy: {Jido.Examples.ReAct.Strategy, max_iterations: 10},
    schema: Zoi.object(%{
      __strategy__: Zoi.map() |> Zoi.default(%{}),
      last_query: Zoi.string() |> Zoi.default(""),
      last_answer: Zoi.string() |> Zoi.default(""),
      completed: Zoi.boolean() |> Zoi.default(false)
    })

  alias Jido.Examples.ReAct.{Action, Tools}

  # Expose tools for the strategy
  def tools, do: Tools.all()
  def actions, do: Tools.actions()

  # --- Signal Handlers ---

  @impl true
  def handle_signal(agent, %Jido.Signal{type: "react.user_query", data: %{query: query} = data}) do
    agent = %{agent | state: Map.put(agent.state, :last_query, query)}
    cmd(agent, {Action.Start, data})
  end

  def handle_signal(agent, %Jido.Signal{type: "react.llm_result", data: data}) do
    cmd(agent, {Action.LLMResult, data})
  end

  def handle_signal(agent, %Jido.Signal{type: "react.tool_result", data: data}) do
    cmd(agent, {Action.ToolResult, data})
  end

  def handle_signal(agent, signal), do: super(agent, signal)

  # --- Sync __strategy__ to top-level state ---

  @impl true
  def on_after_cmd(agent, _action, directives) do
    strategy = agent.state[:__strategy__] || %{}

    agent = case strategy do
      %{final_answer: answer, status: :completed} when is_binary(answer) ->
        state = agent.state
          |> Map.put(:last_answer, answer)
          |> Map.put(:completed, true)
        %{agent | state: state}

      %{status: :error, last_error: error} ->
        state = agent.state
          |> Map.put(:last_answer, "Error: #{inspect(error)}")
          |> Map.put(:completed, true)
        %{agent | state: state}

      _ ->
        agent
    end

    {:ok, agent, directives}
  end
end
```

---

### 11. Signals Module

```elixir
defmodule Jido.Examples.ReAct.Signals do
  @moduledoc """
  Signal constructors for ReAct feedback loop.
  Single source of truth for signal shapes.
  """

  alias Jido.Signal

  @doc "Create user query signal."
  @spec user_query(String.t(), keyword()) :: Signal.t()
  def user_query(query, opts \\ []) do
    Signal.new!(
      "react.user_query",
      %{query: query, user_id: opts[:user_id]},
      Keyword.merge([source: "/user"], opts)
    )
  end

  @doc "Create LLM result signal."
  @spec llm_result(map()) :: Signal.t()
  def llm_result(%{call_id: call_id, result: result}) do
    Signal.new!(
      "react.llm_result",
      %{call_id: call_id, result: result},
      source: "/llm"
    )
  end

  @doc "Create tool result signal."
  @spec tool_result(map()) :: Signal.t()
  def tool_result(%{call_id: call_id, tool_name: tool_name, result: result}) do
    Signal.new!(
      "react.tool_result",
      %{call_id: call_id, tool_name: tool_name, result: result},
      source: "/tool/#{tool_name}"
    )
  end

  @doc "Create final answer signal."
  @spec final_answer(map()) :: Signal.t()
  def final_answer(%{answer: answer} = data) do
    Signal.new!(
      "react.final_answer",
      %{
        answer: answer,
        iterations: data[:iterations] || 0,
        termination_reason: data[:termination_reason] || :final_answer
      },
      source: "/agent"
    )
  end
end
```

---

## Example Usage

### Runner Script (`examples/react_agent.exs`)

```elixir
# examples/react_agent.exs
#
# Run with: mix run examples/react_agent.exs
#
# Requires ANTHROPIC_API_KEY in .env file

# Load environment
_ = Dotenvy.source(".env")

# Ensure apps started
Application.ensure_all_started(:jido)

alias Jido.Examples.ReAct.{Agent, Signals}

IO.puts("=== Jido ReAct Agent Demo (Streaming) ===\n")

# Start ReAct agent server
{:ok, pid} = Jido.AgentServer.start(
  agent: Agent,
  id: "react-demo-1"
)

IO.puts("Agent started: #{inspect(pid)}")

# Build query
query = """
What is (3 + 5) * 7?
Also, what's the weather in San Francisco?
"""

IO.puts("\nQuery: #{query}")
IO.puts("\nProcessing (streaming)...\n")

# Send query signal
signal = Signals.user_query(query, source: "/cli")
{:ok, _agent} = Jido.AgentServer.call(pid, signal)

# Poll for completion
defmodule Poller do
  def wait_for_completion(pid, attempts \\ 60, interval \\ 500)

  def wait_for_completion(_pid, 0, _interval) do
    {:error, :timeout}
  end

  def wait_for_completion(pid, attempts, interval) do
    {:ok, state} = Jido.AgentServer.state(pid)

    if state.agent.state[:completed] do
      {:ok, state.agent}
    else
      Process.sleep(interval)
      wait_for_completion(pid, attempts - 1, interval)
    end
  end
end

case Poller.wait_for_completion(pid) do
  {:ok, agent} ->
    IO.puts("=== Result ===")
    IO.puts("Status: completed")
    IO.puts("Iterations: #{agent.state.__strategy__[:iteration]}")
    IO.puts("Termination: #{agent.state.__strategy__[:termination_reason]}")
    IO.puts("\nAnswer:")
    IO.puts(agent.state.last_answer)

  {:error, :timeout} ->
    IO.puts("Timeout waiting for completion")
    {:ok, state} = Jido.AgentServer.state(pid)
    IO.puts("Current status: #{state.agent.state.__strategy__[:status]}")
end
```

---

## Implementation Checklist

### Phase 1: Infrastructure
- [ ] Create `types.ex` with shared Zoi types
- [ ] Create `llm_client.ex` with behaviour + ReqLLM (streaming) + Mock implementations
- [ ] Add config for `:react_llm_client`
- [ ] Create `directives.ex` with `LLMStream` and `ToolExec` structs (Zoi)
- [ ] Create `directive_exec.ex` with streaming implementations

### Phase 2: Tools (Jido.Action)
- [ ] Create `actions/calculator.ex` using `use Jido.Action` with Zoi schema
- [ ] Create `actions/weather.ex` using `use Jido.Action` with Zoi schema
- [ ] Create `tools.ex` registry that converts Actions to ReqLLM tools

### Phase 3: Strategy
- [ ] Create `strategy_state.ex` using `Jido.Agent.Strategy.State` + Zoi schema
- [ ] Create `actions.ex` with `Start`, `LLMResult`, `ToolResult` structs (Zoi)
- [ ] Create `strategy.ex` with state machine and terminal state guards

### Phase 4: Agent & Signals
- [ ] Create `signals.ex` with all signal constructors
- [ ] Create `agent.ex` with strategy config and `on_after_cmd/3` sync

### Phase 5: Integration
- [ ] Create `examples/react_agent.exs` runner script
- [ ] Create test helpers (`eventually/1`, mock helpers)
- [ ] Write integration tests with mock client
- [ ] Test with real Claude Haiku API (optional, requires key)

### Phase 6: Polish
- [ ] Add debug logging throughout
- [ ] Add telemetry events for observability
- [ ] Document all modules
- [ ] Run `mix quality` and fix any issues

---

## Dependencies

Add to `projects/jido/mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps
    {:req_llm, "~> 1.0"},
    {:abacus, "~> 2.1"},  # Safe math evaluation
    {:dotenvy, "~> 0.8"}, # .env file loading (dev/test only)
    {:jason, "~> 1.4"}    # JSON encoding for tool results
  ]
end
```

---

## Key Changes from V2

1. **Streaming**: Uses `ReqLLM.stream_text/3` → `StreamResponse` instead of `generate_text/3`
2. **Zoi Schemas**: All structs use `Zoi.struct()` pattern for type safety
3. **Jido.Action Tools**: Tools are defined as `Jido.Action` modules with proper schemas
4. **Single-pass Stream Consumption**: Stream chunks collected once, extracting both text and tool_calls
5. **Action Execution via Jido.Exec**: Tools run through `Jido.Exec.run/3` for full lifecycle

---

## Future Enhancements

When moving to `jido_ai`:

- [ ] Real-time streaming display (emit tokens as signals)
- [ ] Budget-aware control (tokens, time, cost)
- [ ] Multi-model orchestration
- [ ] Nested agent hierarchies
- [ ] Tick-driven strategy variant
- [ ] ReAct transcript logging (thought/action/observation)
- [ ] Configurable retry policies for transient errors
