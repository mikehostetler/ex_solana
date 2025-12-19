# Phase 3: Tool Calling and Sandbox

This phase implements the tool calling infrastructure that enables the LLM agent to interact with the codebase. All tool execution is sandboxed through a Lua-based tool manager that enforces security boundaries, preventing direct shell access and restricting operations to the current project directory.

## 3.1 Tool Infrastructure

The tool system defines a schema for tools, handles registration, and manages the execution flow between the LLM agent and the sandboxed tool manager.

### 3.1.1 Tool Schema and Registration
- [x] **Task 3.1.1 Complete**

Define the tool schema and implement tool registration.

- [x] 3.1.1.1 Create `JidoCode.Tools` namespace module
- [x] 3.1.1.2 Define tool schema struct: `%Tool{name, description, parameters, handler}`
- [x] 3.1.1.3 Define parameter schema: `%Param{name, type, description, required}`
- [x] 3.1.1.4 Create `JidoCode.Tools.Registry` for tool registration and lookup
- [x] 3.1.1.5 Implement `Registry.register/1` to add tools at startup
- [x] 3.1.1.6 Implement `Registry.list/0` returning all registered tools
- [x] 3.1.1.7 Implement `Registry.get/1` to lookup tool by name
- [x] 3.1.1.8 Generate tool descriptions in LLM-compatible format for system prompt
- [x] 3.1.1.9 Write registry tests (success: tools register and lookup correctly)

### 3.1.2 Tool Execution Flow
- [x] **Task 3.1.2 Complete**

Implement the flow from LLM tool call to sandboxed execution and result handling.

- [x] 3.1.2.1 Create `JidoCode.Tools.Executor` module for tool execution coordination
- [x] 3.1.2.2 Parse tool calls from LLM response (JSON function calling format)
- [x] 3.1.2.3 Validate tool name exists in registry
- [x] 3.1.2.4 Validate parameters against tool schema (type checking, required fields)
- [x] 3.1.2.5 Delegate execution to ToolManager (never execute directly)
- [x] 3.1.2.6 Handle tool execution timeout (configurable, default 30s)
- [x] 3.1.2.7 Format tool results for LLM consumption
- [x] 3.1.2.8 Support sequential tool calls (one result feeds into next call)
- [x] 3.1.2.9 Write execution flow tests with mock tool manager (success: full round-trip)

## 3.2 Lua Sandbox Tool Manager

All tool execution is delegated to a Lua-based sandbox using the `luerl` Erlang library. The tool manager enforces security boundaries: no direct shell access, no operations outside project directory, controlled API access.

### 3.2.1 Luerl Integration
- [x] **Task 3.2.1 Complete**

Set up the Luerl Lua runtime integration for sandboxed execution.

- [x] 3.2.1.1 Add `luerl` dependency to mix.exs
- [x] 3.2.1.2 Create `JidoCode.Tools.Manager` module wrapping Luerl
- [x] 3.2.1.3 Initialize Lua state with restricted standard library (no `os.execute`, `io.popen`, `loadfile`)
- [x] 3.2.1.4 Implement `Manager.start_link/1` as GenServer for state management
- [x] 3.2.1.5 Store project root path in Manager state for boundary enforcement
- [x] 3.2.1.6 Implement `Manager.execute/3` accepting tool name, params, and timeout
- [x] 3.2.1.7 Add Manager to supervision tree under AgentSupervisor
- [x] 3.2.1.8 Write Luerl integration tests (success: Lua code executes in sandbox)

### 3.2.2 Security Boundaries
- [x] **Task 3.2.2 Complete**

Implement security restrictions to prevent unauthorized access.

- [x] 3.2.2.1 Define project boundary as current working directory at startup
- [x] 3.2.2.2 Implement `validate_path/1` ensuring all paths resolve within project boundary
- [x] 3.2.2.3 Reject any path containing `..` that escapes project root after resolution
- [x] 3.2.2.4 Reject absolute paths outside project directory
- [x] 3.2.2.5 Reject symlinks pointing outside project directory
- [x] 3.2.2.6 Block all direct shell execution (no `os.execute`, `io.popen` equivalents)
- [x] 3.2.2.7 Whitelist allowed Lua standard library functions
- [x] 3.2.2.8 Implement resource limits: memory cap, execution time cap
- [x] 3.2.2.9 Log all security boundary violations for debugging
- [x] 3.2.2.10 Write security boundary tests (success: escape attempts blocked)

### 3.2.3 Erlang Bridge Functions
- [x] **Task 3.2.3 Complete**

Expose controlled Erlang functions to Lua for file, shell, and API operations.

- [x] 3.2.3.1 Create `JidoCode.Tools.Bridge` module for Erlang-Lua bindings
- [x] 3.2.3.2 Implement `lua_read_file/3` - read file contents (path validated)
- [x] 3.2.3.3 Implement `lua_write_file/3` - write file contents (path validated)
- [x] 3.2.3.4 Implement `lua_list_dir/3` - list directory contents (path validated)
- [x] 3.2.3.5 Implement `lua_file_exists/3` - check file existence (path validated)
- [x] 3.2.3.6 Implement `lua_shell/3` - execute shell command via controlled subprocess
- [x] 3.2.3.7 Shell bridge captures stdout/stderr, runs in project dir (timeout TBD)
- [ ] 3.2.3.8 Implement `bridge_http/2` - HTTP requests via Req (deferred - not needed for POC)
- [x] 3.2.3.9 Register all bridge functions in Lua state as `jido.*` namespace
- [x] 3.2.3.10 Write bridge function tests (success: operations work within boundaries)

## 3.3 Core Coding Tools

Implement the essential tools for coding assistance: file operations, search, and shell execution.

### 3.3.1 File System Tools
- [x] **Task 3.3.1 Complete**

Create tools for reading and writing files.

- [x] 3.3.1.1 Create `read_file` tool: read file contents, params: `{path: string}`
- [x] 3.3.1.2 Create `write_file` tool: write/overwrite file, params: `{path: string, content: string}`
- [x] 3.3.1.3 Create `list_directory` tool: list files/dirs, params: `{path: string, recursive: boolean}`
- [x] 3.3.1.4 Create `file_info` tool: get file metadata, params: `{path: string}`
- [x] 3.3.1.5 Create `create_directory` tool: create dir, params: `{path: string}`
- [x] 3.3.1.6 Create `delete_file` tool: remove file, params: `{path: string}` (with confirmation flag)
- [x] 3.3.1.7 All file tools delegate to ToolManager bridge functions
- [x] 3.3.1.8 Return structured results: `{ok: content}` or `{error: reason}`
- [x] 3.3.1.9 Write file tool tests (success: CRUD operations work)

### 3.3.2 Search Tools
- [x] **Task 3.3.2 Complete**

Create tools for searching the codebase.

- [x] 3.3.2.1 Create `grep` tool: search file contents, params: `{pattern: string, path: string, recursive: boolean}`
- [x] 3.3.2.2 Create `find_files` tool: find files by name/glob, params: `{pattern: string, path: string}`
- [x] 3.3.2.3 Grep tool returns matched lines with file paths and line numbers
- [x] 3.3.2.4 Find tool returns list of matching file paths
- [x] 3.3.2.5 Implement result truncation for large result sets (configurable limit)
- [x] 3.3.2.6 Search tools delegate to ToolManager for execution
- [x] 3.3.2.7 Write search tool tests (success: patterns match correctly)

### 3.3.3 Shell Execution Tool
- [x] **Task 3.3.3 Complete**

Create controlled shell execution tool.

- [x] 3.3.3.1 Create `run_command` tool: execute shell command, params: `{command: string, args: [string]}`
- [x] 3.3.3.2 Command runs in project directory (cwd enforced)
- [x] 3.3.3.3 Capture stdout and stderr separately (Note: merged for POC simplicity)
- [x] 3.3.3.4 Return exit code with output: `{exit_code: int, stdout: string, stderr: string}`
- [x] 3.3.3.5 Enforce execution timeout (default 25s, configurable)
- [x] 3.3.3.6 Allow/block specific commands via allowlist and shell interpreter blocking
- [x] 3.3.3.7 Shell tool uses direct Elixir execution with security validation (matches FileSystem pattern)
- [x] 3.3.3.8 Write shell tool tests with safe commands (success: commands execute in sandbox)
- [x] 3.3.3.9 Path argument validation blocks traversal and absolute paths outside project
- [x] 3.3.3.10 Output truncation at 1MB prevents memory exhaustion

## 3.4 Tool Result Handling

Display tool calls and results in the TUI for transparency.

### 3.4.1 Tool Call Display
- [x] **Task 3.4.1 Complete**

Show tool invocations and results in the TUI conversation.

- [x] 3.4.1.1 Broadcast `{:tool_call, tool_name, params, call_id}` via PubSub when tool is invoked
- [x] 3.4.1.2 Broadcast `{:tool_result, result}` when tool completes (Result struct)
- [x] 3.4.1.3 TUI displays tool calls with distinct styling (e.g., dimmed, prefixed with "⚙")
- [x] 3.4.1.4 Display tool parameters in condensed format
- [x] 3.4.1.5 Display tool results with syntax highlighting for code/file contents
- [x] 3.4.1.6 Truncate long results with "Show more" indicator
- [x] 3.4.1.7 Handle tool errors with red error styling
- [x] 3.4.1.8 Add toggle keybinding (Ctrl+T) to show/hide tool call details
- [x] 3.4.1.9 Write TUI tool display tests (success: tool calls render correctly)

**Phase 1 - PubSub Infrastructure:**
- Created `JidoCode.Tools.Display` module for formatting tool calls and results
- Added PubSub broadcasting to Executor for tool_call and tool_result events
- Session-specific topic routing via `:session_id` option
- Display formatting with truncation, syntax detection, and status icons

**Phase 2 - TUI Integration:**
- Added `tool_calls` and `show_tool_details` fields to TUI Model
- Implemented `{:tool_call, ...}` and `{:tool_result, ...}` message handling
- Added Ctrl+T toggle for show/hide tool details
- Created `format_tool_call_entry/2` for rendering tool calls in conversation
- Status-based styling: ✓ green (success), ✗ red (error), ⏱ yellow (timeout)
- Truncation with "[...]" when show_tool_details is false
- Status bar shows "Ctrl+T: Tools" / "Ctrl+T: Hide" hint
- 26 new tests (150 total TUI tests)
