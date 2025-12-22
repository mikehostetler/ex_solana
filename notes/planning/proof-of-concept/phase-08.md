# Phase 8: Extended Tool System

This phase extends the JidoCode tool system with advanced coding assistant capabilities. Building on the existing file system, search, and shell tools, this phase adds targeted file editing, Livebook notebook support, web integration for documentation lookup, task tracking, and multi-agent task spawning using the Jido framework.

## 8.1 File Editing Tools

The existing `write_file` tool overwrites entire files. This section adds targeted string replacement capabilities for precise code modifications without rewriting full files.

### 8.1.1 Edit Tool Implementation
- [ ] **Task 8.1.1**

Implement an `edit_file` tool that performs exact string replacement within files, similar to sed but with explicit old/new string matching for safety and predictability.

- [ ] 8.1.1.1 Create `JidoCode.Tools.Handlers.FileSystem.EditFile` handler module
- [ ] 8.1.1.2 Implement `execute/2` with parameters: `path`, `old_string`, `new_string`, `replace_all` (boolean)
- [ ] 8.1.1.3 Add validation that `old_string` exists in file (fail if not found)
- [ ] 8.1.1.4 Add validation that `old_string` is unique when `replace_all: false` (fail if ambiguous)
- [ ] 8.1.1.5 Use `Security.atomic_write/4` for TOCTOU-safe file modification
- [ ] 8.1.1.6 Return success message with replacement count
- [ ] 8.1.1.7 Add `edit_file/0` definition to `Definitions.FileSystem` module
- [ ] 8.1.1.8 Register tool with parameters: path (string, required), old_string (string, required), new_string (string, required), replace_all (boolean, default: false)
- [ ] 8.1.1.9 Write unit tests for EditFile handler (success: single replacement, multiple replacement, not found error, ambiguous match error)

### 8.1.2 Edit Tool Unit Tests
- [ ] **Task 8.1.2**

Create comprehensive unit tests for the edit tool covering all edge cases and error conditions.

- [ ] 8.1.2.1 Test single string replacement succeeds
- [ ] 8.1.2.2 Test `replace_all: true` replaces all occurrences
- [ ] 8.1.2.3 Test error when `old_string` not found in file
- [ ] 8.1.2.4 Test error when `old_string` matches multiple times with `replace_all: false`
- [ ] 8.1.2.5 Test path validation via Security module
- [ ] 8.1.2.6 Test atomic write prevents partial modifications on error
- [ ] 8.1.2.7 Test Unicode string handling
- [ ] 8.1.2.8 Test multiline string replacement

## 8.2 Livebook Integration

Elixir Livebook uses `.livemd` files - a markdown-based format with embedded code cells. This section adds tools for programmatic manipulation of Livebook notebooks.

### 8.2.1 Livebook Parser
- [ ] **Task 8.2.1**

Create a parser module for `.livemd` files that extracts notebook structure including markdown content, code cells, and metadata.

- [ ] 8.2.1.1 Create `JidoCode.Livebook.Parser` module
- [ ] 8.2.1.2 Define `Notebook` struct with sections, cells, and metadata
- [ ] 8.2.1.3 Define `Cell` struct with type (`:markdown`, `:elixir`, `:erlang`, `:smart`), content, and metadata
- [ ] 8.2.1.4 Implement `parse/1` to convert .livemd string to `%Notebook{}`
- [ ] 8.2.1.5 Parse Elixir code cells (```elixir ... ```)
- [ ] 8.2.1.6 Parse Erlang code cells (```erlang ... ```)
- [ ] 8.2.1.7 Parse smart cell metadata from HTML comments (`<!-- livebook:{...} -->`)
- [ ] 8.2.1.8 Parse markdown sections between code cells
- [ ] 8.2.1.9 Write parser unit tests (success: parse sample .livemd files correctly)

### 8.2.2 Livebook Serializer
- [ ] **Task 8.2.2**

Create a serializer that converts the notebook structure back to valid `.livemd` format.

- [ ] 8.2.2.1 Implement `serialize/1` to convert `%Notebook{}` to .livemd string
- [ ] 8.2.2.2 Serialize code cells with proper fence markers
- [ ] 8.2.2.3 Serialize smart cell metadata as HTML comments
- [ ] 8.2.2.4 Preserve cell ordering and section structure
- [ ] 8.2.2.5 Handle edge cases (empty cells, special characters)
- [ ] 8.2.2.6 Write serializer unit tests (success: round-trip parse/serialize preserves content)

### 8.2.3 LivebookEdit Tool
- [ ] **Task 8.2.3**

Implement the LivebookEdit tool for modifying notebook cells by index or ID.

- [ ] 8.2.3.1 Create `JidoCode.Tools.Handlers.Livebook.EditCell` handler
- [ ] 8.2.3.2 Implement cell replacement by index (`cell_index` parameter)
- [ ] 8.2.3.3 Implement cell insertion (`edit_mode: "insert"`, inserts after specified index)
- [ ] 8.2.3.4 Implement cell deletion (`edit_mode: "delete"`)
- [ ] 8.2.3.5 Support `cell_type` parameter for new cells (`:elixir`, `:markdown`, `:erlang`)
- [ ] 8.2.3.6 Validate cell index bounds
- [ ] 8.2.3.7 Use Security.atomic_write for safe file modification
- [ ] 8.2.3.8 Add `livebook_edit/0` definition to new `Definitions.Livebook` module
- [ ] 8.2.3.9 Register tool with parameters: notebook_path (string), cell_index (integer), new_source (string), cell_type (string, optional), edit_mode (string: replace/insert/delete)

### 8.2.4 Livebook Unit Tests
- [ ] **Task 8.2.4**

Create unit tests for Livebook parser, serializer, and edit tool.

- [ ] 8.2.4.1 Test parsing notebook with mixed cell types
- [ ] 8.2.4.2 Test parsing smart cells with JSON metadata
- [ ] 8.2.4.3 Test serialize/parse round-trip preserves content
- [ ] 8.2.4.4 Test cell replacement at valid index
- [ ] 8.2.4.5 Test cell insertion after index
- [ ] 8.2.4.6 Test cell deletion
- [ ] 8.2.4.7 Test error on invalid cell index
- [ ] 8.2.4.8 Test path validation for notebook files

## 8.3 Web Integration Tools

Web tools enable the agent to fetch documentation and search for information online, improving assistance quality for unfamiliar APIs and libraries.

### 8.3.1 WebFetch Tool
- [ ] **Task 8.3.1**

Implement a WebFetch tool that retrieves content from URLs, converts HTML to markdown, and optionally processes with a prompt.

- [ ] 8.3.1.1 Create `JidoCode.Tools.Handlers.Web.Fetch` handler module
- [ ] 8.3.1.2 Add `Req` HTTP client calls with timeout (default 30s)
- [ ] 8.3.1.3 Implement HTML to markdown conversion (use `Floki` for parsing, custom converter)
- [ ] 8.3.1.4 Add domain allowlist configuration in Settings (`allowed_domains` list)
- [ ] 8.3.1.5 Validate URL against allowlist before fetching
- [ ] 8.3.1.6 Add response size limit (default 1MB) to prevent memory exhaustion
- [ ] 8.3.1.7 Handle redirects (follow up to 5 redirects)
- [ ] 8.3.1.8 Return structured result with URL, title, and content
- [ ] 8.3.1.9 Add `web_fetch/0` definition to new `Definitions.Web` module
- [ ] 8.3.1.10 Register tool with parameters: url (string, required), prompt (string, optional)

### 8.3.2 WebSearch Tool
- [ ] **Task 8.3.2**

Implement a WebSearch tool that queries a search API and returns results for research tasks.

- [ ] 8.3.2.1 Create `JidoCode.Tools.Handlers.Web.Search` handler module
- [ ] 8.3.2.2 Define search provider interface (`search/2` callback)
- [ ] 8.3.2.3 Implement DuckDuckGo provider as default (no API key required)
- [ ] 8.3.2.4 Implement SerpAPI provider as optional (configurable API key in Settings)
- [ ] 8.3.2.5 Add `search_api_key` and `search_provider` to Settings schema
- [ ] 8.3.2.6 Parse search results into structured format (title, url, snippet)
- [ ] 8.3.2.7 Limit results count (default 10, max 20)
- [ ] 8.3.2.8 Add rate limiting (max 10 requests per minute)
- [ ] 8.3.2.9 Add `web_search/0` definition to `Definitions.Web` module
- [ ] 8.3.2.10 Register tool with parameters: query (string, required), num_results (integer, optional)

### 8.3.3 Web Tools Security
- [ ] **Task 8.3.3**

Implement security measures for web tools to prevent abuse and data exfiltration.

- [ ] 8.3.3.1 Create `JidoCode.Tools.Security.Web` module
- [ ] 8.3.3.2 Implement domain allowlist validation (default: hexdocs.pm, elixir-lang.org, erlang.org, github.com)
- [ ] 8.3.3.3 Add URL sanitization (block file://, javascript:, data: schemes)
- [ ] 8.3.3.4 Implement request timeout enforcement
- [ ] 8.3.3.5 Add response content type validation (only text/html, application/json)
- [ ] 8.3.3.6 Log all web requests for audit trail
- [ ] 8.3.3.7 Add Settings option to disable web tools entirely (`web_tools_enabled: false`)

### 8.3.4 Web Tools Unit Tests
- [ ] **Task 8.3.4**

Create unit tests for web tools with mocked HTTP responses.

- [ ] 8.3.4.1 Test WebFetch with mocked HTML response
- [ ] 8.3.4.2 Test HTML to markdown conversion
- [ ] 8.3.4.3 Test domain allowlist blocking
- [ ] 8.3.4.4 Test response size limit enforcement
- [ ] 8.3.4.5 Test WebSearch result parsing
- [ ] 8.3.4.6 Test rate limiting
- [ ] 8.3.4.7 Test URL sanitization blocks dangerous schemes
- [ ] 8.3.4.8 Test timeout handling

## 8.4 Task Tracking Tool

A task tracking tool allows the agent to maintain a structured list of work items, improving multi-step task execution and progress visibility.

### 8.4.1 TodoWrite Tool
- [ ] **Task 8.4.1**

Implement a TodoWrite tool for managing task lists with status tracking.

- [ ] 8.4.1.1 Create `JidoCode.Tools.Handlers.Todo` handler module
- [ ] 8.4.1.2 Define `Todo` struct with fields: content (string), status (pending/in_progress/completed), active_form (string)
- [ ] 8.4.1.3 Implement `execute/2` accepting `todos` array parameter
- [ ] 8.4.1.4 Store todos in session state (via TUI Model or dedicated GenServer)
- [ ] 8.4.1.5 Validate todo structure (content required, status enum validation)
- [ ] 8.4.1.6 Broadcast todo updates via PubSub for TUI display
- [ ] 8.4.1.7 Add `todo_write/0` definition to new `Definitions.Todo` module
- [ ] 8.4.1.8 Register tool with parameters: todos (array of objects with content, status, active_form)

### 8.4.2 Todo Display Integration
- [ ] **Task 8.4.2**

Integrate todo display into the TUI for user visibility.

- [ ] 8.4.2.1 Add `todos` field to TUI Model struct
- [ ] 8.4.2.2 Create `ViewHelpers.render_todos/1` function
- [ ] 8.4.2.3 Add todo panel to TUI view (collapsible, below status bar)
- [ ] 8.4.2.4 Show status indicators: ○ pending, ● in_progress, ✓ completed
- [ ] 8.4.2.5 Display `active_form` text for in_progress items
- [ ] 8.4.2.6 Handle `{:todo_update, todos}` message in TUI update function
- [ ] 8.4.2.7 Add Ctrl+D keyboard shortcut to toggle todo panel visibility

### 8.4.3 Todo Unit Tests
- [ ] **Task 8.4.3**

Create unit tests for todo tool and TUI integration.

- [ ] 8.4.3.1 Test todo creation with valid structure
- [ ] 8.4.3.2 Test status transitions (pending → in_progress → completed)
- [ ] 8.4.3.3 Test invalid status rejection
- [ ] 8.4.3.4 Test PubSub broadcast on update
- [ ] 8.4.3.5 Test TUI todo rendering
- [ ] 8.4.3.6 Test todo panel toggle

## 8.5 Multi-Agent Task Tool

The Task tool enables spawning specialized sub-agents for complex tasks, leveraging the Jido framework's agent architecture for isolated execution and result aggregation.

### 8.5.1 TaskAgent Implementation
- [ ] **Task 8.5.1**

Create a TaskAgent module for executing isolated sub-tasks with their own LLM context.

- [ ] 8.5.1.1 Create `JidoCode.Agents.TaskAgent` GenServer module
- [ ] 8.5.1.2 Implement `start_link/1` accepting task_spec with goal, context, and model
- [ ] 8.5.1.3 Initialize internal `Jido.AI.Agent` with task-specific system prompt
- [ ] 8.5.1.4 Implement `execute_task/2` that runs the agent and returns result
- [ ] 8.5.1.5 Add timeout handling with configurable limit (default 60s)
- [ ] 8.5.1.6 Broadcast progress updates via PubSub (`task.{task_id}` topic)
- [ ] 8.5.1.7 Implement graceful shutdown with result capture
- [ ] 8.5.1.8 Add telemetry events for task lifecycle (start, complete, fail, timeout)

### 8.5.2 Task Tool Handler
- [ ] **Task 8.5.2**

Implement the Task tool handler that spawns and manages sub-agents.

- [ ] 8.5.2.1 Create `JidoCode.Tools.Handlers.Task.SpawnTask` handler module
- [ ] 8.5.2.2 Generate unique task ID using `:crypto.strong_rand_bytes/1`
- [ ] 8.5.2.3 Spawn TaskAgent via `AgentSupervisor.start_agent/1`
- [ ] 8.5.2.4 Register task with unique name (`task_{id}` atom)
- [ ] 8.5.2.5 Wait for task completion with timeout
- [ ] 8.5.2.6 Clean up sub-agent after completion via `AgentSupervisor.stop_agent/1`
- [ ] 8.5.2.7 Return task result or timeout error
- [ ] 8.5.2.8 Handle sub-agent crash gracefully (return error, don't crash parent)

### 8.5.3 Task Tool Definition
- [ ] **Task 8.5.3**

Create the Task tool definition and register with the tool system.

- [ ] 8.5.3.1 Create `JidoCode.Tools.Definitions.Task` module
- [ ] 8.5.3.2 Define `spawn_task/0` tool with parameters:
  - `description` (string, required) - Short task description
  - `prompt` (string, required) - Detailed task instructions
  - `subagent_type` (string, optional) - Agent specialization hint
  - `model` (string, optional) - Override model for sub-agent
  - `timeout` (integer, optional) - Task timeout in ms
- [ ] 8.5.3.3 Add tool to Registry via `Definitions.Task.all/0`
- [ ] 8.5.3.4 Document sub-agent types and use cases in tool description

### 8.5.4 Task Tool Unit Tests
- [ ] **Task 8.5.4**

Create unit tests for TaskAgent and Task tool handler.

- [ ] 8.5.4.1 Test TaskAgent spawns and executes simple task
- [ ] 8.5.4.2 Test TaskAgent timeout handling
- [ ] 8.5.4.3 Test TaskAgent cleanup after completion
- [ ] 8.5.4.4 Test Task handler spawns agent via supervisor
- [ ] 8.5.4.5 Test Task handler returns result on success
- [ ] 8.5.4.6 Test Task handler handles sub-agent crash
- [ ] 8.5.4.7 Test telemetry events fired correctly
- [ ] 8.5.4.8 Test PubSub progress broadcasts

## 8.6 Tool Registration and Integration

Consolidate all new tools into the registration system and ensure they integrate properly with the existing tool infrastructure.

### 8.6.1 Tool Registration
- [ ] **Task 8.6.1**

Register all new tools with the Registry and ensure they appear in LLM function calling format.

- [ ] 8.6.1.1 Add `Definitions.FileSystem.edit_file/0` to `Definitions.FileSystem.all/0`
- [ ] 8.6.1.2 Create `Definitions.Livebook` module with `all/0` returning livebook tools
- [ ] 8.6.1.3 Create `Definitions.Web` module with `all/0` returning web_fetch and web_search
- [ ] 8.6.1.4 Create `Definitions.Todo` module with `all/0` returning todo_write
- [ ] 8.6.1.5 Create `Definitions.Task` module with `all/0` returning spawn_task
- [ ] 8.6.1.6 Update tool registration in agent initialization to include all new tools
- [ ] 8.6.1.7 Verify `Registry.to_llm_format/0` includes all tools correctly
- [ ] 8.6.1.8 Test `Registry.to_text_description/0` produces readable tool list

### 8.6.2 Settings Schema Updates
- [ ] **Task 8.6.2**

Update Settings schema to support new tool configurations.

- [ ] 8.6.2.1 Add `web_tools_enabled` boolean (default: true)
- [ ] 8.6.2.2 Add `allowed_domains` array (default: ["hexdocs.pm", "elixir-lang.org", "erlang.org", "github.com"])
- [ ] 8.6.2.3 Add `search_provider` string (default: "duckduckgo")
- [ ] 8.6.2.4 Add `search_api_key` string (optional, for SerpAPI)
- [ ] 8.6.2.5 Add `task_timeout_ms` integer (default: 60000)
- [ ] 8.6.2.6 Update Settings documentation with new fields
- [ ] 8.6.2.7 Add Settings validation for new fields

## 8.7 Integration Tests

End-to-end integration tests verifying tool execution through the full pipeline from LLM response parsing to result formatting.

### 8.7.1 Integration Test Suite
- [ ] **Task 8.7.1**

Create integration tests covering tool execution flows.

- [ ] 8.7.1.1 Test edit_file tool execution through Executor
- [ ] 8.7.1.2 Test livebook_edit tool with sample .livemd file
- [ ] 8.7.1.3 Test web_fetch tool with mocked HTTP (bypass real network)
- [ ] 8.7.1.4 Test web_search tool with mocked API response
- [ ] 8.7.1.5 Test todo_write tool updates TUI state
- [ ] 8.7.1.6 Test spawn_task tool creates and cleans up sub-agent
- [ ] 8.7.1.7 Test tool timeout handling across all new tools
- [ ] 8.7.1.8 Test security validation (path escaping, domain blocking)
- [ ] 8.7.1.9 Test PubSub broadcasts for tool calls and results
- [ ] 8.7.1.10 Verify minimum 80% code coverage for new modules

**Implementation Notes:**
- All integration tests tagged with `@moduletag :integration`
- Use `Bypass` library for HTTP mocking in web tool tests
- Use temporary directories for file operation tests
- Mock LLM responses to avoid real API calls

## 8.8 Documentation

Update documentation to cover new tools and their usage.

### 8.8.1 Tool Documentation
- [ ] **Task 8.8.1**

Document all new tools in the codebase and user-facing docs.

- [ ] 8.8.1.1 Add @moduledoc to all new handler modules
- [ ] 8.8.1.2 Add @doc to all public functions
- [ ] 8.8.1.3 Update CLAUDE.md with new tool descriptions
- [ ] 8.8.1.4 Add examples to tool description strings for LLM context
- [ ] 8.8.1.5 Document security considerations for web tools
- [ ] 8.8.1.6 Document Settings configuration options

---

## Summary

**New Tools Added:**
| Tool | Handler | Purpose |
|------|---------|---------|
| `edit_file` | `Handlers.FileSystem.EditFile` | Targeted string replacement in files |
| `livebook_edit` | `Handlers.Livebook.EditCell` | Edit Elixir Livebook notebook cells |
| `web_fetch` | `Handlers.Web.Fetch` | Fetch and parse web content |
| `web_search` | `Handlers.Web.Search` | Search the web via API |
| `todo_write` | `Handlers.Todo` | Manage task tracking list |
| `spawn_task` | `Handlers.Task.SpawnTask` | Spawn sub-agents for complex tasks |

**New Modules:**
- `JidoCode.Livebook.Parser` - Parse .livemd files
- `JidoCode.Agents.TaskAgent` - Sub-agent for task execution
- `JidoCode.Tools.Security.Web` - Web tool security
- `JidoCode.Tools.Definitions.{Livebook, Web, Todo, Task}` - Tool definitions
- `JidoCode.Tools.Handlers.{Livebook, Web, Todo, Task}` - Tool handlers

**Dependencies:**
- `Floki` - HTML parsing for web_fetch (confirmed)
- `Bypass` - HTTP mocking for tests (dev/test only)

**Implementation Order:**
1. Section 8.1 - Edit Tool (priority: builds on existing file tools)
2. Section 8.2 - Livebook Integration
3. Section 8.3 - Web Tools (default: DuckDuckGo, no API key required)
4. Section 8.4 - Todo Tracking
5. Section 8.5 - Task Tool (multi-agent)
6. Section 8.6 - Registration
7. Section 8.7 - Integration Tests
8. Section 8.8 - Documentation

**Critical Files to Modify:**
- `lib/jido_code/tools/definitions/file_system.ex` - Add edit_file
- `lib/jido_code/settings.ex` - Add web/task settings
- `lib/jido_code/tui.ex` - Add todo display
- `lib/jido_code/agent_supervisor.ex` - Verify TaskAgent support
