# Phase 2: Code Search & Shell Execution

This phase implements code search capabilities using ripgrep and shell execution tools with background process support. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All search and shell tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "grep_search", "arguments": {...}}          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.grep(pattern, opts, session_id: id)          │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.grep(pattern, opts)"         │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_grep/3 invoked from Lua                         │
│  (Elixir function registered as jido.grep)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Security.validate_path(path, project_root) +               │
│  Security.validate_command(cmd) for shell tools             │
│  - Path boundary validation                                 │
│  - Command allowlist enforcement                            │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Bridge Function | Purpose |
|------|-----------------|---------|
| grep_search | `jido.grep(pattern, opts)` | Regex-based code searching with ripgrep |
| bash_execute | `jido.shell(cmd, opts)` | Foreground command execution |
| bash_background | `jido.shell_background(cmd)` | Background process spawning |
| bash_output | `jido.shell_output(shell_id)` | Background output retrieval |
| kill_shell | `jido.shell_kill(shell_id)` | Background process termination |

---

## 2.1 Grep Search Tool

Implement the grep_search tool using ripgrep for regex-based code searching. The tool executes through the Lua sandbox via the `jido.grep` bridge function.

### 2.1.1 Tool Definition

Create the grep_search tool definition with comprehensive options.

- [ ] 2.1.1.1 Create `lib/jido_code/tools/definitions/grep_search.ex`
- [ ] 2.1.1.2 Define comprehensive schema:
  ```elixir
  %{
    name: "grep_search",
    description: "Search file contents with regex pattern using ripgrep.",
    parameters: [
      %{name: "pattern", type: :string, required: true, description: "Regex pattern"},
      %{name: "path", type: :string, required: false, description: "Search directory"},
      %{name: "output_mode", type: :string, required: false,
        enum: ["content", "files_with_matches", "count"]},
      %{name: "context_before", type: :integer, required: false, description: "Lines before (-B)"},
      %{name: "context_after", type: :integer, required: false, description: "Lines after (-A)"},
      %{name: "context", type: :integer, required: false, description: "Lines before and after (-C)"},
      %{name: "file_type", type: :string, required: false, description: "File type filter (ex, js)"},
      %{name: "case_insensitive", type: :boolean, required: false},
      %{name: "multiline", type: :boolean, required: false},
      %{name: "head_limit", type: :integer, required: false, description: "Max results"}
    ]
  }
  ```
- [ ] 2.1.1.3 Register tool in definitions module

### 2.1.2 Bridge Function Implementation

Implement the Bridge function that executes within the Lua sandbox.

- [ ] 2.1.2.1 Add `lua_grep/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_grep(args, state, project_root) do
    case args do
      [pattern] -> do_grep(pattern, %{}, state, project_root)
      [pattern, opts] -> do_grep(pattern, decode_opts(opts), state, project_root)
      _ -> {[nil, "grep requires pattern argument"], state}
    end
  end
  ```
- [ ] 2.1.2.2 Validate search path within boundary using `Security.validate_path/3`
- [ ] 2.1.2.3 Build ripgrep command with all options
- [ ] 2.1.2.4 Execute ripgrep with timeout (default 30 seconds)
- [ ] 2.1.2.5 Parse output based on output_mode:
  - `content`: Show matching lines with context
  - `files_with_matches`: Show only file paths
  - `count`: Show match counts per file
- [ ] 2.1.2.6 Apply head_limit to truncate large results
- [ ] 2.1.2.7 Return `{[results], state}` or `{[nil, error], state}`
- [ ] 2.1.2.8 Register in `Bridge.register/2`:
  ```elixir
  |> register_function("grep", &lua_grep/3, project_root)
  ```

### 2.1.3 Manager API

Expose the tool through the Manager API for session-aware execution.

- [ ] 2.1.3.1 Add `grep/3` to `Tools.Manager` that accepts pattern and options
- [ ] 2.1.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.1.3.3 Call bridge function through Lua: `jido.grep(pattern, opts)`

### 2.1.4 Unit Tests for Grep Search

- [ ] Test grep_search through sandbox finds pattern matches
- [ ] Test grep_search with context_before lines
- [ ] Test grep_search with context_after lines
- [ ] Test grep_search with combined context
- [ ] Test grep_search with file type filter
- [ ] Test grep_search multiline mode
- [ ] Test grep_search output mode: content
- [ ] Test grep_search output mode: files_with_matches
- [ ] Test grep_search output mode: count
- [ ] Test grep_search case insensitive
- [ ] Test grep_search validates boundary through sandbox
- [ ] Test grep_search handles no matches gracefully
- [ ] Test grep_search handles invalid regex

---

## 2.2 Bash Execute Tool

Implement the bash_execute tool for foreground command execution through the Lua sandbox.

### 2.2.1 Tool Definition

Create the bash_execute tool definition for foreground commands.

- [ ] 2.2.1.1 Create `lib/jido_code/tools/definitions/bash_execute.ex`
- [ ] 2.2.1.2 Define schema:
  ```elixir
  %{
    name: "bash_execute",
    description: "Execute shell command. Command must be in allowlist.",
    parameters: [
      %{name: "command", type: :string, required: true, description: "Shell command"},
      %{name: "description", type: :string, required: false, description: "5-10 word description"},
      %{name: "timeout", type: :integer, required: false, description: "Timeout in ms (default: 120000)"},
      %{name: "working_directory", type: :string, required: false, description: "Override working directory"}
    ]
  }
  ```
- [ ] 2.2.1.3 Document allowed command patterns in description
- [ ] 2.2.1.4 Register tool in definitions module

### 2.2.2 Bridge Function Implementation

Implement the Bridge function for shell execution within the Lua sandbox.

- [ ] 2.2.2.1 Update existing `lua_shell/3` in `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell(args, state, project_root) do
    case args do
      [command] -> do_shell(command, %{}, state, project_root)
      [command, opts] -> do_shell(command, decode_opts(opts), state, project_root)
      _ -> {[nil, "shell requires command argument"], state}
    end
  end
  ```
- [ ] 2.2.2.2 Use `Security.validate_command/1` to check against allowlist:
  - Allowed: mix, git, npm, node, elixir, erl, rebar3, etc.
  - Blocked: bash, sh, zsh, rm -rf /, sudo, etc.
- [ ] 2.2.2.3 Block shell interpreters (bash, sh, zsh directly)
- [ ] 2.2.2.4 Block dangerous patterns (rm -rf /, etc.)
- [ ] 2.2.2.5 Set working directory to project root (or override if within boundary)
- [ ] 2.2.2.6 Execute command with System.cmd or Port
- [ ] 2.2.2.7 Apply timeout (default 120000ms, max 600000ms)
- [ ] 2.2.2.8 Capture stdout and stderr separately
- [ ] 2.2.2.9 Truncate output at 30,000 characters with indicator
- [ ] 2.2.2.10 Return `{[%{output: output, exit_code: code, stderr: stderr}], state}` or `{[nil, error], state}`

### 2.2.3 Manager API

- [ ] 2.2.3.1 Add `shell/2` to `Tools.Manager` that accepts command and options
- [ ] 2.2.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.2.3.3 Call bridge function through Lua: `jido.shell(command, opts)`

### 2.2.4 Unit Tests for Bash Execute

- [ ] Test bash_execute through sandbox runs allowed commands (mix compile)
- [ ] Test bash_execute runs git commands (git status)
- [ ] Test bash_execute blocks dangerous commands
- [ ] Test bash_execute blocks shell interpreters
- [ ] Test bash_execute respects timeout
- [ ] Test bash_execute handles timeout exceeded
- [ ] Test bash_execute captures exit code
- [ ] Test bash_execute captures stderr separately
- [ ] Test bash_execute truncates long output
- [ ] Test bash_execute uses project working directory
- [ ] Test bash_execute respects working_directory override within boundary

---

## 2.3 Bash Background Tool

Implement the bash_background tool for starting long-running processes through the Lua sandbox.

### 2.3.1 Tool Definition

Create the bash_background tool definition for background processes.

- [ ] 2.3.1.1 Create `lib/jido_code/tools/definitions/bash_background.ex`
- [ ] 2.3.1.2 Define schema:
  ```elixir
  %{
    name: "bash_background",
    description: "Start command in background. Returns shell_id for output retrieval.",
    parameters: [
      %{name: "command", type: :string, required: true, description: "Command to run"},
      %{name: "description", type: :string, required: false, description: "Description for tracking"}
    ]
  }
  ```
- [ ] 2.3.1.3 Register tool in definitions module

### 2.3.2 Bridge Function Implementation

Implement the Bridge function for background process management.

- [ ] 2.3.2.1 Add `lua_shell_background/3` to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell_background(args, state, project_root) do
    case args do
      [command] -> do_shell_background(command, %{}, state, project_root)
      [command, opts] -> do_shell_background(command, decode_opts(opts), state, project_root)
      _ -> {[nil, "shell_background requires command argument"], state}
    end
  end
  ```
- [ ] 2.3.2.2 Use `Security.validate_command/1` to check against allowlist
- [ ] 2.3.2.3 Start command as supervised Task
- [ ] 2.3.2.4 Generate unique shell_id (UUID or short hash)
- [ ] 2.3.2.5 Store process reference in session-scoped registry (in state)
- [ ] 2.3.2.6 Set up output streaming to accumulator
- [ ] 2.3.2.7 Return `{[%{shell_id: id, description: desc}], state}` with updated state
- [ ] 2.3.2.8 Register in `Bridge.register/2`

### 2.3.3 Manager API

- [ ] 2.3.3.1 Add `shell_background/2` to `Tools.Manager`
- [ ] 2.3.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.3.3.3 Call bridge function through Lua: `jido.shell_background(command, opts)`

### 2.3.4 Unit Tests for Bash Background

- [ ] Test bash_background through sandbox starts process
- [ ] Test bash_background returns unique shell_id
- [ ] Test bash_background process runs in background
- [ ] Test bash_background validates commands through Security module
- [ ] Test bash_background stores process in session state
- [ ] Test bash_background handles process crash

---

## 2.4 Bash Output Tool

Implement the bash_output tool for retrieving output from background processes through the Lua sandbox.

### 2.4.1 Tool Definition

Create the bash_output tool definition for output retrieval.

- [ ] 2.4.1.1 Create `lib/jido_code/tools/definitions/bash_output.ex`
- [ ] 2.4.1.2 Define schema:
  ```elixir
  %{
    name: "bash_output",
    description: "Get output from background shell process.",
    parameters: [
      %{name: "shell_id", type: :string, required: true, description: "ID from bash_background"},
      %{name: "block", type: :boolean, required: false, description: "Wait for completion (default: true)"},
      %{name: "timeout", type: :integer, required: false, description: "Max wait time in ms (default: 30000)"}
    ]
  }
  ```
- [ ] 2.4.1.3 Register tool in definitions module

### 2.4.2 Bridge Function Implementation

Implement the Bridge function for background output retrieval.

- [ ] 2.4.2.1 Add `lua_shell_output/3` to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell_output(args, state, project_root) do
    case args do
      [shell_id] -> do_shell_output(shell_id, %{block: true}, state, project_root)
      [shell_id, opts] -> do_shell_output(shell_id, decode_opts(opts), state, project_root)
      _ -> {[nil, "shell_output requires shell_id argument"], state}
    end
  end
  ```
- [ ] 2.4.2.2 Look up process by shell_id in session state
- [ ] 2.4.2.3 Handle non-existent shell_id gracefully
- [ ] 2.4.2.4 Retrieve accumulated output from process
- [ ] 2.4.2.5 Determine status (running/completed/failed)
- [ ] 2.4.2.6 If block=true, wait for completion up to timeout
- [ ] 2.4.2.7 Truncate output at 30,000 characters
- [ ] 2.4.2.8 Return `{[%{output: output, status: status, exit_code: code}], state}` or `{[nil, error], state}`
- [ ] 2.4.2.9 Register in `Bridge.register/2`

### 2.4.3 Manager API

- [ ] 2.4.3.1 Add `shell_output/2` to `Tools.Manager`
- [ ] 2.4.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.4.3.3 Call bridge function through Lua: `jido.shell_output(shell_id, opts)`

### 2.4.4 Unit Tests for Bash Output

- [ ] Test bash_output through sandbox retrieves output from running process
- [ ] Test bash_output retrieves output from completed process
- [ ] Test bash_output returns correct status
- [ ] Test bash_output blocking mode waits for completion
- [ ] Test bash_output non-blocking mode returns immediately
- [ ] Test bash_output handles timeout
- [ ] Test bash_output for non-existent shell_id

---

## 2.5 Kill Shell Tool

Implement the kill_shell tool for terminating background processes through the Lua sandbox.

### 2.5.1 Tool Definition

Create the kill_shell tool definition.

- [ ] 2.5.1.1 Create `lib/jido_code/tools/definitions/kill_shell.ex`
- [ ] 2.5.1.2 Define schema:
  ```elixir
  %{
    name: "kill_shell",
    description: "Terminate a background shell process.",
    parameters: [
      %{name: "shell_id", type: :string, required: true, description: "ID of background shell to kill"}
    ]
  }
  ```
- [ ] 2.5.1.3 Register tool in definitions module

### 2.5.2 Bridge Function Implementation

Implement the Bridge function for process termination.

- [ ] 2.5.2.1 Add `lua_shell_kill/3` to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_shell_kill(args, state, _project_root) do
    case args do
      [shell_id] -> do_shell_kill(shell_id, state)
      _ -> {[nil, "shell_kill requires shell_id argument"], state}
    end
  end
  ```
- [ ] 2.5.2.2 Look up process by shell_id in session state
- [ ] 2.5.2.3 Send termination signal (Process.exit or Task.shutdown)
- [ ] 2.5.2.4 Remove from session state registry
- [ ] 2.5.2.5 Return `{[true], updated_state}` or `{[nil, error], state}`
- [ ] 2.5.2.6 Register in `Bridge.register/2`

### 2.5.3 Manager API

- [ ] 2.5.3.1 Add `shell_kill/2` to `Tools.Manager`
- [ ] 2.5.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 2.5.3.3 Call bridge function through Lua: `jido.shell_kill(shell_id)`

### 2.5.4 Unit Tests for Kill Shell

- [ ] Test kill_shell through sandbox terminates running process
- [ ] Test kill_shell handles already-terminated process
- [ ] Test kill_shell handles non-existent shell_id
- [ ] Test kill_shell removes process from session state

---

## 2.6 Phase 2 Integration Tests

Integration tests for search and shell tools working through the Lua sandbox.

### 2.6.1 Sandbox Integration

Verify tools execute through the sandbox correctly.

- [ ] 2.6.1.1 Create `test/jido_code/integration/tools_phase2_test.exs`
- [ ] 2.6.1.2 Test: All tools execute through `Tools.Manager` → Lua → Bridge → Security chain
- [ ] 2.6.1.3 Test: Lua VM has dangerous functions removed (os.execute unavailable)
- [ ] 2.6.1.4 Test: Session-scoped managers are isolated (shell_ids don't leak between sessions)

### 2.6.2 Search Integration

Test search tools in realistic scenarios through sandbox.

- [ ] 2.6.2.1 Test: Create files with content → grep finds matches → context lines correct
- [ ] 2.6.2.2 Test: grep with file type filter only searches matching files
- [ ] 2.6.2.3 Test: grep respects project boundary

### 2.6.3 Shell Integration

Test shell tools in realistic scenarios through sandbox.

- [ ] 2.6.3.1 Test: bash_execute runs mix commands successfully
- [ ] 2.6.3.2 Test: bash_execute → verify output matches expected
- [ ] 2.6.3.3 Test: bash_background starts long-running process → bash_output retrieves output
- [ ] 2.6.3.4 Test: Background process completion detected
- [ ] 2.6.3.5 Test: kill_shell terminates running background process

### 2.6.4 Security Integration

Test security measures across shell tools via sandbox.

- [ ] 2.6.4.1 Test: grep respects project boundary (via Security.validate_path)
- [ ] 2.6.4.2 Test: bash commands blocked for shell injection patterns (via Security.validate_command)
- [ ] 2.6.4.3 Test: Commands run in project directory
- [ ] 2.6.4.4 Test: Dangerous command patterns rejected
- [ ] 2.6.4.5 Test: Direct Lua execution of os.execute fails (sandbox restriction)

---

## Phase 2 Success Criteria

1. **grep_search**: Ripgrep search via `jido.grep` bridge
2. **bash_execute**: Foreground execution via `jido.shell` bridge
3. **bash_background**: Background spawning via `jido.shell_background` bridge
4. **bash_output**: Output retrieval via `jido.shell_output` bridge
5. **kill_shell**: Process termination via `jido.shell_kill` bridge
6. **All tools execute through Lua sandbox** (defense-in-depth)
7. **Test Coverage**: Minimum 80% for Phase 2 tools

---

## Phase 2 Critical Files

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add/update bridge functions for grep and shell
- `lib/jido_code/tools/manager.ex` - Expose grep and shell APIs
- `lib/jido_code/tools/security.ex` - Ensure `validate_command/1` exists

**New Files:**
- `lib/jido_code/tools/definitions/grep_search.ex`
- `lib/jido_code/tools/definitions/bash_execute.ex`
- `lib/jido_code/tools/definitions/bash_background.ex`
- `lib/jido_code/tools/definitions/bash_output.ex`
- `lib/jido_code/tools/definitions/kill_shell.ex`
- `test/jido_code/tools/bridge_search_shell_test.exs`
- `test/jido_code/integration/tools_phase2_test.exs`
