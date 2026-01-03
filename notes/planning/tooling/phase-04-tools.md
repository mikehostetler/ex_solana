# Phase 4: Web & Agent Tools

This phase implements web access capabilities and agent/task delegation tools. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All web and agent tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "web_fetch", "arguments": {"url": "..."}}   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.web_fetch(url, opts, session_id: id)         │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.web_fetch(url, opts)"        │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_web_fetch/3 invoked from Lua                    │
│  (Elixir function registered as jido.web_fetch)             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Security.Web.validate_url/1                                │
│  - Domain allowlist enforcement                             │
│  - Scheme validation (no file://, javascript://)            │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Bridge Function | Purpose |
|------|-----------------|---------|
| web_fetch | `jido.web_fetch(url, opts)` | Fetch and parse web content |
| web_search | `jido.web_search(query, opts)` | Search the web |
| spawn_subagent | `jido.spawn_agent(prompt, opts)` | Delegate tasks to sub-agents |
| get_task_output | `jido.task_output(task_id, opts)` | Retrieve background task results |
| todo_write | `jido.todo_write(todos)` | Manage task tracking list |
| todo_read | `jido.todo_read(filter)` | Read current task list |
| ask_user | `jido.ask_user(questions)` | Interactive user questions |

---

## 4.1 Web Fetch Tool

Implement the web_fetch tool for fetching and parsing web content through the Lua sandbox.

### 4.1.1 Tool Definition

Create the web_fetch tool definition with URL validation.

- [ ] 4.1.1.1 Create `lib/jido_code/tools/definitions/web_fetch.ex`
- [ ] 4.1.1.2 Define schema:
  ```elixir
  %{
    name: "web_fetch",
    description: "Fetch web page and convert to markdown. Restricted to documentation domains.",
    parameters: [
      %{name: "url", type: :string, required: true, description: "URL to fetch"},
      %{name: "prompt", type: :string, required: false, description: "Prompt to process content with"},
      %{name: "extract_selector", type: :string, required: false, description: "CSS selector to extract"}
    ]
  }
  ```
- [ ] 4.1.1.3 Document domain allowlist in description
- [ ] 4.1.1.4 Register tool in definitions module

### 4.1.2 Bridge Function Implementation

Implement the Bridge function for web content fetching.

- [ ] 4.1.2.1 Add `lua_web_fetch/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_web_fetch(args, state, _project_root) do
    case args do
      [url] -> do_web_fetch(url, %{}, state)
      [url, opts] -> do_web_fetch(url, decode_opts(opts), state)
      _ -> {[nil, "web_fetch requires url argument"], state}
    end
  end
  ```
- [ ] 4.1.2.2 Use `Security.Web.validate_url/1` to check against domain allowlist:
  - hexdocs.pm
  - elixir-lang.org
  - erlang.org
  - github.com
  - hex.pm
- [ ] 4.1.2.3 Block dangerous URL schemes (file://, javascript://, data://)
- [ ] 4.1.2.4 Fetch URL with HTTP client (Req)
- [ ] 4.1.2.5 Handle redirects (follow up to 5 redirects, validate each domain)
- [ ] 4.1.2.6 Parse HTML with Floki
- [ ] 4.1.2.7 Convert HTML to markdown (preserve code blocks, links)
- [ ] 4.1.2.8 Apply CSS selector extraction if specified
- [ ] 4.1.2.9 Implement 15-minute cache (ETS-based)
- [ ] 4.1.2.10 Truncate large content with indicator
- [ ] 4.1.2.11 Return `{[%{content: markdown, url: final_url}], state}` or `{[nil, error], state}`
- [ ] 4.1.2.12 Register in `Bridge.register/2`

### 4.1.3 Manager API

- [ ] 4.1.3.1 Add `web_fetch/2` to `Tools.Manager`
- [ ] 4.1.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.1.3.3 Call bridge function through Lua: `jido.web_fetch(url, opts)`

### 4.1.4 Unit Tests for Web Fetch

- [ ] Test web_fetch through sandbox with allowed domain
- [ ] Test web_fetch blocks disallowed domain
- [ ] Test web_fetch blocks file:// URLs
- [ ] Test web_fetch follows redirects (validates each domain)
- [ ] Test web_fetch converts HTML to markdown
- [ ] Test web_fetch applies CSS selector
- [ ] Test web_fetch caches responses
- [ ] Test web_fetch handles 404 errors
- [ ] Test web_fetch handles timeouts

---

## 4.2 Web Search Tool

Implement the web_search tool for searching the web through the Lua sandbox.

### 4.2.1 Tool Definition

Create the web_search tool definition with query parameters.

- [ ] 4.2.1.1 Create `lib/jido_code/tools/definitions/web_search.ex`
- [ ] 4.2.1.2 Define schema:
  ```elixir
  %{
    name: "web_search",
    description: "Search the web. Returns titles, URLs, and snippets.",
    parameters: [
      %{name: "query", type: :string, required: true, description: "Search query"},
      %{name: "allowed_domains", type: :array, required: false, description: "Limit to specific domains"},
      %{name: "blocked_domains", type: :array, required: false, description: "Exclude specific domains"},
      %{name: "limit", type: :integer, required: false, description: "Max results (default: 10)"}
    ]
  }
  ```
- [ ] 4.2.1.3 Register tool in definitions module

### 4.2.2 Bridge Function Implementation

Implement the Bridge function for web search.

- [ ] 4.2.2.1 Add `lua_web_search/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_web_search(args, state, _project_root) do
    case args do
      [query] -> do_web_search(query, %{}, state)
      [query, opts] -> do_web_search(query, decode_opts(opts), state)
      _ -> {[nil, "web_search requires query argument"], state}
    end
  end
  ```
- [ ] 4.2.2.2 Build search query with domain filters
- [ ] 4.2.2.3 Execute search via DuckDuckGo or configured provider
- [ ] 4.2.2.4 Parse search results
- [ ] 4.2.2.5 Filter by allowed/blocked domains
- [ ] 4.2.2.6 Apply result limit
- [ ] 4.2.2.7 Format results with title, URL, snippet
- [ ] 4.2.2.8 Return `{[[%{title: t, url: u, snippet: s}, ...]], state}` or `{[nil, error], state}`
- [ ] 4.2.2.9 Register in `Bridge.register/2`

### 4.2.3 Manager API

- [ ] 4.2.3.1 Add `web_search/2` to `Tools.Manager`
- [ ] 4.2.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.2.3.3 Call bridge function through Lua: `jido.web_search(query, opts)`

### 4.2.4 Unit Tests for Web Search

- [ ] Test web_search through sandbox returns results
- [ ] Test web_search filters by allowed_domains
- [ ] Test web_search filters by blocked_domains
- [ ] Test web_search respects limit
- [ ] Test web_search handles no results
- [ ] Test web_search handles search errors

---

## 4.3 Spawn Subagent Tool

Implement the spawn_subagent tool for delegating complex tasks through the Lua sandbox.

### 4.3.1 Tool Definition

Create the spawn_subagent tool definition for task delegation.

- [ ] 4.3.1.1 Create `lib/jido_code/tools/definitions/spawn_subagent.ex`
- [ ] 4.3.1.2 Define schema:
  ```elixir
  %{
    name: "spawn_subagent",
    description: "Spawn a sub-agent for complex tasks. Returns task_id for background tasks.",
    parameters: [
      %{name: "description", type: :string, required: true, description: "3-5 word task description"},
      %{name: "prompt", type: :string, required: true, description: "Detailed task prompt"},
      %{name: "subagent_type", type: :string, required: true,
        enum: ["general-purpose", "explore", "plan"], description: "Agent type"},
      %{name: "run_in_background", type: :boolean, required: false, description: "Run asynchronously"},
      %{name: "model", type: :string, required: false, description: "Model override"}
    ]
  }
  ```
- [ ] 4.3.1.3 Register tool in definitions module

### 4.3.2 Bridge Function Implementation

Implement the Bridge function for sub-agent spawning.

- [ ] 4.3.2.1 Add `lua_spawn_agent/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_spawn_agent(args, state, project_root) do
    case args do
      [prompt] -> do_spawn_agent(prompt, %{}, state, project_root)
      [prompt, opts] -> do_spawn_agent(prompt, decode_opts(opts), state, project_root)
      _ -> {[nil, "spawn_agent requires prompt argument"], state}
    end
  end
  ```
- [ ] 4.3.2.2 Validate subagent_type against available types
- [ ] 4.3.2.3 Create agent configuration based on type
- [ ] 4.3.2.4 Spawn TaskAgent with prompt and session context
- [ ] 4.3.2.5 If run_in_background, generate task_id and store in session state
- [ ] 4.3.2.6 If synchronous, wait for completion
- [ ] 4.3.2.7 Capture agent output and tool calls
- [ ] 4.3.2.8 Return `{[%{task_id: id, result: result}], state}` or `{[nil, error], state}`
- [ ] 4.3.2.9 Register in `Bridge.register/2`

### 4.3.3 Manager API

- [ ] 4.3.3.1 Add `spawn_agent/2` to `Tools.Manager`
- [ ] 4.3.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.3.3.3 Call bridge function through Lua: `jido.spawn_agent(prompt, opts)`

### 4.3.4 Unit Tests for Spawn Subagent

- [ ] Test spawn_subagent through sandbox creates agent
- [ ] Test spawn_subagent with different types
- [ ] Test spawn_subagent background mode returns task_id
- [ ] Test spawn_subagent synchronous mode returns result
- [ ] Test spawn_subagent handles agent failure

---

## 4.4 Get Task Output Tool

Implement the get_task_output tool for retrieving background agent results through the Lua sandbox.

### 4.4.1 Tool Definition

Create the get_task_output tool definition.

- [ ] 4.4.1.1 Create `lib/jido_code/tools/definitions/get_task_output.ex`
- [ ] 4.4.1.2 Define schema:
  ```elixir
  %{
    name: "get_task_output",
    description: "Get output from a background sub-agent task.",
    parameters: [
      %{name: "task_id", type: :string, required: true, description: "Task ID from spawn_subagent"},
      %{name: "block", type: :boolean, required: false, description: "Wait for completion (default: true)"},
      %{name: "timeout", type: :integer, required: false, description: "Max wait time in ms"}
    ]
  }
  ```
- [ ] 4.4.1.3 Register tool in definitions module

### 4.4.2 Bridge Function Implementation

Implement the Bridge function for task output retrieval.

- [ ] 4.4.2.1 Add `lua_task_output/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_task_output(args, state, _project_root) do
    case args do
      [task_id] -> do_task_output(task_id, %{block: true}, state)
      [task_id, opts] -> do_task_output(task_id, decode_opts(opts), state)
      _ -> {[nil, "task_output requires task_id argument"], state}
    end
  end
  ```
- [ ] 4.4.2.2 Look up task by task_id in session state
- [ ] 4.4.2.3 If block=true, wait for completion
- [ ] 4.4.2.4 Return task status and result
- [ ] 4.4.2.5 Return `{[%{status: status, result: result}], state}` or `{[nil, error], state}`
- [ ] 4.4.2.6 Register in `Bridge.register/2`

### 4.4.3 Manager API

- [ ] 4.4.3.1 Add `task_output/2` to `Tools.Manager`
- [ ] 4.4.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.4.3.3 Call bridge function through Lua: `jido.task_output(task_id, opts)`

### 4.4.4 Unit Tests for Get Task Output

- [ ] Test get_task_output through sandbox retrieves completed task
- [ ] Test get_task_output waits for running task
- [ ] Test get_task_output handles timeout
- [ ] Test get_task_output handles unknown task_id

---

## 4.5 Todo Write Tool

Implement the todo_write tool for managing task tracking lists through the Lua sandbox.

### 4.5.1 Tool Definition

Create the todo_write tool definition for task management.

- [ ] 4.5.1.1 Create `lib/jido_code/tools/definitions/todo_write.ex`
- [ ] 4.5.1.2 Define schema:
  ```elixir
  %{
    name: "todo_write",
    description: "Update the task tracking list.",
    parameters: [
      %{name: "todos", type: :array, required: true, items: %{
        content: %{type: :string, required: true, description: "Task description"},
        status: %{type: :string, required: true, enum: ["pending", "in_progress", "completed"]},
        active_form: %{type: :string, required: true, description: "Present continuous form"}
      }}
    ]
  }
  ```
- [ ] 4.5.1.3 Register tool in definitions module

### 4.5.2 Bridge Function Implementation

Implement the Bridge function for todo list management.

- [ ] 4.5.2.1 Add `lua_todo_write/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_todo_write(args, state, _project_root) do
    case args do
      [todos] -> do_todo_write(todos, state)
      _ -> {[nil, "todo_write requires todos array"], state}
    end
  end
  ```
- [ ] 4.5.2.2 Validate todo structure
- [ ] 4.5.2.3 Update session state with new todo list
- [ ] 4.5.2.4 Publish todo update via PubSub
- [ ] 4.5.2.5 Return `{[todos], updated_state}` or `{[nil, error], state}`
- [ ] 4.5.2.6 Register in `Bridge.register/2`

### 4.5.3 Manager API

- [ ] 4.5.3.1 Add `todo_write/2` to `Tools.Manager`
- [ ] 4.5.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.5.3.3 Call bridge function through Lua: `jido.todo_write(todos)`

### 4.5.4 Unit Tests for Todo Write

- [ ] Test todo_write through sandbox creates new list
- [ ] Test todo_write updates existing list
- [ ] Test todo_write validates status enum
- [ ] Test todo_write publishes update

---

## 4.6 Todo Read Tool

Implement the todo_read tool for reading current task list through the Lua sandbox.

### 4.6.1 Tool Definition

Create the todo_read tool definition.

- [ ] 4.6.1.1 Create `lib/jido_code/tools/definitions/todo_read.ex`
- [ ] 4.6.1.2 Define schema:
  ```elixir
  %{
    name: "todo_read",
    description: "Read the current task tracking list.",
    parameters: [
      %{name: "filter", type: :string, required: false,
        enum: ["all", "pending", "in_progress", "completed"]}
    ]
  }
  ```
- [ ] 4.6.1.3 Register tool in definitions module

### 4.6.2 Bridge Function Implementation

Implement the Bridge function for reading todos.

- [ ] 4.6.2.1 Add `lua_todo_read/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_todo_read(args, state, _project_root) do
    case args do
      [] -> do_todo_read(%{filter: "all"}, state)
      [opts] -> do_todo_read(decode_opts(opts), state)
      _ -> {[nil, "todo_read: invalid arguments"], state}
    end
  end
  ```
- [ ] 4.6.2.2 Retrieve todos from session state
- [ ] 4.6.2.3 Apply filter if specified
- [ ] 4.6.2.4 Return `{[todos], state}` or `{[nil, error], state}`
- [ ] 4.6.2.5 Register in `Bridge.register/2`

### 4.6.3 Manager API

- [ ] 4.6.3.1 Add `todo_read/2` to `Tools.Manager`
- [ ] 4.6.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.6.3.3 Call bridge function through Lua: `jido.todo_read(opts)`

### 4.6.4 Unit Tests for Todo Read

- [ ] Test todo_read through sandbox returns all todos
- [ ] Test todo_read filters by status
- [ ] Test todo_read handles empty list

---

## 4.7 Ask User Tool

Implement the ask_user tool for interactive user questions through the Lua sandbox.

### 4.7.1 Tool Definition

Create the ask_user tool definition for user interaction.

- [ ] 4.7.1.1 Create `lib/jido_code/tools/definitions/ask_user.ex`
- [ ] 4.7.1.2 Define schema:
  ```elixir
  %{
    name: "ask_user",
    description: "Ask the user a question with options.",
    parameters: [
      %{name: "questions", type: :array, required: true, items: %{
        question: %{type: :string, required: true, description: "Question text"},
        header: %{type: :string, required: true, description: "Short label (max 12 chars)"},
        options: %{type: :array, required: true, items: %{
          label: %{type: :string, required: true},
          description: %{type: :string, required: false}
        }},
        multi_select: %{type: :boolean, required: false}
      }}
    ]
  }
  ```
- [ ] 4.7.1.3 Register tool in definitions module

### 4.7.2 Bridge Function Implementation

Implement the Bridge function for user questions.

- [ ] 4.7.2.1 Add `lua_ask_user/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_ask_user(args, state, _project_root) do
    case args do
      [questions] -> do_ask_user(questions, state)
      _ -> {[nil, "ask_user requires questions array"], state}
    end
  end
  ```
- [ ] 4.7.2.2 Validate question structure
- [ ] 4.7.2.3 Format questions for TUI display
- [ ] 4.7.2.4 Publish question to TUI via PubSub
- [ ] 4.7.2.5 Wait for user response (blocking with timeout)
- [ ] 4.7.2.6 Return `{[%{answers: answers}], state}` or `{[nil, :cancelled], state}`
- [ ] 4.7.2.7 Register in `Bridge.register/2`

### 4.7.3 Manager API

- [ ] 4.7.3.1 Add `ask_user/2` to `Tools.Manager`
- [ ] 4.7.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 4.7.3.3 Call bridge function through Lua: `jido.ask_user(questions)`

### 4.7.4 Unit Tests for Ask User

- [ ] Test ask_user through sandbox formats questions correctly
- [ ] Test ask_user with single select
- [ ] Test ask_user with multi select
- [ ] Test ask_user handles user cancellation
- [ ] Test ask_user timeout handling

---

## 4.8 Phase 4 Integration Tests

Integration tests for web and agent tools working through the Lua sandbox.

### 4.8.1 Sandbox Integration

Verify tools execute through the sandbox correctly.

- [ ] 4.8.1.1 Create `test/jido_code/integration/tools_phase4_test.exs`
- [ ] 4.8.1.2 Test: All tools execute through `Tools.Manager` → Lua → Bridge chain
- [ ] 4.8.1.3 Test: Session-scoped managers are isolated

### 4.8.2 Web Integration

Test web tools in realistic scenarios through sandbox.

- [ ] 4.8.2.1 Test: web_fetch retrieves hexdocs page
- [ ] 4.8.2.2 Test: web_fetch caches repeated requests
- [ ] 4.8.2.3 Test: web_search finds relevant results

### 4.8.3 Agent Integration

Test agent tools in realistic scenarios through sandbox.

- [ ] 4.8.3.1 Test: spawn_subagent -> get_task_output retrieves result
- [ ] 4.8.3.2 Test: spawn_subagent background mode
- [ ] 4.8.3.3 Test: Multiple concurrent subagents

### 4.8.4 Todo Integration

Test todo tracking across session through sandbox.

- [ ] 4.8.4.1 Test: todo_write -> todo_read cycle
- [ ] 4.8.4.2 Test: todo updates published to TUI
- [ ] 4.8.4.3 Test: todos persisted with session state

### 4.8.5 User Interaction Integration

Test user interaction tools through sandbox.

- [ ] 4.8.5.1 Test: ask_user displays in TUI
- [ ] 4.8.5.2 Test: ask_user receives user response

---

## Phase 4 Success Criteria

1. **web_fetch**: HTML-to-markdown via `jido.web_fetch` bridge
2. **web_search**: Query search via `jido.web_search` bridge
3. **spawn_subagent**: Agent delegation via `jido.spawn_agent` bridge
4. **get_task_output**: Task retrieval via `jido.task_output` bridge
5. **todo_write/read**: Task tracking via `jido.todo_write`/`jido.todo_read` bridges
6. **ask_user**: User interaction via `jido.ask_user` bridge
7. **All tools execute through Lua sandbox** (defense-in-depth)
8. **Test Coverage**: Minimum 80% for Phase 4 tools

---

## Phase 4 Critical Files

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add web, agent, todo, and user bridge functions
- `lib/jido_code/tools/manager.ex` - Expose web, agent, todo, and user APIs
- `lib/jido_code/tools/security/web.ex` - URL validation for web tools

**New Files:**
- `lib/jido_code/tools/definitions/web_fetch.ex`
- `lib/jido_code/tools/definitions/web_search.ex`
- `lib/jido_code/tools/definitions/spawn_subagent.ex`
- `lib/jido_code/tools/definitions/get_task_output.ex`
- `lib/jido_code/tools/definitions/todo_write.ex`
- `lib/jido_code/tools/definitions/todo_read.ex`
- `lib/jido_code/tools/definitions/ask_user.ex`
- `lib/jido_code/tools/web/cache.ex`
- `test/jido_code/tools/bridge_web_agent_test.exs`
- `test/jido_code/integration/tools_phase4_test.exs`
