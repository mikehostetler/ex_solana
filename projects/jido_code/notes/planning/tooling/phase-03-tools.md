# Phase 3: Git & LSP Integration

This phase implements version control and code intelligence tools. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All Git and LSP tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "git_command", "arguments": {...}}          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.git(subcommand, args, session_id: id)        │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.git(subcommand, args)"       │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_git/3 invoked from Lua                          │
│  (Elixir function registered as jido.git)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Git subcommand validation + Security checks                │
│  - Subcommand allowlist enforcement                         │
│  - Destructive operation guards                             │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Bridge Function | Purpose |
|------|-----------------|---------|
| git_command | `jido.git(subcommand, args)` | Safe git CLI passthrough |
| get_diagnostics | `jido.lsp_diagnostics(path, opts)` | LSP error/warning retrieval |
| get_hover_info | `jido.lsp_hover(path, line, char)` | Type and documentation at position |
| go_to_definition | `jido.lsp_definition(path, line, char)` | Symbol definition navigation |
| find_references | `jido.lsp_references(path, line, char)` | Symbol usage finding |

---

## 3.1 Git Command Tool

Implement the git_command tool for safe git CLI passthrough through the Lua sandbox.

### 3.1.1 Tool Definition

Create the git_command tool definition with safety constraints.

- [ ] 3.1.1.1 Create `lib/jido_code/tools/definitions/git_command.ex`
- [ ] 3.1.1.2 Define schema:
  ```elixir
  %{
    name: "git_command",
    description: "Execute git command. Some destructive operations blocked by default.",
    parameters: [
      %{name: "subcommand", type: :string, required: true, description: "Git subcommand (status, diff, log, etc.)"},
      %{name: "args", type: :array, required: false, description: "Additional arguments"},
      %{name: "allow_destructive", type: :boolean, required: false, description: "Allow destructive operations"}
    ]
  }
  ```
- [ ] 3.1.1.3 Document allowed and blocked subcommands
- [ ] 3.1.1.4 Register tool in definitions module

### 3.1.2 Bridge Function Implementation

Implement the Bridge function for git command execution within the Lua sandbox.

- [ ] 3.1.2.1 Add `lua_git/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_git(args, state, project_root) do
    case args do
      [subcommand] -> do_git(subcommand, [], %{}, state, project_root)
      [subcommand, cmd_args] -> do_git(subcommand, cmd_args, %{}, state, project_root)
      [subcommand, cmd_args, opts] -> do_git(subcommand, cmd_args, decode_opts(opts), state, project_root)
      _ -> {[nil, "git requires subcommand argument"], state}
    end
  end
  ```
- [ ] 3.1.2.2 Define allowed subcommands:
  - Always allowed: status, diff, log, show, branch, remote, fetch, stash list
  - With confirmation: add, commit, checkout, merge, rebase, stash push/pop
  - Blocked by default: push --force, reset --hard, clean -fd
- [ ] 3.1.2.3 Validate subcommand against allowlist
- [ ] 3.1.2.4 Block destructive operations unless allow_destructive=true
- [ ] 3.1.2.5 Execute git command in project directory
- [ ] 3.1.2.6 Parse common outputs for structured response:
  - status: Parse staged, unstaged, untracked files
  - diff: Parse file changes
  - log: Parse commits with hash, author, message
- [ ] 3.1.2.7 Return `{[%{output: output, parsed: structured}], state}` or `{[nil, error], state}`
- [ ] 3.1.2.8 Register in `Bridge.register/2`

### 3.1.3 Manager API

- [ ] 3.1.3.1 Add `git/3` to `Tools.Manager` that accepts subcommand and options
- [ ] 3.1.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.1.3.3 Call bridge function through Lua: `jido.git(subcommand, args, opts)`

### 3.1.4 Unit Tests for Git Command

- [ ] Test git_command through sandbox runs status
- [ ] Test git_command runs diff
- [ ] Test git_command runs log with format options
- [ ] Test git_command runs branch listing
- [ ] Test git_command blocks force push by default
- [ ] Test git_command allows force push with allow_destructive
- [ ] Test git_command blocks reset --hard by default
- [ ] Test git_command runs in project directory
- [ ] Test git_command parses status output
- [ ] Test git_command parses diff output
- [ ] Test git_command handles git errors

---

## 3.2 Get Diagnostics Tool

Implement the get_diagnostics tool for retrieving LSP errors, warnings, and hints through the Lua sandbox.

### 3.2.1 Tool Definition

Create the get_diagnostics tool definition for LSP integration.

- [ ] 3.2.1.1 Create `lib/jido_code/tools/definitions/get_diagnostics.ex`
- [ ] 3.2.1.2 Define schema:
  ```elixir
  %{
    name: "get_diagnostics",
    description: "Get LSP diagnostics (errors, warnings) for file or workspace.",
    parameters: [
      %{name: "path", type: :string, required: false, description: "File path (default: all)"},
      %{name: "severity", type: :string, required: false,
        enum: ["error", "warning", "info", "hint"], description: "Filter by severity"},
      %{name: "limit", type: :integer, required: false, description: "Maximum diagnostics to return"}
    ]
  }
  ```
- [ ] 3.2.1.3 Register tool in definitions module

### 3.2.2 Bridge Function Implementation

Implement the Bridge function for LSP diagnostics retrieval.

- [ ] 3.2.2.1 Add `lua_lsp_diagnostics/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_lsp_diagnostics(args, state, project_root) do
    case args do
      [] -> do_lsp_diagnostics(nil, %{}, state, project_root)
      [path] -> do_lsp_diagnostics(path, %{}, state, project_root)
      [path, opts] -> do_lsp_diagnostics(path, decode_opts(opts), state, project_root)
      _ -> {[nil, "lsp_diagnostics: invalid arguments"], state}
    end
  end
  ```
- [ ] 3.2.2.2 Use LSP client interface (abstraction over ElixirLS/Lexical)
- [ ] 3.2.2.3 Connect to running language server
- [ ] 3.2.2.4 Retrieve diagnostics for file or workspace
- [ ] 3.2.2.5 Filter by severity if specified
- [ ] 3.2.2.6 Format diagnostics with:
  - severity: error/warning/info/hint
  - file: relative path
  - line: line number
  - column: column number
  - message: diagnostic message
  - code: diagnostic code if available
- [ ] 3.2.2.7 Apply limit if specified
- [ ] 3.2.2.8 Return `{[diagnostics], state}` or `{[nil, error], state}`
- [ ] 3.2.2.9 Register in `Bridge.register/2`

### 3.2.3 Manager API

- [ ] 3.2.3.1 Add `lsp_diagnostics/2` to `Tools.Manager`
- [ ] 3.2.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.2.3.3 Call bridge function through Lua: `jido.lsp_diagnostics(path, opts)`

### 3.2.4 Unit Tests for Get Diagnostics

- [ ] Test get_diagnostics through sandbox retrieves compilation errors
- [ ] Test get_diagnostics retrieves warnings
- [ ] Test get_diagnostics filters by file path
- [ ] Test get_diagnostics filters by severity
- [ ] Test get_diagnostics respects limit
- [ ] Test get_diagnostics handles no diagnostics
- [ ] Test get_diagnostics handles LSP connection failure

---

## 3.3 Get Hover Info Tool

Implement the get_hover_info tool for retrieving type information and documentation through the Lua sandbox.

### 3.3.1 Tool Definition

Create the get_hover_info tool definition for code intelligence.

- [ ] 3.3.1.1 Create `lib/jido_code/tools/definitions/get_hover_info.ex`
- [ ] 3.3.1.2 Define schema:
  ```elixir
  %{
    name: "get_hover_info",
    description: "Get type info and documentation at cursor position.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "File path"},
      %{name: "line", type: :integer, required: true, description: "Line number (1-indexed)"},
      %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed)"}
    ]
  }
  ```
- [ ] 3.3.1.3 Register tool in definitions module

### 3.3.2 Bridge Function Implementation

Implement the Bridge function for LSP hover information.

- [ ] 3.3.2.1 Add `lua_lsp_hover/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_lsp_hover(args, state, project_root) do
    case args do
      [path, line, character] -> do_lsp_hover(path, line, character, state, project_root)
      _ -> {[nil, "lsp_hover requires path, line, character"], state}
    end
  end
  ```
- [ ] 3.3.2.2 Validate file path within boundary using `Security.validate_path/3`
- [ ] 3.3.2.3 Convert 1-indexed to 0-indexed for LSP protocol
- [ ] 3.3.2.4 Send hover request to LSP server
- [ ] 3.3.2.5 Parse response for:
  - Type signature
  - Documentation
  - Module information
  - Spec information
- [ ] 3.3.2.6 Format markdown content appropriately
- [ ] 3.3.2.7 Return `{[%{type: type, docs: docs}], state}` or `{[nil, error], state}`
- [ ] 3.3.2.8 Register in `Bridge.register/2`

### 3.3.3 Manager API

- [ ] 3.3.3.1 Add `lsp_hover/4` to `Tools.Manager`
- [ ] 3.3.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.3.3.3 Call bridge function through Lua: `jido.lsp_hover(path, line, character)`

### 3.3.4 Unit Tests for Get Hover Info

- [ ] Test get_hover_info through sandbox returns function documentation
- [ ] Test get_hover_info returns type information
- [ ] Test get_hover_info returns module docs
- [ ] Test get_hover_info handles unknown position
- [ ] Test get_hover_info validates file path
- [ ] Test get_hover_info handles LSP connection failure

---

## 3.4 Go To Definition Tool

Implement the go_to_definition tool for navigating to symbol definitions through the Lua sandbox.

### 3.4.1 Tool Definition

Create the go_to_definition tool definition.

- [ ] 3.4.1.1 Create `lib/jido_code/tools/definitions/go_to_definition.ex`
- [ ] 3.4.1.2 Define schema:
  ```elixir
  %{
    name: "go_to_definition",
    description: "Find where a symbol is defined.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "File path"},
      %{name: "line", type: :integer, required: true, description: "Line number (1-indexed)"},
      %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed)"}
    ]
  }
  ```
- [ ] 3.4.1.3 Register tool in definitions module

### 3.4.2 Bridge Function Implementation

Implement the Bridge function for definition navigation.

- [ ] 3.4.2.1 Add `lua_lsp_definition/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_lsp_definition(args, state, project_root) do
    case args do
      [path, line, character] -> do_lsp_definition(path, line, character, state, project_root)
      _ -> {[nil, "lsp_definition requires path, line, character"], state}
    end
  end
  ```
- [ ] 3.4.2.2 Validate file path within boundary
- [ ] 3.4.2.3 Send definition request to LSP
- [ ] 3.4.2.4 Parse location response
- [ ] 3.4.2.5 Return `{[%{path: path, line: line, character: char}], state}` or `{[nil, :not_found], state}`
- [ ] 3.4.2.6 Register in `Bridge.register/2`

### 3.4.3 Manager API

- [ ] 3.4.3.1 Add `lsp_definition/4` to `Tools.Manager`
- [ ] 3.4.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.4.3.3 Call bridge function through Lua: `jido.lsp_definition(path, line, character)`

### 3.4.4 Unit Tests for Go To Definition

- [ ] Test go_to_definition through sandbox finds function definition
- [ ] Test go_to_definition finds module definition
- [ ] Test go_to_definition handles no definition found

---

## 3.5 Find References Tool

Implement the find_references tool for finding all usages of a symbol through the Lua sandbox.

### 3.5.1 Tool Definition

Create the find_references tool definition.

- [ ] 3.5.1.1 Create `lib/jido_code/tools/definitions/find_references.ex`
- [ ] 3.5.1.2 Define schema:
  ```elixir
  %{
    name: "find_references",
    description: "Find all usages of a symbol.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "File path"},
      %{name: "line", type: :integer, required: true, description: "Line number (1-indexed)"},
      %{name: "character", type: :integer, required: true, description: "Character offset (1-indexed)"},
      %{name: "include_declaration", type: :boolean, required: false, description: "Include declaration (default: false)"}
    ]
  }
  ```
- [ ] 3.5.1.3 Register tool in definitions module

### 3.5.2 Bridge Function Implementation

Implement the Bridge function for reference finding.

- [ ] 3.5.2.1 Add `lua_lsp_references/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_lsp_references(args, state, project_root) do
    case args do
      [path, line, character] -> do_lsp_references(path, line, character, %{}, state, project_root)
      [path, line, character, opts] -> do_lsp_references(path, line, character, decode_opts(opts), state, project_root)
      _ -> {[nil, "lsp_references requires path, line, character"], state}
    end
  end
  ```
- [ ] 3.5.2.2 Validate file path within boundary
- [ ] 3.5.2.3 Send references request to LSP
- [ ] 3.5.2.4 Parse location list response
- [ ] 3.5.2.5 Return `{[[%{path: path, line: line, character: char}, ...]], state}` or `{[nil, error], state}`
- [ ] 3.5.2.6 Register in `Bridge.register/2`

### 3.5.3 Manager API

- [ ] 3.5.3.1 Add `lsp_references/4` to `Tools.Manager`
- [ ] 3.5.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 3.5.3.3 Call bridge function through Lua: `jido.lsp_references(path, line, character, opts)`

### 3.5.4 Unit Tests for Find References

- [ ] Test find_references through sandbox finds function usages
- [ ] Test find_references finds module usages
- [ ] Test find_references includes/excludes declaration

---

## 3.6 LSP Client Infrastructure

Implement the shared LSP client infrastructure used by all LSP bridge functions.

### 3.6.1 LSP Client Module

Create a reusable LSP client accessible from Bridge functions.

- [ ] 3.6.1.1 Create `lib/jido_code/tools/lsp/client.ex`
- [ ] 3.6.1.2 Implement connection to ElixirLS via stdio
- [ ] 3.6.1.3 Implement connection to Lexical as alternative
- [ ] 3.6.1.4 Handle initialize/initialized handshake
- [ ] 3.6.1.5 Implement request/response correlation
- [ ] 3.6.1.6 Handle notifications (for diagnostics)
- [ ] 3.6.1.7 Implement graceful shutdown

### 3.6.2 LSP Protocol Types

Define LSP protocol types for Bridge functions.

- [ ] 3.6.2.1 Create `lib/jido_code/tools/lsp/protocol.ex`
- [ ] 3.6.2.2 Define Position, Range, Location types
- [ ] 3.6.2.3 Define Diagnostic type
- [ ] 3.6.2.4 Define Hover type
- [ ] 3.6.2.5 Define TextDocumentIdentifier type

### 3.6.3 Unit Tests for LSP Client

- [ ] Test LSP client connection
- [ ] Test LSP request/response handling
- [ ] Test LSP notification handling
- [ ] Test LSP error handling

---

## 3.7 Phase 3 Integration Tests

Integration tests for Git and LSP tools working through the Lua sandbox.

### 3.7.1 Sandbox Integration

Verify tools execute through the sandbox correctly.

- [ ] 3.7.1.1 Create `test/jido_code/integration/tools_phase3_test.exs`
- [ ] 3.7.1.2 Test: All tools execute through `Tools.Manager` → Lua → Bridge chain
- [ ] 3.7.1.3 Test: Session-scoped managers are isolated

### 3.7.2 Git Integration

Test git tools in realistic scenarios through sandbox.

- [ ] 3.7.2.1 Test: git_command status works in initialized repo
- [ ] 3.7.2.2 Test: git_command diff shows file changes
- [ ] 3.7.2.3 Test: git_command log shows commit history
- [ ] 3.7.2.4 Test: git_command branch lists branches

### 3.7.3 LSP Integration

Test LSP tools with real language server through sandbox.

- [ ] 3.7.3.1 Test: diagnostics returned after file with syntax error
- [ ] 3.7.3.2 Test: diagnostics returned for undefined function
- [ ] 3.7.3.3 Test: hover info available for standard library functions
- [ ] 3.7.3.4 Test: hover info available for project functions
- [ ] 3.7.3.5 Test: go_to_definition navigates to function
- [ ] 3.7.3.6 Test: find_references locates function usages

---

## Phase 3 Success Criteria

1. **git_command**: Safe git passthrough via `jido.git` bridge
2. **get_diagnostics**: LSP diagnostics via `jido.lsp_diagnostics` bridge
3. **get_hover_info**: Type and docs via `jido.lsp_hover` bridge
4. **go_to_definition**: Definition navigation via `jido.lsp_definition` bridge
5. **find_references**: Reference finding via `jido.lsp_references` bridge
6. **LSP Client**: Reliable connection infrastructure
7. **All tools execute through Lua sandbox** (defense-in-depth)
8. **Test Coverage**: Minimum 80% for Phase 3 tools

---

## Phase 3 Critical Files

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add git and LSP bridge functions
- `lib/jido_code/tools/manager.ex` - Expose git and LSP APIs

**New Files:**
- `lib/jido_code/tools/definitions/git_command.ex`
- `lib/jido_code/tools/definitions/get_diagnostics.ex`
- `lib/jido_code/tools/definitions/get_hover_info.ex`
- `lib/jido_code/tools/definitions/go_to_definition.ex`
- `lib/jido_code/tools/definitions/find_references.ex`
- `lib/jido_code/tools/lsp/client.ex`
- `lib/jido_code/tools/lsp/protocol.ex`
- `test/jido_code/tools/bridge_git_lsp_test.exs`
- `test/jido_code/integration/tools_phase3_test.exs`
