# JidoCode Tools Implementation Plan

## Overview

This plan implements the **30 core tools** for JidoCode based on the comprehensive tools reference research (notes/research/1.06-tooling/1.05.1-comprehensive-tools-reference.md). The implementation follows proven patterns from Claude Code, OpenCode, Aider, and other major coding assistants, while adding Elixir/BEAM-specific capabilities.

## Tool Categories

| Category | Tools | Count |
|----------|-------|-------|
| File Operations | read_file, write_file, edit_file, multi_edit, list_dir, glob_search, delete_file | 7 |
| Code Search | grep_search, codebase_search, repo_map | 3 |
| Shell Execution | bash_execute, bash_background, bash_output | 3 |
| Git Operations | git_command | 1 |
| LSP Integration | get_diagnostics, get_hover_info | 2 |
| Web Tools | web_fetch, web_search | 2 |
| Agent/Task | spawn_subagent, todo_write, todo_read | 3 |
| User Interaction | ask_user | 1 |
| Elixir-Specific | iex_eval, mix_task, get_process_state, inspect_supervisor, reload_module, ets_inspect, fetch_elixir_docs, run_exunit | 8 |
| **Total** | | **30** |

## Phase Documents

- [Phase 1: File Operations & Core Tools](phase-01-tools.md) - Foundation file system tools
- [Phase 2: Code Search & Shell Execution](phase-02-tools.md) - Search and terminal tools
- [Phase 3: Git & LSP Integration](phase-03-tools.md) - Version control and code intelligence
- [Phase 4: Web & Agent Tools](phase-04-tools.md) - Web access and task delegation
- [Phase 5: Elixir-Specific Tools](phase-05-tools.md) - BEAM runtime introspection
- [Phase 6: Testing & Polish](phase-06-tools.md) - Integration tests, edge cases, documentation

## Implementation Priority

Based on the research recommendations:

| Phase | Tools | Priority |
|-------|-------|----------|
| Phase 1 | read_file, write_file, edit_file, list_dir, glob_search, delete_file, multi_edit | MVP - Core file operations |
| Phase 2 | grep_search, bash_execute, bash_background, bash_output | MVP - Search and shell |
| Phase 3 | git_command, get_diagnostics, get_hover_info | Core - VCS and LSP |
| Phase 4 | web_fetch, web_search, spawn_subagent, todo_write, todo_read, ask_user | Core - Web and agents |
| Phase 5 | iex_eval, mix_task, get_process_state, inspect_supervisor, reload_module, ets_inspect, fetch_elixir_docs, run_exunit | Advanced - Elixir-specific |
| Phase 6 | codebase_search, repo_map | Advanced - Semantic search |

## Architecture

All tools route through the Lua sandbox for defense-in-depth security (see [ADR-0001](../../decisions/0001-tool-security-architecture.md)).

```
┌─────────────────────────────────────────────────────────────┐
│                     Tool Executor                            │
│  Dispatches all tool calls through Lua sandbox              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Lua Sandbox (Tools.Manager)                │
│  - Dangerous Lua functions removed                          │
│  - All operations via Bridge functions                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Bridge Functions (Tools.Bridge)            │
│  - jido.read_file(), jido.write_file(), jido.shell(), etc. │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Tools.Security Module                      │
│  - validate_path/3, atomic_read/2, atomic_write/3           │
└─────────────────────────────────────────────────────────────┘
```

File structure:

```
lib/jido_code/tools/
├── definitions/           # Tool schemas and metadata
├── bridge.ex              # Lua bridge functions (security layer 1)
├── manager.ex             # Lua sandbox manager
├── security.ex            # Path/command validation (security layer 2)
├── registry.ex            # Tool registration (ETS-backed)
└── executor.ex            # Tool dispatch through sandbox
```

## Critical Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Security model | All tools through Lua sandbox | Defense-in-depth, two security layers ([ADR-0001](../../decisions/0001-tool-security-architecture.md)) |
| Edit strategy | Search/replace with multi-strategy matching | Higher success rate, matches Claude Code/OpenCode |
| Read format | Line-numbered (cat -n style) | Enables precise edit references |
| Shell persistence | Persistent shell session | State maintained across calls |
| Output truncation | 30,000 characters | Matches Claude Code pattern |
| Background processes | Task-based with output retrieval | Clean async pattern |

## Success Criteria

1. **30 tools implemented** with full test coverage
2. **File operations**: Read, write, edit, multi-edit, list, glob, delete
3. **Code search**: Grep with context, file type filtering
4. **Shell execution**: Foreground and background with output retrieval
5. **Git integration**: Safe git command passthrough
6. **LSP integration**: Diagnostics and hover info
7. **Web tools**: Fetch and search with caching
8. **Agent tools**: Subagent delegation, todo tracking
9. **Elixir-specific**: IEx, Mix, process introspection, hot reload, ETS
10. **Test coverage**: Minimum 80% across all tools
11. **Security**: All tools respect session boundaries
