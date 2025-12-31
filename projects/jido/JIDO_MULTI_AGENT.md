# Jido Multi-Agent Architecture Plan

**Status: ✅ IMPLEMENTED**

## Overview

This document outlines the multi-agent support in Jido. The implementation enables intuitive parent-child agent hierarchies with clear lifecycle signals, seamless communication patterns, and support for LLM-enabled worker agents.

## Current State

### What Works
- `Directive.spawn_agent(agent_module, tag, opts: %{}, meta: %{})` creates a SpawnAgent directive
- SpawnAgent executor starts child via `AgentServer.start/1` with parent reference
- Child receives parent info via `__parent__` field containing `ParentRef` struct (pid, id, tag, meta)
- Parent tracks children via `State.add_child` and `ChildInfo` struct
- `jido.agent.child.exit` signal is sent when child dies
- `jido.agent.orphaned` signal is sent when parent dies
- Agents are pure: `handle_signal/2` returns `{agent, directives}`
- AI directives exist: `ReqLLMStream` for streaming LLM calls

### Problems Discovered
1. **No startup notification**: SpawnAgent does NOT emit a signal when child starts - parent has no callback to know when child is ready
2. **PID dispatch incompatibility**: The `:pid` dispatch adapter sends via `send/2` as `{:signal, signal}`, but AgentServer only handles signals via `GenServer.call/cast` - raw `send/2` messages are ignored
3. **No communication helpers**: No standard parent-child communication patterns or helpers exist
4. **Missing lifecycle signal**: No `jido.agent.child.started` signal exists

---

## Proposed Changes

### 1. Add `jido.agent.child.started` Signal

**Goal**: Parent reliably knows when a child is initialized and ready.

#### Implementation

Create a new core signal module (symmetric with `ChildExit` and `Orphaned`):

```elixir
# lib/jido/agent_server/signal/child_started.ex
defmodule Jido.AgentServer.Signal.ChildStarted do
  @moduledoc """
  Emitted by a child agent when it finishes initialization and becomes ready.
  Delivered to the parent as `jido.agent.child.started`.
  """

  use Jido.Signal,
    type: "jido.agent.child.started",
    default_source: "/agent",
    schema: [
      parent_id: [type: :string, required: true, doc: "ID of the parent agent"],
      child_id: [type: :string, required: true, doc: "ID of the child agent"],
      child_module: [type: :any, required: true, doc: "Module of the child agent"],
      tag: [type: :any, required: true, doc: "Tag used when spawning"],
      pid: [type: :any, required: true, doc: "PID of the child process"],
      meta: [type: :map, default: %{}, doc: "Metadata passed during spawn"]
    ]
end
```

#### Emit from AgentServer

In `handle_continue(:post_init, state)`:

```elixir
@impl true
def handle_continue(:post_init, state) do
  state = notify_parent_if_present(state)
  # ... existing post-init logic ...
  {:noreply, state}
end

defp notify_parent_if_present(%State{parent: %ParentRef{pid: parent_pid} = parent} = state) 
    when is_pid(parent_pid) do
  child_started = ChildStarted.new!(
    %{
      parent_id: parent.id,
      child_id: state.id,
      child_module: state.agent_module,
      tag: parent.tag,
      pid: self(),
      meta: parent.meta
    },
    source: "/agent/#{state.id}"
  )
  
  # Fire-and-forget to parent
  _ = AgentServer.cast(parent_pid, child_started)
  state
end

defp notify_parent_if_present(state), do: state
```

#### Usage in Parent Agents

```elixir
def handle_signal(agent, %Signal{type: "jido.agent.child.started", data: data}) do
  IO.puts("Child #{data.child_id} started with tag #{data.tag}")
  
  # Store child info in agent state
  children = Map.get(agent.state, :active_children, %{})
  child_info = %{id: data.child_id, pid: data.pid, module: data.child_module}
  agent = put_in(agent.state.active_children, Map.put(children, data.tag, child_info))
  
  {agent, []}
end
```

**Effort**: Medium (1-3 hours including tests)

---

### 2. Handle Raw `{:signal, signal}` Messages in AgentServer

**Goal**: Make the `:pid` dispatch adapter work correctly with AgentServer.

#### Problem

The `PidAdapter` default async mode uses:
```elixir
send(target, {:signal, signal})
```

But AgentServer only handles signals via `handle_call` and `handle_cast`, not `handle_info`.

#### Solution

Add `handle_info` clause in AgentServer:

```elixir
@impl true
def handle_info({:signal, %Signal{} = signal}, state) do
  case process_signal(signal, state) do
    {:ok, new_state} -> {:noreply, new_state}
    {:error, _reason, new_state} -> {:noreply, new_state}
  end
end
```

This mirrors the logic in `handle_cast({:signal, signal}, state)`.

**Effort**: Small (<1 hour)

---

### 3. Add Communication Helper Functions

**Goal**: Make parent-child communication boilerplate-free while staying pure.

#### 3.1 `Directive.emit_to_pid/3`

```elixir
# In lib/jido/agent/directive.ex

@doc """
Convenience for emitting a signal directly to an Erlang process PID.

Equivalent to: `%Emit{signal: signal, dispatch: {:pid, [target: pid]}}`

## Examples

    Directive.emit_to_pid(signal, some_pid)
    Directive.emit_to_pid(signal, some_pid, delivery_mode: :sync)
"""
@spec emit_to_pid(Jido.Signal.t(), pid(), Keyword.t()) :: Emit.t()
def emit_to_pid(signal, pid, extra_opts \\ []) when is_pid(pid) do
  opts = Keyword.merge([target: pid], extra_opts)
  %Emit{signal: signal, dispatch: {:pid, opts}}
end
```

#### 3.2 `Directive.emit_to_parent/3`

```elixir
@doc """
Emit a signal to the agent's parent, if any.

Returns `nil` if there is no parent, so callers should use `List.wrap/1`.

## Examples

    def handle_signal(agent, %Signal{type: "work.done"} = _signal) do
      reply = Signal.new!("worker.result", %{answer: 42}, source: "/worker")
      directive = Directive.emit_to_parent(agent, reply)
      {agent, List.wrap(directive)}
    end
"""
@spec emit_to_parent(struct(), Jido.Signal.t(), Keyword.t()) :: Emit.t() | nil
def emit_to_parent(%{__parent__: %ParentRef{pid: pid}}, signal, extra_opts \\ [])
    when is_pid(pid) do
  emit_to_pid(signal, pid, extra_opts)
end

def emit_to_parent(_agent, _signal, _extra_opts), do: nil
```

#### 3.3 Pattern for Parent → Child Communication

No special helper needed. Use `emit_to_pid/3` with the child's PID from `jido.agent.child.started`:

```elixir
def handle_signal(agent, %Signal{type: "jido.agent.child.started", data: data}) do
  # Store child PID
  agent = put_in(agent.state.worker_pid, data.pid)
  
  # Send work to child immediately
  work_signal = Signal.new!("worker.do_work", %{query: "hello"}, source: "/coordinator")
  directive = Directive.emit_to_pid(work_signal, data.pid)
  
  {agent, [directive]}
end
```

**Effort**: Small (~1 hour)

---

### 4. External "Await Completion" Helper

**Goal**: Allow non-agent callers (HTTP controllers, CLI) to wait for agent completion.

```elixir
# lib/jido/multi_agent.ex
defmodule Jido.MultiAgent do
  @moduledoc """
  Helpers for multi-agent coordination from external callers.
  
  These are convenience functions for non-agent code that needs to
  synchronously wait for agents or their children to complete.
  """

  alias Jido.AgentServer

  @doc """
  Wait for an agent to reach a terminal status.
  
  Polls the agent state until `status` is `:completed` or `:failed`,
  or until the timeout is reached.
  
  ## Options
  
  - `:status_path` - Path to status field (default: `[:status]`)
  - `:result_path` - Path to result field (default: `[:last_answer]`)
  - `:poll_interval` - Milliseconds between polls (default: 50)
  
  ## Examples
  
      {:ok, result} = MultiAgent.await_completion(agent_pid, 10_000)
  """
  @spec await_completion(AgentServer.server(), non_neg_integer(), Keyword.t()) ::
          {:ok, %{status: atom(), result: any()}} | {:error, term()}
  def await_completion(server, timeout_ms \\ 10_000, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_interval = Keyword.get(opts, :poll_interval, 50)
    status_path = Keyword.get(opts, :status_path, [:status])
    result_path = Keyword.get(opts, :result_path, [:last_answer])
    
    do_await_completion(server, deadline, poll_interval, status_path, result_path)
  end

  defp do_await_completion(server, deadline, poll_interval, status_path, result_path) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case AgentServer.state(server) do
        {:ok, %{agent: %{state: state}}} ->
          status = get_in(state, status_path)
          
          case status do
            :completed -> {:ok, %{status: :completed, result: get_in(state, result_path)}}
            :failed -> {:ok, %{status: :failed, result: get_in(state, [:error])}}
            _ ->
              Process.sleep(poll_interval)
              do_await_completion(server, deadline, poll_interval, status_path, result_path)
          end
        
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Wait for a specific child of a parent agent to complete.
  
  ## Examples
  
      {:ok, pid} = AgentServer.start(agent: CoordinatorAgent)
      AgentServer.cast(pid, spawn_worker_signal)
      {:ok, result} = MultiAgent.await_child_completion(pid, :worker_1, 10_000)
  """
  @spec await_child_completion(AgentServer.server(), term(), non_neg_integer(), Keyword.t()) ::
          {:ok, %{status: atom(), result: any()}} | {:error, term()}
  def await_child_completion(parent_server, child_tag, timeout_ms \\ 10_000, opts \\ []) do
    with {:ok, %{children: children}} <- AgentServer.state(parent_server),
         %{pid: child_pid} <- Map.get(children, child_tag) do
      await_completion(child_pid, timeout_ms, opts)
    else
      nil -> {:error, :child_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Effort**: Medium (1-3 hours including tests)

---

### 5. Streaming with LLM-Enabled Child Agents

**Goal**: Clear pattern for streaming LLM results from worker to coordinator.

#### Pattern A: Worker Handles Streaming, Sends Final Result

Worker agent:
```elixir
def handle_signal(agent, %Signal{type: "worker.query", data: data}) do
  # Start LLM streaming
  call_id = "llm_#{:erlang.unique_integer([:positive])}"
  agent = put_in(agent.state.call_id, call_id)
  
  llm_directive = AIDirective.ReqLLMStream.new!(%{
    id: call_id,
    model: "anthropic:claude-haiku-4-5",
    context: [%{role: :user, content: data.query}]
  })
  
  {agent, [llm_directive]}
end

def handle_signal(agent, %Signal{type: "reqllm.partial", data: data}) do
  # Accumulate streaming text locally
  current = agent.state.streaming_text || ""
  agent = put_in(agent.state.streaming_text, current <> data.delta)
  {agent, []}
end

def handle_signal(agent, %Signal{type: "reqllm.result", data: data}) do
  answer = extract_answer(data.result)
  agent = put_in(agent.state.answer, answer)
  
  # Send final result to parent
  reply = Signal.new!("worker.answer", %{answer: answer}, source: "/worker")
  directive = Directive.emit_to_parent(agent, reply)
  
  {agent, List.wrap(directive)}
end
```

#### Pattern B: Worker Forwards Streaming to Parent (Advanced)

For real-time streaming in the coordinator:

```elixir
def handle_signal(agent, %Signal{type: "reqllm.partial", data: data} = signal) do
  # Accumulate locally
  current = agent.state.streaming_text || ""
  agent = put_in(agent.state.streaming_text, current <> data.delta)
  
  # Forward to parent for real-time display
  directive = Directive.emit_to_parent(agent, signal)
  
  {agent, List.wrap(directive)}
end
```

**Recommendation**: Default to Pattern A (final result only). Pattern B adds complexity and message volume.

---

## Complete Lifecycle Signals

After implementation, Jido will have a coherent set of lifecycle signals:

| Signal | Direction | When |
|--------|-----------|------|
| `jido.agent.child.started` | Child → Parent | Child finished init |
| `jido.agent.child.exit` | Runtime → Parent | Child process died |
| `jido.agent.orphaned` | Runtime → Child | Parent process died |

---

## Example: Complete Multi-Agent Flow

```elixir
defmodule WorkerAgent do
  use Jido.Agent,
    name: "worker_agent",
    schema: [query: [type: :string], answer: [type: :string]]

  alias Jido.Agent.Directive
  alias Jido.AI.Directive, as: AIDirective

  def handle_signal(agent, %Signal{type: "worker.query", data: data}) do
    llm = AIDirective.ReqLLMStream.new!(%{
      id: "call_#{System.unique_integer([:positive])}",
      model: "anthropic:claude-haiku-4-5",
      context: [%{role: :user, content: data.query}]
    })
    {put_in(agent.state.query, data.query), [llm]}
  end

  def handle_signal(agent, %Signal{type: "reqllm.result", data: data}) do
    answer = data.result |> elem(1) |> Map.get(:text, "")
    agent = put_in(agent.state.answer, answer)
    
    reply = Signal.new!("worker.answer", %{answer: answer}, source: "/worker")
    {agent, List.wrap(Directive.emit_to_parent(agent, reply))}
  end

  def handle_signal(agent, _signal), do: {agent, []}
end

defmodule CoordinatorAgent do
  use Jido.Agent,
    name: "coordinator_agent",
    schema: [
      pending_query: [type: :string],
      answers: [type: {:list, :string}, default: []]
    ]

  alias Jido.Agent.Directive

  def handle_signal(agent, %Signal{type: "start_work", data: data}) do
    spawn_dir = Directive.spawn_agent(WorkerAgent, :worker, meta: %{query: data.query})
    {put_in(agent.state.pending_query, data.query), [spawn_dir]}
  end

  def handle_signal(agent, %Signal{type: "jido.agent.child.started", data: data}) do
    # Child is ready, send it work
    work = Signal.new!("worker.query", %{query: agent.state.pending_query}, source: "/coordinator")
    emit = Directive.emit_to_pid(work, data.pid)
    {agent, [emit]}
  end

  def handle_signal(agent, %Signal{type: "worker.answer", data: data}) do
    answers = [data.answer | agent.state.answers]
    {put_in(agent.state.answers, answers), []}
  end

  def handle_signal(agent, _signal), do: {agent, []}
end

# Usage from outside
{:ok, coordinator} = AgentServer.start(agent: CoordinatorAgent)
signal = Signal.new!("start_work", %{query: "What is 2+2?"}, source: "/external")
AgentServer.cast(coordinator, signal)

# Wait for completion
{:ok, result} = Jido.MultiAgent.await_child_completion(coordinator, :worker, 30_000)
```

---

## Implementation Status

All items have been implemented:

1. ✅ **Handle `{:signal, signal}` in `handle_info`** - Unblocks PID dispatch
2. ✅ **Add `ChildStarted` signal and emission** - Enables startup notification  
3. ✅ **Add `emit_to_pid/3` and `emit_to_parent/3` helpers** - Clean API
4. ✅ **Add `Jido.MultiAgent` helpers** - External coordination
5. ✅ **Update multi_agent.exs example** - Validates the design

### Files Changed

- `lib/jido/agent_server.ex` - Added `handle_info({:signal, ...})` and `notify_parent_of_startup/1`
- `lib/jido/agent_server/signal/child_started.ex` - New file for `jido.agent.child.started` signal
- `lib/jido/agent_server/state.ex` - Injects parent reference into agent state
- `lib/jido/agent/directive.ex` - Added `emit_to_pid/3` and `emit_to_parent/3`
- `lib/jido/multi_agent.ex` - New module with `await_completion/3` and `await_child_completion/4`
- `examples/multi_agent.exs` - Updated example using new patterns

---

## Design Principles

1. **Agents stay pure**: All new functionality uses directives and signals, not side effects in agents
2. **Leverage existing patterns**: Uses the same signal/directive model for parent-child communication
3. **Completion via state**: Follows Elm/Redux semantics - completion is a state concern, not process death
4. **Opt-in complexity**: Simple use cases stay simple; streaming forwarding is opt-in
5. **No hidden magic**: All communication is explicit via signals

---

## Future Considerations

### Cross-Node Agents
If parent and child need to be on different BEAM nodes, the `:pid` adapter won't work. Consider:
- Bus-based routing with node-aware addressing
- Registry with distributed lookup

### Durable Workflows
For workflows that survive restarts, consider:
- Persistent event log for signals
- Checkpoint/restore for agent state
- Job queue integration

### Orchestration DSL
For complex multi-agent patterns, consider:
- `Jido.MultiAgent.Orchestration` behaviour
- Combinators: `parallel/1`, `race/1`, `map_reduce/3`
- Visual workflow builder

These are out of scope for the initial implementation but the design should not preclude them.
