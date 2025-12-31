# Jido–Claude Integration (Claude Code + A2A)

**Date:** 2025-12-31  
**Status:** Draft architecture & implementation proposal  
**Scope:** Integrating Claude Code / Claude Agent SDK into Jido 2.0 as an external capability, and aligning with emerging MCP + A2A agent coordination standards.

---

## 1. TL;DR / Executive Summary

- Treat Claude Code (and the Claude Agent SDK) as a **tool-hosted, external agent** that Jido orchestrates via **directives** and **sensors**; keep Jido agents pure (`cmd/2`).
- Implement a **minimal, CLI-based integration first** using Claude Code headless mode (`claude -p`), with:
  - A new `Directive.ClaudeCall` directive type
  - A `DirectiveExec` implementation that spawns/streams a Claude Code subprocess
  - Streaming of chunks back into Jido as `Signal` events, routed to agents or observers.
- Design the integration so it can later plug into **MCP (Model Context Protocol)** and **A2A (Agent-to-Agent)**:
  - Jido as **orchestrator agent** calling Claude via A2A
  - Optional Jido **tool servers** via MCP so Claude agents can call back into Jido.

**Effort:**  
- Phase 1 (CLI-based, no MCP/A2A): **M–L (1–2 days)**  
- Phase 2 (A2A gateway & MCP tooling): **L–XL (3–7+ days)**, gated on maturity of A2A tooling and product needs.

---

## 2. Background: Claude Code, Claude Agent SDK, MCP, A2A

### 2.1 Claude Code & Claude Agent SDK

Key points from Anthropic's docs and engineering posts:

- **Claude Code** is a **CLI-based agentic coding assistant**:
  - Can search files, edit code, run commands, interact with git/GitHub, etc.
  - Has a **"headless mode"** (`claude -p`) designed for automation / CI and programmatic integration.
- The **Claude Agent SDK** generalizes this harness:
  - Agent loop: **gather context → take action → verify work → repeat**.
  - Supports:
    - Tooling / bash integration
    - File system as context store
    - Subagents, compaction (conversation summarization)
    - Integration with **MCP** for external tools.
- Internally, Anthropic uses a **multi-agent orchestrator-worker pattern**:
  - A lead agent plans and coordinates.
  - Worker/subagents perform specialized tasks (often in parallel).
  - Artifacts (code, reports, etc.) are often written to a shared filesystem or tools, not just returned via chat.

These patterns map well onto **Jido's orchestrator–worker agent model** and its immutable `cmd/2` agents with externalized directives.

### 2.2 MCP (Model Context Protocol)

- MCP is an **open standard** for exposing tools/data as servers and connecting them to AI agents as clients.
- Two main roles:
  - **MCP server:** exposes tools/data (e.g., "run SQL", "get Slack messages").
  - **MCP client:** lives inside an AI assistant / agent harness and discovers/calls those tools.
- Claude Desktop and Claude Agent SDK can act as **MCP clients**; there is an ecosystem of **pre-built MCP servers** (GitHub, Postgres, etc.).

For Jido:

- Short term: Jido can ignore MCP and just treat Claude Code as a black-box worker.
- Medium/long term: Jido can implement **MCP servers** (e.g., "Jido Agent Tooling") so Claude agents can call back into Jido-managed capabilities.

### 2.3 A2A (Agent-to-Agent Protocol)

- A2A (as described by Google + Anthropic collaborations) is an **open protocol for agent-to-agent communication**:
  - Enables agents, potentially from different vendors/frameworks, to **discover each other, exchange messages, delegate tasks, and share context**.
  - Focuses on **interoperability** and **coordination** across heterogeneous agent systems.
- High-level concepts (from public material and summaries):
  - **Agent descriptors:** identity, capabilities, supported tools.
  - **Tasks / messages:** structured task requests and results, often JSON-based, over HTTP or streaming transports.
  - **Coordination patterns:** orchestrator–worker, peer-to-peer collaboration, task delegation across agents.

For Jido:

- Jido should be designed so a **Jido agent or instance can sit behind an A2A endpoint**:
  - As a **client**, it can send tasks to a Claude-based orchestrator/worker.
  - As a **server**, it can expose Jido agents as addressable A2A agents to other ecosystems.
- Initial integration can be **A2A-friendly** (clean message envelopes and clear task/response modeling), even before adopting a concrete A2A SDK.

---

## 3. Jido–Claude Architecture Overview

### 3.1 Roles

- **Jido Instance (`MyApp.Jido`)**
  - OTP supervisor per Jido 2.0 API plan.
  - Hosts:
    - `MyApp.Jido.AgentSupervisor` (agent processes)
    - `MyApp.Jido.TaskSupervisor` (async external work)
    - `MyApp.Jido.Registry` (agent lookup)
    - `MyApp.Jido.Scheduler` (cron)
- **Jido Agents (immutable, cmd/2)**
  - Own high-level workflows (e.g., "Refactor module X", "Migrate project Y").
  - Emit **directives** describing external actions, including Claude-related work.
- **Jido AgentServer**
  - Executes directives, manages **queue + drain loop**, handles async tasks.
- **Claude Worker (external)**
  - A **Claude Code headless CLI process** or a small HTTP service using the **Claude Agent SDK**.
  - Receives structured tasks from Jido, uses Claude to perform code / analysis work.
  - Streams back incremental results.
- **Jido Sensors / Signals**
  - Carry streamed updates (`"claude.output_chunk"`, `"claude.task_updated"`, etc.) as `Jido.Signal` events back into Jido agents or observers.

### 3.2 High-Level Data Flow

#### Simple "one-shot" Claude call

1. A Jido agent (`CodeOrchestratorAgent`) decides it needs Claude to perform a coding action.
2. `cmd/2` returns:
   - Updated agent state (e.g., status: `:in_progress`).
   - A `%Directive.ClaudeCall{...}` describing:
     - Prompt / instructions
     - Context files/paths (if needed)
     - Desired mode (`:analysis`, `:edit`, etc.)
     - Where to stream results (agent id / bus / pubsub).
3. `AgentServer` executes this directive by:
   - Spawning a task/port under `MyApp.Jido.TaskSupervisor`.
   - Launching `claude -p` (CLI) or hitting an HTTP endpoint for the Claude Agent SDK.
   - Streaming output lines/chunks.
4. As output arrives, the worker:
   - Wraps chunks in `Jido.Signal` structs, e.g. `"claude.output_chunk"`, `"claude.completed"`, `"claude.error"`.
   - Injects them back via `AgentServer.cast/2` or via a `Sensor.Dispatch` helper.
5. The orchestrator agent's `handle_signal/2` consumes these signals:
   - Updates state (e.g., accumulating a log, status transitions).
   - May emit further directives (e.g., write artifacts to disk, run tests, spawn sub-agents).

#### Long-lived session / multi-step work

Same as above, but:

- The **Jido agent state** tracks a `claude_session_id` and accumulated summary.
- Each directive includes `session_id` to reuse Claude context (for CLI, this could be simulated via a persistent background process or explicit transcript passed each time).
- Jido may spawn **multiple worker agents**, each wrapping its own Claude worker, and coordinate using `Jido.MultiAgent.await/2`.

---

## 4. Mapping to Jido Concepts

### 4.1 Agents

- Define a family of agents for Claude orchestration:

  ```elixir
  defmodule MyApp.Agents.ClaudeOrchestrator do
    use Jido.Agent,
      name: "claude_orchestrator",
      description: "Orchestrates Claude Code sessions for coding tasks",
      schema: [
        status: [type: :atom, default: :idle],
        session_id: [type: :string, default: nil],
        task_id: [type: :string, default: nil],
        progress: [type: :map, default: %{}],
        log: [type: :list, default: []]
      ]
  end
  ```

- Business logic lives in **Actions** (e.g., `StartClaudeTask`, `HandleClaudeUpdate`), following existing Jido action patterns.

### 4.2 Directives

Add a new directive type under `Jido.Agent.Directive` (or equivalent):

```elixir
defmodule Jido.Agent.Directive.ClaudeCall do
  @enforce_keys [:mode, :prompt, :target]
  defstruct [
    :mode,            # :analysis | :edit | :refactor | ...
    :prompt,          # main instruction for Claude
    :session_id,      # optional, for multi-step work
    :context_paths,   # list of file paths / globs for context
    :workspace_root,  # local path to run Claude in
    :target,          # where to stream results (agent id, via tuple, bus, pubsub)
    :metadata         # free-form (e.g., task_id, correlation_id)
  ]
end
```

And helper constructors in `Jido.Agent.Directive`:

```elixir
defmodule Jido.Agent.Directive do
  # ...

  @spec claude_call(keyword()) :: Jido.Agent.Directive.ClaudeCall.t()
  def claude_call(opts) do
    struct!(Jido.Agent.Directive.ClaudeCall, opts)
  end
end
```

These remain **pure data**; they do not touch Claude directly.

### 4.3 Signals

Introduce a small, coherent set of signal types for Claude integration:

- `"claude.started"` – worker process started.
- `"claude.output_chunk"` – textual or structured partial output.
- `"claude.artifact"` – reference to created file/report.
- `"claude.completed"` – task finished successfully.
- `"claude.failed"` – failure, with error info.

All are standard `Jido.Signal` structs, e.g.:

```elixir
%Jido.Signal{
  type: "claude.output_chunk",
  data: %{
    task_id: "t-123",
    chunk: "...",
    sequence: 17
  },
  source: "/claude/worker/#{worker_id}",
  extensions: %{session_id: "...", level: :info}
}
```

Agents stay pure by **reacting** to these signals in `handle_signal/2`.

### 4.4 Sensors (Optional helper)

If streaming via an external channel (e.g., HTTP callbacks, PubSub), a `Jido.Sensor` can translate those into signals. For a direct CLI `Port`, this may not be strictly necessary; the directive executor can inject signals directly.

---

## 5. Phase 1: Minimal CLI-Based Integration (Recommended Path)

**Goal:** A simple, production-viable way for Jido agents to **call Claude Code**, stream results, and coordinate work, without waiting on A2A/MCP libraries.

### 5.1 Components

1. **Directive type:** `Jido.Agent.Directive.ClaudeCall` (see above).
2. **DirectiveExec module:** `Jido.AgentServer.DirectiveExec.ClaudeCall`
3. **Worker harness:** `Jido.Claude.Worker` (thin Elixir wrapper around CLI or HTTP).
4. **Signals:** standard `Jido.Signal` patterns for streaming.
5. **Orchestrator agent & actions:** e.g., `MyApp.Agents.ClaudeOrchestrator`, `Actions.StartClaudeTask`, `Actions.HandleClaudeUpdate`.

### 5.2 Directive Execution Flow

Implement a `DirectiveExec` module roughly like:

```elixir
defmodule Jido.AgentServer.DirectiveExec.ClaudeCall do
  @behaviour Jido.AgentServer.DirectiveExec

  alias Jido.Agent.Directive.ClaudeCall
  alias Jido.Claude.Worker
  alias Jido.Signal

  @impl true
  def execute(%ClaudeCall{} = directive, state) do
    # state contains agent, jido instance name, etc.
    %{agent: agent, jido: jido} = state

    # Spawn async worker under instance TaskSupervisor
    task =
      Task.Supervisor.async_nolink(Jido.task_supervisor(jido), fn ->
        Worker.run_and_stream(directive, agent.id)
      end)

    # Track task in state if needed
    new_state =
      put_in(state.async_tasks[task.ref], %{
        directive: directive,
        agent_id: agent.id
      })

    {:async, task, new_state}
  end
end
```

**Contract:**

- Returns `{:async, task, new_state}` so `AgentServer`'s drain loop knows this is an async directive, consistent with existing patterns in `DirectiveExec`.

### 5.3 Worker Harness (`Jido.Claude.Worker`)

This module should **hide all Claude-specific details** behind a simple API:

```elixir
defmodule Jido.Claude.Worker do
  @moduledoc """
  Thin wrapper around Claude Code headless CLI or HTTP API.

  Responsible for:
  - Launching Claude Code processes
  - Streaming output
  - Translating output into Jido.Signal structs
  - Routing them back to Jido via AgentServer.cast/2 or Sensor.Dispatch
  """

  alias Jido.Signal
  alias Jido.AgentServer

  @type target :: AgentServer.server() | {:via, module(), term()} | {:pubsub, keyword()} | {:bus, keyword()}

  @spec run_and_stream(Jido.Agent.Directive.ClaudeCall.t(), String.t()) :: :ok | {:error, term()}
  def run_and_stream(directive, default_target_agent_id) do
    target = directive.target || default_target_agent_id

    emit(started_signal(directive), target)

    # Strategy A: CLI-based
    cmd = build_cli_command(directive)
    opts = [cd: directive.workspace_root || File.cwd!()]

    # Use Port or System.cmd streaming; pseudo-code:
    Port.open({:spawn_executable, "/usr/local/bin/claude"}, [
      :binary,
      args: cmd,
      cd: opts[:cd],
      {:line, 256}
    ])
    |> stream_port(directive, target)

    # Eventually emit completion or error
  end

  defp stream_port(port, directive, target) do
    receive do
      {^port, {:data, line}} ->
        case parse_line(line) do
          {:ok, chunk} ->
            emit(output_chunk_signal(directive, chunk), target)
          {:error, err} ->
            emit(error_signal(directive, err), target)
        end

        stream_port(port, directive, target)

      {^port, :eof} ->
        emit(completed_signal(directive), target)
        :ok
    after
      60_000 ->
        emit(error_signal(directive, :timeout), target)
        :ok
    end
  end

  defp emit(%Signal{} = signal, target) do
    # Keep this simple and reuse existing AgentServer.cast/2 or Signal.Dispatch
    AgentServer.cast(target, signal)
  end
end
```

Notes:

- **Do not over-specify** the CLI JSON format here; treat `parse_line/1` as an implementation detail that can evolve with Claude Code updates.
- This wrapper is also where we could **switch from CLI to HTTP** later without changing directives or agents.

### 5.4 Orchestrator Agent Pattern

Use an orchestrator agent to:

- Accept a high-level Jido signal (e.g., `"project.refactor"`).
- Plan sub-tasks and context selection.
- Emit one or more `Directive.ClaudeCall` directives.
- React to `"claude.*"` signals to update progress and decide next steps.

Pseudo-code for a simple action:

```elixir
defmodule MyApp.Actions.StartClaudeRefactor do
  use Jido.Action, name: "start_claude_refactor"

  alias Jido.Agent.Directive

  @impl true
  def run(params, %{agent: agent}) do
    task_id = params.task_id || Jido.generate_id()

    directive =
      Directive.claude_call(
        mode: :refactor,
        prompt: params.prompt,
        context_paths: params.context_paths,
        workspace_root: params.workspace_root,
        target: {:agent, agent.id},
        metadata: %{task_id: task_id}
      )

    new_state = %{
      agent.state
      | status: :in_progress,
        task_id: task_id
    }

    {:ok, new_state, [directive]}
  end
end
```

The agent's `handle_signal/2` would implement logic like:

- On `"claude.output_chunk"`: append to `log`, maybe stream to client.
- On `"claude.completed"`: set `status: :completed`.

### 5.5 Tests & Guardrails

- Unit tests for:
  - Directive construction (`Directive.claude_call/1`).
  - `DirectiveExec.ClaudeCall.execute/2` result shapes.
  - Worker harness behavior with **simulated port output** (no real Claude dependency).
- Integration tests:
  - Mock `Jido.Claude.Worker` in `DirectiveExec` to avoid hitting CLI in CI.
  - Verify orchestrator agent state transitions and signal handling.

**Effort:** M–L (1–2 days), mostly wiring + tests.

---

## 6. Phase 2: A2A & MCP-Friendly Design

Once the minimal integration is stable, incrementally add **A2A** and **MCP** capabilities.

### 6.1 Design Goals

- **Do not change agent APIs or directives**:
  - `Directive.ClaudeCall` remains the same.
  - Orchestrator agents are unaffected.
- Swap **implementation details**:
  - Instead of local CLI, the worker uses A2A or HTTP calls to a Claude Agent SDK-based service.
  - Allow Claude-based agents to call back into Jido via MCP.

### 6.2 Jido as A2A Client (Calling Claude Agents)

Introduce a **Jido A2A client** module:

```elixir
defmodule Jido.A2A.Client do
  @moduledoc """
  Minimal client for sending tasks to an A2A-compliant Claude agent service.

  Pluggable transport (HTTP/WebSocket) and message format.
  """

  @type task_request :: map()
  @type task_update :: map()
  @type task_result :: map()

  @spec start_task(task_request(), keyword()) :: {:ok, task_id :: String.t()} | {:error, term()}
  def start_task(request, opts \\ []) do
    # POST /tasks or similar; implementation depends on A2A spec & SDK
  end

  @spec stream_updates(task_id :: String.t(), (task_update() -> any())) :: :ok | {:error, term()}
  def stream_updates(task_id, fun) do
    # SSE / WebSocket / long-poll; call fun(update) for each chunk
  end
end
```

Then update `Jido.Claude.Worker` to have **two backends**:

- `backend: :cli` (default)
- `backend: :a2a` (calls `Jido.A2A.Client`).

The same signals are emitted; only the transport changes.

### 6.3 Jido as MCP Server (Tools for Claude)

For deeper integration, expose **Jido tools** via MCP so Claude agents can act on Jido-managed resources:

- Implement an **MCP server** in Elixir that wraps:
  - Jido agent operations (e.g., `start_agent`, `call_agent`, `await_completion`).
  - Domain-specific tools (e.g., "get project metadata", "enqueue workflow job").
- Register that MCP server with the Claude Agent SDK harness.

The flow then becomes:

- Jido orchestrator sends a `Directive.ClaudeCall`.
- The remote Claude agent:
  - Reads the codebase / files (via its own environment).
  - Calls **MCP tools** exposed by Jido to query or trigger Jido-managed systems.
- Jido receives **tool invocations** and acts accordingly (e.g., emit Jido signals / directives internally).

This is the inverse direction of Phase 1 (Claude → Jido), but uses the same **Jido agent + directive + signal** mechanics.

### 6.4 Jido as A2A Agent (Callable From Other Orchestrators)

Longer-term, Jido can be **wrapped in an A2A server**:

- Map A2A **task requests** to:
  - Jido agent creation (`start_agent`)
  - Initial signals / actions.
- Use `Jido.MultiAgent.await/2` and signals to track progress.
- Emit A2A **task updates** and **task results** when Jido completes.

This allows:

- Claude-based orchestrators (or other vendors) to treat Jido as a **capability provider**.
- Jido and Claude to participate as **peers** in a multi-agent, multi-vendor system.

---

## 7. Risks, Guardrails, and Operational Concerns

### 7.1 Token & Cost Amplification

Anthropic's multi-agent patterns note that **agents and subagents can use 4–15× more tokens** than simple chat.

**Guardrails:**

- Require explicit **mode/verbosity** in `Directive.ClaudeCall` (e.g., `:fast_summary` vs `:deep_refactor`).
- Enforce **budget limits** per directive (max estimated tokens, max runtime).
- Log per-task token usage if available from Claude APIs.

### 7.2 Non-Determinism & Debugging

Agent systems are **non-deterministic** across runs. This is amplified when Jido orchestrates Claude.

Mitigations:

- Include **correlation IDs** in directives and signals (task/session IDs).
- Log:
  - The full `Directive.ClaudeCall` (minus secrets).
  - A trace of `"claude.*"` signals per task.
- Use Jido's telemetry hooks (per `Jido.AgentServer` review) to emit structured traces.

### 7.3 Failure Modes

- CLI process crashes / hangs.
- A2A / HTTP connectivity issues.
- Malformed output from Claude or format changes.

Mitigations:

- Timeouts and retries in `Jido.Claude.Worker`.
- Defensive parsing (`parse_line/1` returning `{:error, :unexpected_format}` rather than crashing).
- Fallback strategies (e.g., mark Jido task as failed and emit `"claude.failed"` signal with raw logs).

### 7.4 Backpressure & Overload

- Too many concurrent Claude tasks can exhaust CPU / rate limits.

Mitigations:

- Use **TaskSupervisor max_children** config in Jido instance (`:max_tasks`).
- Optionally, add a small **worker pool** abstraction (`Jido.AgentPool`) scheduling Claude tasks.

---

## 8. When to Invest in the Advanced Path

Stick with the **Phase 1 CLI-based integration** until you see:

1. **Cross-system workflows** where:
   - Claude needs to call back into Jido or other systems frequently.
   - Multiple tools / data sources must be orchestrated across vendors.
2. **Organizational need for standardization:**
   - Multiple teams building agents in different stacks (Vertex AI, Claude Agent SDK, Jido, etc.).
   - Desire to share capabilities via **MCP** and **A2A** instead of custom HTTP glue.
3. **Scaling beyond one codebase or one repo:**
   - Need to orchestrate many projects / environments reliably.
   - Strong demand for **multi-agent, multi-tenant** orchestration.

At that point, investing in:

- A robust **A2A client/server** implementation in Elixir, and
- One or more **MCP servers** for Jido tools

becomes justified.

---

## 9. Summary & Next Steps

### 9.1 Summary

- Jido's **pure agent + directive** architecture is a natural fit for orchestrating **Claude Code / Claude Agent SDK**.
- The **simplest viable integration**:
  - New `Directive.ClaudeCall` struct
  - A `DirectiveExec` module that spawns a Claude worker (CLI or HTTP)
  - Streaming results back as `Jido.Signal` events
  - A Jido orchestrator agent coordinating higher-level workflows.
- This design is **forward-compatible** with:
  - **A2A** for cross-agent communication
  - **MCP** for tool integration and bidirectional Jido–Claude collaboration.

### 9.2 Concrete Next Steps (Phase 1)

1. **Define directive struct + helpers**
   - `Jido.Agent.Directive.ClaudeCall`
   - `Jido.Agent.Directive.claude_call/1`
2. **Implement directive executor**
   - `Jido.AgentServer.DirectiveExec.ClaudeCall`
   - Integration with Jido's TaskSupervisor and drain loop.
3. **Implement worker harness**
   - `Jido.Claude.Worker` (CLI first; structure to allow HTTP/A2A later).
4. **Add signal types & handlers**
   - `"claude.started"`, `"claude.output_chunk"`, `"claude.completed"`, `"claude.failed"`.
   - Implement `handle_signal/2` in a sample orchestrator agent.
5. **Testing & docs**
   - Unit + integration tests using stubbed worker.
   - Short guide under `guides/integrations/claude.md` referencing this plan.

Once Phase 1 is shipping and stable, revisit this doc to plan A2A/MCP rollout based on actual usage patterns and product needs.
