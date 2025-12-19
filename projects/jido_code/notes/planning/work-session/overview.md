# Work-Session Architecture: Multi-Project Support Plan

This plan introduces **work-sessions** as the top-level entity for managing isolated project contexts within a single JidoCode instance. Each session encapsulates its own project directory, sandbox boundaries, LLM configuration, conversation history, and task list. The TUI will display sessions as tabs, allowing users to work on multiple projects simultaneously.

## Overview

The work-session architecture enables a single user to manage up to 10 concurrent coding sessions, each operating in complete isolation. Sessions are displayed as tabs in the TUI using TermUI's Tabs widget, with each tab containing the full conversation interface. Sessions can be persisted to disk and restored via the `/resume` command.

**Key Deliverables**:
- `JidoCode.Session` struct and lifecycle management
- `JidoCode.SessionRegistry` for tracking active sessions (max 10)
- `JidoCode.SessionSupervisor` with per-session supervision trees
- `JidoCode.Session.Manager` for per-session sandbox isolation
- `JidoCode.Session.State` for conversation state management
- TUI tab integration with Ctrl+1 through Ctrl+0 for navigation
- Session commands: `/session new`, `/session list`, `/session close`, `/session rename`
- Session persistence with `/resume` command for restoration
- Auto-creation of default session for CWD on startup

## Phase Documents

- [Phase 1: Session Foundation](phase-01.md) - Session struct, registry, and supervisor infrastructure
- [Phase 2: Per-Session Manager and Security](phase-02.md) - Sandbox isolation per session
- [Phase 3: Tool Integration](phase-03.md) - Context threading through tool execution
- [Phase 4: TUI Tab Integration](phase-04.md) - Tabs widget and multi-session rendering
- [Phase 5: Session Commands](phase-05.md) - Command interface for session management
- [Phase 6: Session Persistence](phase-06.md) - Save/restore sessions with /resume
- [Phase 7: Testing and Polish](phase-07.md) - Integration tests, edge cases, documentation

## Architecture Overview

```
JidoCode.Supervisor (:one_for_one)
├── JidoCode.Settings.Cache (global settings ETS)
├── Phoenix.PubSub (JidoCode.PubSub)
├── Registry (named process lookup)
├── JidoCode.Tools.Registry (tool definitions - shared)
├── Task.Supervisor (async tasks)
│
├── JidoCode.SessionRegistry (ETS table for session metadata, max 10)
│
└── JidoCode.SessionSupervisor (DynamicSupervisor)
    │
    └── JidoCode.Session.Supervisor (:one_for_all, per session)
        ├── JidoCode.Session.Manager (project_root, Lua sandbox)
        ├── JidoCode.Agents.LLMAgent (with session context)
        └── JidoCode.Session.State (conversation state GenServer)
```

## Session Data Structure

```elixir
defmodule JidoCode.Session do
  @type t :: %__MODULE__{
    id: String.t(),           # UUID
    name: String.t(),         # Display name (folder name)
    project_path: String.t(), # Absolute project directory
    config: config(),         # LLM configuration
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @type config :: %{
    provider: String.t(),
    model: String.t(),
    temperature: float(),
    max_tokens: pos_integer()
  }
end
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Session limit | 10 | Balance between flexibility and resource management |
| Session naming | Folder name | Intuitive, automatic, unambiguous |
| Tab navigation | Ctrl+1 to Ctrl+0 | Standard terminal tab shortcuts (0 = 10th) |
| Default session | Auto-create CWD | Seamless startup experience |
| Persistence | Opt-in via /resume | No unexpected state restoration |
| State location | `~/.jido_code/sessions/` | Central, accessible location |

## Current State Analysis

### What Already Exists

| Component | Status | Location |
|-----------|--------|----------|
| LLMAgent session_id | Exists | `lib/jido_code/agents/llm_agent.ex` |
| AgentSupervisor | Exists | `lib/jido_code/agent_supervisor.ex` |
| PubSub per-session topics | Exists | `lib/jido_code/pubsub_topics.ex` |
| TermUI Tabs widget | Exists | `term_ui/lib/term_ui/widgets/tabs.ex` |
| Tool context support | Partial | `lib/jido_code/tools/handler_helpers.ex` |
| Settings system | Exists | `lib/jido_code/settings.ex` |

### Gaps to Fill

| Component | Gap | Phase |
|-----------|-----|-------|
| Session struct | Missing | Phase 1 |
| SessionRegistry | Missing | Phase 1 |
| SessionSupervisor | Missing | Phase 1 |
| Per-session Manager | Missing | Phase 2 |
| Tool context threading | Incomplete | Phase 3 |
| TUI tab rendering | Missing | Phase 4 |
| Session commands | Missing | Phase 5 |
| Session persistence | Missing | Phase 6 |

## Success Criteria

1. **Session Isolation**: Each session has isolated project_root, sandbox, config, and conversation
2. **Multi-Session TUI**: Users can view and switch between up to 10 session tabs
3. **Tab Navigation**: Ctrl+1 through Ctrl+0 switch to numbered sessions
4. **Session Commands**: `/session new|list|close|rename` work correctly
5. **Default Session**: Application starts with session for CWD
6. **Persistence**: Sessions saved to disk, restored via `/resume`
7. **Resource Management**: Max 10 sessions enforced, clear errors on limit
8. **Tool Security**: Each session's tools operate within its project boundary
9. **Fault Tolerance**: Session crashes don't affect other sessions
10. **Test Coverage**: Minimum 80% coverage for new session code

## Critical Files

**New Files:**
- `lib/jido_code/session.ex` - Session struct and creation
- `lib/jido_code/session_registry.ex` - ETS-backed session tracking
- `lib/jido_code/session_supervisor.ex` - DynamicSupervisor for sessions
- `lib/jido_code/session/supervisor.ex` - Per-session supervisor
- `lib/jido_code/session/manager.ex` - Per-session sandbox
- `lib/jido_code/session/state.ex` - Conversation state holder
- `lib/jido_code/session/settings.ex` - Per-project settings loader
- `lib/jido_code/session/persistence.ex` - Save/restore logic

**Modified Files:**
- `lib/jido_code/application.ex` - Add session infrastructure to supervision tree
- `lib/jido_code/tui.ex` - Multi-session model, tab rendering, event routing
- `lib/jido_code/commands.ex` - Add /session command family
- `lib/jido_code/tools/executor.ex` - Session-aware context
- `lib/jido_code/tools/handler_helpers.ex` - Require session context
- All tool handlers - Use context.project_root consistently

## Provides Foundation For

- **Multi-user support**: Session per user in shared instance
- **Workspace management**: Multiple related projects
- **Session templates**: Pre-configured project types
- **Session sharing**: Export/import session state
