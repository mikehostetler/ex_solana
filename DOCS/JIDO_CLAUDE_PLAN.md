# Jido Claude Integration Plan

## Overview

Integrate the Claude Agent SDK into the Jido Agent framework using a two-agent pattern:
- **Orchestrator Agent** - Business logic, manages multiple concurrent Claude sessions
- **ClaudeSessionAgent** - Owns a single Claude session lifecycle, emits signals per turn

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Orchestrator Agent (any Jido Agent)                                    │
│                                                                         │
│  State:                                                                 │
│    sessions: %{                                                         │
│      "task-123" => %{status: :running, child_pid: #PID<...>},          │
│      "task-456" => %{status: :success, result: "..."},                 │
│      "task-789" => %{status: :running, child_pid: #PID<...>}           │
│    }                                                                    │
│                                                                         │
│  cmd(agent, {SpawnClaudeSession, %{session_id: "task-123", ...}})      │
│    → {agent, [%SpawnAgent{agent: ClaudeSessionAgent, tag: "task-123"}]}│
│                                                                         │
│  Receives signals from children (correlated by session_id):             │
│    • "claude.session.started"   → updates sessions["task-123"]          │
│    • "claude.turn.tool_use"     → logs/observes progress                │
│    • "claude.session.success"   → stores result, removes from active    │
│    • "claude.session.error"     → handles failure, retry logic          │
│    • "jido.agent.child.exit"    → cleanup on unexpected exit            │
│                                                                         │
│  Can spawn multiple concurrent sessions with unique tags/session_ids    │
└─────────────────────────────────────────────────────────────────────────┘
          │                    │                    │
          │ %SpawnAgent{}      │ %SpawnAgent{}      │ %SpawnAgent{}
          ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ ClaudeSession    │  │ ClaudeSession    │  │ ClaudeSession    │
│ tag: "task-123"  │  │ tag: "task-456"  │  │ tag: "task-789"  │
│                  │  │                  │  │                  │
│ session_id ──────┼──┼──────────────────┼──┼─► correlation    │
│ status: :running │  │ status: :success │  │ status: :running │
│ turns: 3         │  │ turns: 12        │  │ turns: 1         │
│ prompt: "..."    │  │ result: "..."    │  │ prompt: "..."    │
└──────────────────┘  └──────────────────┘  └──────────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
    StreamRunner         StreamRunner         StreamRunner
    (internal Task)      (completed)          (internal Task)
```

## Key Concepts

### Long-Running Sessions

Claude sessions can run for extended periods (5-30+ minutes for complex tasks). The architecture handles this via:

1. **No blocking calls** - SDK runs in separate Task, parent never blocks
2. **Activity-based timeouts** - Track `last_activity`, not session start time
3. **Heartbeat signals** - Each turn updates `last_activity` timestamp
4. **Generous defaults** - 10-minute activity timeout (not session timeout)
5. **Configurable per-session** - Override timeout via session metadata

```elixir
# Long-running session with extended timeout
cmd(agent, {SpawnSession, %{
  session_id: "deep-analysis",
  prompt: "Perform comprehensive codebase review...",
  max_turns: 100,
  meta: %{timeout_ms: 1_800_000}  # 30-minute activity timeout
}})
```

### Session Identification & Correlation

Every Claude session has a unique `session_id` that:
- Is passed to `SpawnClaudeSession` action (or auto-generated)
- Becomes the `tag` for the `%SpawnAgent{}` directive
- Is included in every signal emitted by the child
- Allows parent to correlate signals to specific sessions

```elixir
# Spawning with explicit session_id
cmd(agent, {SpawnClaudeSession, %{
  session_id: "analyze-pr-#{pr_number}",
  prompt: "Review this PR..."
}})

# Auto-generated session_id
cmd(agent, {SpawnClaudeSession, %{prompt: "..."}})
# → generates session_id like "claude-a1b2c3d4"
```

### Parent State: Session Registry

The orchestrator maintains a `sessions` map tracking all child sessions:

```elixir
%{
  sessions: %{
    "task-123" => %{
      status: :running,
      child_pid: #PID<0.234.0>,
      started_at: ~U[2024-01-15 10:30:00Z],
      prompt: "Analyze the codebase...",
      turns: 5,
      last_activity: ~U[2024-01-15 10:31:23Z]
    },
    "task-456" => %{
      status: :success,
      result: "The analysis shows...",
      cost_usd: 0.0234,
      completed_at: ~U[2024-01-15 10:29:00Z]
    }
  }
}
```

### Lifecycle Events

| Event | Parent Receives | Parent Action |
|-------|-----------------|---------------|
| Session spawned | `jido.agent.child.started` | Register in sessions map |
| Session init | `claude.session.started` | Update with session_id, model |
| Each turn | `claude.turn.*` | Update turns count, last_activity |
| Success | `claude.session.success` | Store result, mark complete |
| Failure | `claude.session.error` | Handle error, maybe retry |
| Child exit | `jido.agent.child.exit` | Cleanup, detect crashes |

## Module Structure

```
lib/jido_claude/
├── claude_session_agent.ex      # The session agent module
├── actions/
│   ├── start_session.ex         # Initialize and spawn stream runner
│   ├── handle_message.ex        # Process each SDK message
│   └── cancel_session.ex        # Cancel running session
├── parent/
│   ├── spawn_session.ex         # Action for parent to spawn child session
│   ├── handle_session_event.ex  # Action to process child signals
│   ├── cancel_session.ex        # Action to cancel a child session
│   └── session_registry.ex      # State helpers for sessions map
├── stream_runner.ex             # Task that runs SDK stream
├── signals.ex                   # Signal type constants and builders
└── options.ex                   # Wrapper for ClaudeAgentSDK.Options
```

## Implementation Phases

### Phase 1: Core Session Agent

**Goal:** ClaudeSessionAgent that runs a single prompt and emits signals.

#### 1.1 ClaudeSessionAgent Module

```elixir
defmodule JidoClaude.ClaudeSessionAgent do
  use Jido.Agent,
    name: "claude_session",
    description: "Manages a single Claude Code session",
    schema: [
      status: [type: :atom, default: :idle],
      prompt: [type: :string, default: nil],
      options: [type: :any, default: nil],
      session_id: [type: :string, default: nil],
      model: [type: :string, default: nil],
      turns: [type: :integer, default: 0],
      transcript: [type: {:list, :any}, default: []],
      result: [type: :string, default: nil],
      cost_usd: [type: :float, default: nil],
      error: [type: :any, default: nil]
    ]

  def signal_routes do
    [
      {"claude.internal.message", {JidoClaude.Actions.HandleMessage, %{}}}
    ]
  end
end
```

#### 1.2 StartSession Action

```elixir
defmodule JidoClaude.Actions.StartSession do
  use Jido.Action,
    name: "claude.start_session",
    description: "Start a Claude Code session",
    schema: [
      prompt: [type: :string, required: true],
      model: [type: :string, default: "sonnet"],
      max_turns: [type: :integer, default: 25],
      allowed_tools: [type: {:list, :string}, default: ["Read", "Glob", "Grep", "Bash"]],
      cwd: [type: :string, default: nil],
      system_prompt: [type: :string, default: nil]
    ]

  alias JidoClaude.StreamRunner
  alias Jido.Agent.Directive

  @impl true
  def run(params, context) do
    options = build_options(params)
    
    # State update
    result = %{
      status: :running,
      prompt: params.prompt,
      options: options,
      turns: 0,
      transcript: []
    }

    # Spawn the stream runner (fire-and-forget Task)
    runner_spec = {Task, fn -> 
      StreamRunner.run(%{
        agent_pid: self(),  # ClaudeSessionAgent's PID
        prompt: params.prompt,
        options: options
      })
    end}

    directives = [
      Directive.spawn(runner_spec, :stream_runner)
    ]

    {:ok, result, directives}
  end

  defp build_options(params) do
    %ClaudeAgentSDK.Options{
      model: params.model,
      max_turns: params.max_turns,
      allowed_tools: params.allowed_tools,
      cwd: params[:cwd] || File.cwd!(),
      system_prompt: params[:system_prompt],
      timeout_ms: params[:sdk_timeout_ms] || 600_000  # 10 min SDK timeout
    }
  end
end
```

**Timeout Configuration:**

| Timeout | Default | Purpose |
|---------|---------|---------|
| `sdk_timeout_ms` | 10 min | SDK-level timeout for entire query |
| `meta.timeout_ms` | 10 min | Activity timeout (no turns received) |
| `max_turns` | 25 | Maximum agentic loop iterations |

For long-running sessions, increase all three:

```elixir
{StartSession, %{
  prompt: "Deep codebase analysis...",
  max_turns: 100,
  sdk_timeout_ms: 1_800_000,     # 30 min SDK timeout
  meta: %{timeout_ms: 900_000}   # 15 min activity timeout
}}
```

#### 1.3 StreamRunner Task

```elixir
defmodule JidoClaude.StreamRunner do
  @moduledoc """
  Task that runs ClaudeAgentSDK.query/3 and dispatches each message
  as a signal to the owning ClaudeSessionAgent.
  """

  alias ClaudeAgentSDK.{Options, Message}
  alias Jido.Signal

  def run(%{agent_pid: agent_pid, prompt: prompt, options: options}) do
    Application.ensure_all_started(:claude_agent_sdk)

    prompt
    |> ClaudeAgentSDK.query(options)
    |> Stream.each(fn message ->
      dispatch_message(agent_pid, message)
    end)
    |> Stream.run()
  rescue
    e ->
      error_signal = build_error_signal(e)
      Jido.Signal.Dispatch.dispatch(error_signal, {:pid, target: agent_pid})
  end

  defp dispatch_message(agent_pid, %Message{} = msg) do
    signal = Signal.new!(
      "claude.internal.message",
      %{
        type: msg.type,
        subtype: msg.subtype,
        data: msg.data,
        raw: msg.raw
      },
      source: "/claude/stream_runner"
    )

    Jido.Signal.Dispatch.dispatch(signal, {:pid, target: agent_pid})
  end

  defp build_error_signal(exception) do
    Signal.new!(
      "claude.internal.message",
      %{
        type: :result,
        subtype: :error_exception,
        data: %{
          error: Exception.message(exception),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        },
        raw: nil
      },
      source: "/claude/stream_runner"
    )
  end
end
```

#### 1.4 HandleMessage Action

```elixir
defmodule JidoClaude.Actions.HandleMessage do
  use Jido.Action,
    name: "claude.handle_message",
    description: "Process a message from Claude SDK stream",
    schema: [
      type: [type: :atom, required: true],
      subtype: [type: :atom, default: nil],
      data: [type: :map, default: %{}],
      raw: [type: :any, default: nil]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Signals

  @impl true
  def run(params, context) do
    agent = context.agent
    
    {state_update, parent_signal, terminal?} = 
      process_message(params, agent)

    directives = build_directives(agent, parent_signal, terminal?)

    {:ok, state_update, directives}
  end

  defp process_message(%{type: :system, subtype: :init, data: data}, _agent) do
    state = %{
      session_id: data[:session_id],
      model: data[:model]
    }
    signal = Signals.session_started(data)
    {state, signal, false}
  end

  defp process_message(%{type: :assistant, data: data, raw: raw}, agent) do
    content_blocks = extract_content_blocks(raw)
    
    state = %{
      turns: agent.state.turns + 1,
      transcript: agent.state.transcript ++ [{:assistant, content_blocks}]
    }

    # Emit different signals for text vs tool_use
    signals = Enum.map(content_blocks, fn
      %{type: :text} = block -> Signals.assistant_text(block)
      %{type: :tool_use} = block -> Signals.tool_use(block)
      _ -> nil
    end) |> Enum.reject(&is_nil/1)

    {state, signals, false}
  end

  defp process_message(%{type: :user, data: data}, agent) do
    state = %{
      transcript: agent.state.transcript ++ [{:user, data}]
    }
    signal = Signals.tool_result(data)
    {state, signal, false}
  end

  defp process_message(%{type: :result, subtype: :success, data: data}, _agent) do
    state = %{
      status: :success,
      result: data[:result],
      cost_usd: data[:total_cost_usd]
    }
    signal = Signals.session_success(data)
    {state, signal, true}
  end

  defp process_message(%{type: :result, subtype: subtype, data: data}, _agent) 
       when subtype in [:error_max_turns, :error_exception, :error_timeout] do
    state = %{
      status: :failure,
      error: %{type: subtype, details: data}
    }
    signal = Signals.session_error(subtype, data)
    {state, signal, true}
  end

  defp process_message(_msg, _agent) do
    {%{}, nil, false}
  end

  defp build_directives(agent, signals, terminal?) do
    # Emit signals to parent
    signal_directives = 
      signals
      |> List.wrap()
      |> Enum.map(fn signal ->
        Directive.emit_to_parent(agent, signal)
      end)
      |> Enum.reject(&is_nil/1)

    # Add Stop directive if terminal
    if terminal? do
      signal_directives ++ [Directive.stop(:normal)]
    else
      signal_directives
    end
  end

  defp extract_content_blocks(%{"message" => %{"content" => content}}) do
    Enum.map(content, fn
      %{"type" => "text", "text" => text} -> 
        %{type: :text, text: text}
      %{"type" => "tool_use", "name" => name, "input" => input} ->
        %{type: :tool_use, name: name, input: input}
      other ->
        %{type: :unknown, raw: other}
    end)
  end

  defp extract_content_blocks(_), do: []
end
```

#### 1.5 Signals Module

```elixir
defmodule JidoClaude.Signals do
  @moduledoc """
  Signal builders for Claude session events.
  """

  alias Jido.Signal

  def session_started(data) do
    Signal.new!(
      "claude.session.started",
      %{session_id: data[:session_id], model: data[:model]},
      source: "/claude"
    )
  end

  def assistant_text(%{text: text}) do
    Signal.new!(
      "claude.turn.text",
      %{text: text},
      source: "/claude"
    )
  end

  def tool_use(%{name: name, input: input}) do
    Signal.new!(
      "claude.turn.tool_use",
      %{tool: name, input: input},
      source: "/claude"
    )
  end

  def tool_result(data) do
    Signal.new!(
      "claude.turn.tool_result",
      data,
      source: "/claude"
    )
  end

  def session_success(data) do
    Signal.new!(
      "claude.session.success",
      %{
        result: data[:result],
        turns: data[:num_turns],
        cost_usd: data[:total_cost_usd],
        duration_ms: data[:duration_ms]
      },
      source: "/claude"
    )
  end

  def session_error(subtype, data) do
    Signal.new!(
      "claude.session.error",
      %{error_type: subtype, details: data},
      source: "/claude"
    )
  end
end
```

### Phase 2: Parent Integration (Multi-Session)

**Goal:** Parent agent can spawn and manage multiple concurrent Claude sessions.

#### 2.1 Session Registry Helpers

```elixir
defmodule JidoClaude.Parent.SessionRegistry do
  @moduledoc """
  State helpers for managing multiple Claude sessions in parent agent.
  """

  def init_sessions(state) do
    Map.put_new(state, :sessions, %{})
  end

  def register_session(state, session_id, attrs) do
    session = Map.merge(%{
      status: :starting,
      started_at: DateTime.utc_now(),
      turns: 0,
      last_activity: DateTime.utc_now()
    }, attrs)
    
    put_in(state, [:sessions, session_id], session)
  end

  def update_session(state, session_id, updates) do
    update_in(state, [:sessions, session_id], fn session ->
      session
      |> Map.merge(updates)
      |> Map.put(:last_activity, DateTime.utc_now())
    end)
  end

  def get_session(state, session_id) do
    get_in(state, [:sessions, session_id])
  end

  def remove_session(state, session_id) do
    update_in(state, [:sessions], &Map.delete(&1, session_id))
  end

  def active_sessions(state) do
    state.sessions
    |> Enum.filter(fn {_id, s} -> s.status in [:starting, :running] end)
    |> Map.new()
  end

  def completed_sessions(state) do
    state.sessions
    |> Enum.filter(fn {_id, s} -> s.status in [:success, :failure, :cancelled] end)
    |> Map.new()
  end
end
```

#### 2.2 SpawnSession Action (for parent agents)

```elixir
defmodule JidoClaude.Parent.SpawnSession do
  use Jido.Action,
    name: "claude.spawn_session",
    description: "Spawn a ClaudeSessionAgent as a child",
    schema: [
      prompt: [type: :string, required: true],
      session_id: [type: :string, default: nil],  # auto-generated if nil
      model: [type: :string, default: "sonnet"],
      max_turns: [type: :integer, default: 25],
      allowed_tools: [type: {:list, :string}, default: ["Read", "Glob", "Grep", "Bash"]],
      cwd: [type: :string, default: nil],
      system_prompt: [type: :string, default: nil],
      meta: [type: :map, default: %{}]  # custom metadata to track
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.ClaudeSessionAgent
  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    session_id = params[:session_id] || generate_session_id()
    
    initial_state = %{
      session_id: session_id,
      prompt: params.prompt,
      options: %{
        model: params.model,
        max_turns: params.max_turns,
        allowed_tools: params.allowed_tools,
        cwd: params[:cwd],
        system_prompt: params[:system_prompt]
      }
    }

    # Register session in parent state
    state_update = 
      context.agent.state
      |> SessionRegistry.init_sessions()
      |> SessionRegistry.register_session(session_id, %{
        prompt: params.prompt,
        model: params.model,
        meta: params[:meta] || %{}
      })
      |> Map.take([:sessions])

    # Spawn child agent with session_id as tag
    directive = Directive.spawn_agent(
      ClaudeSessionAgent,
      session_id,  # tag = session_id for correlation
      opts: %{initial_state: initial_state},
      meta: %{session_id: session_id}
    )

    {:ok, state_update, [directive]}
  end

  defp generate_session_id do
    "claude-" <> (Base.encode16(:crypto.strong_rand_bytes(4), case: :lower))
  end
end
```

#### 2.3 HandleSessionEvent Action

```elixir
defmodule JidoClaude.Parent.HandleSessionEvent do
  use Jido.Action,
    name: "claude.handle_session_event",
    description: "Process signals from child Claude sessions",
    schema: [
      session_id: [type: :string, required: true],
      event_type: [type: :string, required: true],
      data: [type: :map, default: %{}]
    ]

  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    session_id = params.session_id
    event_type = params.event_type
    data = params.data
    
    state = context.agent.state

    # Skip if session not found (already cleaned up)
    unless SessionRegistry.get_session(state, session_id) do
      {:ok, %{}, []}
    else
      handle_event(event_type, session_id, data, state)
    end
  end

  defp handle_event("claude.session.started", session_id, data, state) do
    update = SessionRegistry.update_session(state, session_id, %{
      status: :running,
      sdk_session_id: data[:session_id],
      model: data[:model]
    })
    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("claude.turn." <> _turn_type, session_id, _data, state) do
    session = SessionRegistry.get_session(state, session_id)
    update = SessionRegistry.update_session(state, session_id, %{
      turns: (session[:turns] || 0) + 1
    })
    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("claude.session.success", session_id, data, state) do
    update = SessionRegistry.update_session(state, session_id, %{
      status: :success,
      result: data[:result],
      cost_usd: data[:cost_usd],
      completed_at: DateTime.utc_now()
    })
    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("claude.session.error", session_id, data, state) do
    update = SessionRegistry.update_session(state, session_id, %{
      status: :failure,
      error: data,
      completed_at: DateTime.utc_now()
    })
    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event(_unknown, _session_id, _data, _state) do
    {:ok, %{}, []}
  end
end
```

#### 2.4 CancelSession Action (from parent)

```elixir
defmodule JidoClaude.Parent.CancelSession do
  use Jido.Action,
    name: "claude.cancel_session",
    description: "Cancel a running Claude session",
    schema: [
      session_id: [type: :string, required: true],
      reason: [type: :atom, default: :cancelled]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    session_id = params.session_id
    state = context.agent.state
    
    session = SessionRegistry.get_session(state, session_id)
    
    cond do
      is_nil(session) ->
        {:error, :session_not_found}
      
      session.status not in [:starting, :running] ->
        {:error, :session_not_active}
      
      true ->
        update = SessionRegistry.update_session(state, session_id, %{
          status: :cancelled,
          completed_at: DateTime.utc_now()
        })
        
        directive = Directive.stop_child(session_id, params.reason)
        
        {:ok, Map.take(update, [:sessions]), [directive]}
    end
  end
end
```

#### 2.5 Parent Agent Example

```elixir
defmodule MyOrchestratorAgent do
  use Jido.Agent,
    name: "orchestrator",
    description: "Manages multiple Claude sessions",
    schema: [
      sessions: [type: :map, default: %{}],
      pending_tasks: [type: {:list, :any}, default: []]
    ]

  alias JidoClaude.Parent.{SpawnSession, HandleSessionEvent, CancelSession}

  # Route all Claude signals to the handler
  def signal_routes do
    [
      # Child lifecycle
      {"jido.agent.child.started", &handle_child_started/1},
      {"jido.agent.child.exit", &handle_child_exit/1},
      
      # Claude session events (route to HandleSessionEvent action)
      {"claude.session.started", {HandleSessionEvent, &extract_session_params/1}},
      {"claude.turn.text", {HandleSessionEvent, &extract_session_params/1}},
      {"claude.turn.tool_use", {HandleSessionEvent, &extract_session_params/1}},
      {"claude.session.success", {HandleSessionEvent, &extract_session_params/1}},
      {"claude.session.error", {HandleSessionEvent, &extract_session_params/1}}
    ]
  end

  defp extract_session_params(signal) do
    %{
      session_id: signal.data.session_id,
      event_type: signal.type,
      data: signal.data
    }
  end

  defp handle_child_started(signal) do
    # Child agent started - could log or update state
    {HandleSessionEvent, %{
      session_id: signal.data.tag,
      event_type: "child.started",
      data: %{pid: signal.data.pid}
    }}
  end

  defp handle_child_exit(signal) do
    # Child agent exited - cleanup
    {HandleSessionEvent, %{
      session_id: signal.data.tag,
      event_type: "child.exit",
      data: %{reason: signal.data.reason}
    }}
  end

  # Available actions
  def actions do
    [SpawnSession, CancelSession]
  end
end
```

#### 2.6 Usage Examples

```elixir
# Spawn multiple concurrent sessions
{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  session_id: "review-pr-123",
  prompt: "Review PR #123 for security issues"
}})

{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  session_id: "analyze-deps",
  prompt: "Analyze dependencies for vulnerabilities"
}})

{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  prompt: "Refactor the auth module"  # auto-generates session_id
}})

# Check status
agent.state.sessions
# => %{
#   "review-pr-123" => %{status: :running, turns: 3, ...},
#   "analyze-deps" => %{status: :success, result: "...", ...},
#   "claude-a1b2c3d4" => %{status: :running, turns: 1, ...}
# }

# Cancel a session
{agent, _} = MyOrchestrator.cmd(agent, {CancelSession, %{
  session_id: "review-pr-123"
}})
```

### Phase 3: Advanced Session Management

**Goal:** Robust handling of concurrent sessions with timeouts, retries, and batch operations.

#### 3.1 Session Timeout Watchdog

The watchdog uses **activity-based timeouts**, not session duration. A session running for 30 minutes is fine as long as it's making progress (emitting turn signals).

```elixir
defmodule JidoClaude.Parent.SessionWatchdog do
  @moduledoc """
  Periodic check for stale sessions that haven't received activity.
  
  Uses activity-based timeout (time since last turn), not total session duration.
  This allows long-running Claude sessions while catching truly stuck ones.
  
  Default: 10 minutes without activity = stale
  Per-session override: session.meta.timeout_ms
  """

  use Jido.Action,
    name: "claude.session_watchdog",
    description: "Check for timed-out sessions",
    schema: [
      default_timeout_ms: [type: :integer, default: 600_000]  # 10 minutes
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    default_timeout = params.default_timeout_ms
    now = DateTime.utc_now()
    state = context.agent.state

    # Find stale sessions (no activity within timeout window)
    stale_sessions = 
      SessionRegistry.active_sessions(state)
      |> Enum.filter(fn {_id, session} ->
        timeout_ms = get_in(session, [:meta, :timeout_ms]) || default_timeout
        age_ms = DateTime.diff(now, session.last_activity, :millisecond)
        age_ms > timeout_ms
      end)

    # Mark as timed out and stop children
    {updated_state, directives} = 
      Enum.reduce(stale_sessions, {state, []}, fn {session_id, session}, {st, dirs} ->
        timeout_ms = get_in(session, [:meta, :timeout_ms]) || default_timeout
        updated = SessionRegistry.update_session(st, session_id, %{
          status: :failure,
          error: %{type: :activity_timeout, timeout_ms: timeout_ms},
          completed_at: now
        })
        {updated, dirs ++ [Directive.stop_child(session_id, :timeout)]}
      end)

    {:ok, Map.take(updated_state, [:sessions]), directives}
  end
end
```

#### 3.1.1 Scheduling the Watchdog

Use a Cron directive to run the watchdog periodically:

```elixir
# In parent agent's init or on_after_cmd hook:
def schedule_watchdog do
  # Run every 60 seconds
  Directive.cron("* * * * *", 
    Signal.new!("claude.watchdog.tick", %{}, source: "/internal"),
    job_id: :session_watchdog
  )
end

# Route the tick to the watchdog action
def signal_routes do
  [
    {"claude.watchdog.tick", {SessionWatchdog, %{default_timeout_ms: 600_000}}},
    # ... other routes
  ]
end
```

#### 3.2 Batch Session Operations

```elixir
defmodule JidoClaude.Parent.CancelAllSessions do
  use Jido.Action,
    name: "claude.cancel_all_sessions",
    description: "Cancel all active Claude sessions",
    schema: [
      reason: [type: :atom, default: :cancelled]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    state = context.agent.state
    active = SessionRegistry.active_sessions(state)
    now = DateTime.utc_now()

    {updated_state, directives} = 
      Enum.reduce(active, {state, []}, fn {session_id, _}, {st, dirs} ->
        updated = SessionRegistry.update_session(st, session_id, %{
          status: :cancelled,
          completed_at: now
        })
        {updated, dirs ++ [Directive.stop_child(session_id, params.reason)]}
      end)

    {:ok, Map.take(updated_state, [:sessions]), directives}
  end
end

defmodule JidoClaude.Parent.CleanupCompletedSessions do
  use Jido.Action,
    name: "claude.cleanup_completed",
    description: "Remove completed sessions older than threshold",
    schema: [
      max_age_ms: [type: :integer, default: 3_600_000]  # 1 hour
    ]

  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    max_age_ms = params.max_age_ms
    now = DateTime.utc_now()
    state = context.agent.state

    old_sessions = 
      SessionRegistry.completed_sessions(state)
      |> Enum.filter(fn {_id, session} ->
        completed_at = session[:completed_at] || session.started_at
        age_ms = DateTime.diff(now, completed_at, :millisecond)
        age_ms > max_age_ms
      end)
      |> Enum.map(fn {id, _} -> id end)

    updated_state = 
      Enum.reduce(old_sessions, state, fn id, st ->
        SessionRegistry.remove_session(st, id)
      end)

    {:ok, Map.take(updated_state, [:sessions]), []}
  end
end
```

#### 3.3 Session Queries

```elixir
defmodule JidoClaude.Parent.SessionQueries do
  @moduledoc """
  Query helpers for session state (pure functions, not actions).
  """

  alias JidoClaude.Parent.SessionRegistry

  def count_active(state) do
    SessionRegistry.active_sessions(state) |> map_size()
  end

  def count_by_status(state) do
    state.sessions
    |> Enum.group_by(fn {_id, s} -> s.status end)
    |> Enum.map(fn {status, list} -> {status, length(list)} end)
    |> Map.new()
  end

  def total_cost(state) do
    state.sessions
    |> Enum.map(fn {_id, s} -> s[:cost_usd] || 0.0 end)
    |> Enum.sum()
  end

  def find_by_meta(state, key, value) do
    state.sessions
    |> Enum.filter(fn {_id, s} -> get_in(s, [:meta, key]) == value end)
    |> Map.new()
  end
end
```

### Phase 4: Multi-Turn Sessions (Future)

For follow-up prompts within same session:

```elixir
defmodule JidoClaude.Actions.ContinueSession do
  use Jido.Action,
    name: "claude.continue_session",
    description: "Send follow-up prompt to existing session",
    schema: [
      prompt: [type: :string, required: true]
    ]

  # Implementation would:
  # 1. Check status == :success (previous turn completed)
  # 2. Update state with new prompt
  # 3. Spawn new StreamRunner with conversation context
  # 4. Reset to :running status
end
```

## Signal Types Summary

| Signal Type | Emitted When | Data |
|-------------|--------------|------|
| `claude.session.started` | SDK :system/:init received | `session_id`, `model` |
| `claude.turn.text` | Assistant text response | `session_id`, `text` |
| `claude.turn.tool_use` | Assistant calls a tool | `session_id`, `tool`, `input` |
| `claude.turn.tool_result` | Tool execution result | `session_id`, tool-specific |
| `claude.session.success` | Session completed | `session_id`, `result`, `turns`, `cost_usd` |
| `claude.session.error` | Session failed | `session_id`, `error_type`, `details` |

**Note:** All signals include `session_id` for parent correlation across multiple concurrent sessions.

## Testing Strategy

### Unit Tests
- `ClaudeSessionAgent` state transitions
- `HandleMessage` action for each message type
- Signal building
- `SessionRegistry` state helpers
- `SessionQueries` pure functions

### Integration Tests (with mocked SDK)
- Full session lifecycle
- Parent-child signal flow
- Cancellation
- **Multi-session concurrent execution**
- Session timeout watchdog
- Batch operations (cancel all, cleanup)

### E2E Tests (requires Claude CLI auth)
- Real Claude session
- Tool usage
- Multi-turn conversations
- **Multiple concurrent sessions from single parent**

## Dependencies

```elixir
# mix.exs
{:claude_agent_sdk, "~> 0.7"},
{:jido, path: "projects/jido"}  # or from hex
```

## Open Questions

1. **Session persistence**: Should transcript be stored externally for long sessions?
2. **Rate limiting**: Should ClaudeSessionAgent enforce rate limits?
3. **Retry policy**: Auto-retry on transient errors?
4. **Streaming text**: Emit partial text deltas or wait for complete blocks?
5. **Concurrency limits**: Should parent enforce max concurrent sessions?
6. **Session affinity**: Should follow-up prompts reuse session context?
7. **Progress estimation**: Can we estimate completion % for long sessions?
8. **Cost budgets**: Should parent enforce max cost across all sessions?

## Success Criteria

### Phase 1: Core Session Agent
- [ ] ClaudeSessionAgent can run a prompt and emit signals
- [ ] Clean shutdown on completion
- [ ] Error handling for SDK failures

### Phase 2: Multi-Session Parent
- [ ] Parent agent can spawn multiple concurrent sessions
- [ ] Parent receives all turn signals with correct session_id correlation
- [ ] Session registry tracks status, turns, cost across all sessions
- [ ] Individual sessions can be cancelled

### Phase 3: Advanced Management
- [ ] Timeout watchdog detects and cleans up stale sessions
- [ ] Batch operations (cancel all, cleanup completed)
- [ ] Session queries (count, total cost, find by meta)

### Phase 4: Multi-Turn (Future)
- [ ] Follow-up prompts within same session context
