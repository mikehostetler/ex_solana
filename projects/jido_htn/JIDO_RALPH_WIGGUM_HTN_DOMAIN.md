# Ralph Wiggum Loop: HTN Domain Design for AI Coding Agents

> "Me fail English? That's unpossible!" - Ralph Wiggum

This document outlines an HTN (Hierarchical Task Network) domain design for implementing the [Ralph Wiggum loop pattern](https://ghuntley.com/ralph/) in Jido. The pattern uses a deterministic outer loop for planning/coordination and an LLM-powered inner loop for creative execution.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│  USER REQUEST                                                           │
│  "Add a caching layer to the API with Redis"                            │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  OUTER LOOP: HTN Planner (Deterministic "Bash While Loop")              │
│                                                                         │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐                │
│  │ Decompose   │───▶│ Plan Tasks   │───▶│ Execute     │                │
│  │ Goal        │    │ via Methods  │    │ Primitives  │                │
│  └─────────────┘    └──────────────┘    └──────┬──────┘                │
│                                                 │                       │
│  On failure: replan with MTR (Method Traversal Record)                 │
└─────────────────────────────────────────────────┼───────────────────────┘
                                                  │
                    ┌─────────────────────────────┼─────────────────────┐
                    │                             │                     │
                    ▼                             ▼                     ▼
          ┌─────────────────┐           ┌─────────────────┐   ┌─────────────────┐
          │ run_inner_agent │           │ run_tests       │   │ git_commit      │
          │ (ReAct Loop)    │           │ (Bash Action)   │   │ (Bash Action)   │
          └────────┬────────┘           └─────────────────┘   └─────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  INNER LOOP: ReAct Agent (LLM-Powered "Claude Loop")                    │
│                                                                         │
│  Model: Fast/cheap (claude-haiku, gpt-4o-mini)                         │
│  Tools: File read/write, grep, AST manipulation                         │
│  Scope: Single, well-defined implementation task                        │
│                                                                         │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│  │ Reason  │───▶│ Act     │───▶│ Observe │───▶│ Repeat  │              │
│  └─────────┘    └─────────┘    └─────────┘    └────┬────┘              │
│                                                     │                   │
│  Returns: {:ok, %{files_changed: [...], summary: "..."}}               │
└─────────────────────────────────────────────────────────────────────────┘
```

## Why HTN for the Outer Loop?

| Aspect | Pure LLM (ReAct) | Behavior Tree | HTN |
|--------|------------------|---------------|-----|
| **Cost** | Expensive (every step = LLM call) | Cheap | Cheap |
| **Predictability** | Low | High | High |
| **Planning** | Implicit in prompts | None (reactive) | Explicit forward planning |
| **Task Decomposition** | LLM decides | Manual tree design | Automatic via methods |
| **Replanning** | Start over | Fallback nodes | MTR-based smart replanning |
| **Debugging** | Hard (prompt archaeology) | Easy (tree inspection) | Easy (plan + MTR inspection) |

**Key insight:** The outer loop doesn't need creativity—it needs reliable decomposition and execution. Save the LLM tokens for where they matter: the inner loop's actual coding work.

## HTN Domain: `CodingAgent`

### World State Schema

```elixir
%{
  # Repository context
  repo_path: String.t(),
  current_branch: String.t(),
  
  # Task tracking
  user_request: String.t(),
  task_queue: [Task.t()],
  completed_tasks: [Task.t()],
  
  # Quality gates
  tests_passing: boolean(),
  lint_clean: boolean(),
  build_passing: boolean(),
  
  # Inner loop state
  inner_agent_result: map() | nil,
  files_changed: [String.t()],
  
  # Error recovery
  retry_count: non_neg_integer(),
  last_error: String.t() | nil,
  
  # Constraints
  max_retries: non_neg_integer(),  # default: 3
  max_inner_iterations: non_neg_integer()  # default: 20
}
```

### Compound Tasks

#### `fulfill_user_request` (Root Task)

The top-level goal. Decomposes into understanding, planning, executing, and validating.

```elixir
compound_task "fulfill_user_request" do
  # Method 1: Standard flow - understand, plan, execute, validate
  method "standard_flow" do
    precondition fn ws -> 
      ws.user_request != nil and 
      ws.retry_count < ws.max_retries 
    end
    
    subtasks [
      "understand_request",
      "create_implementation_plan", 
      "execute_plan",
      "validate_and_commit"
    ]
  end
  
  # Method 2: Simple request - skip planning for trivial changes
  method "simple_flow" do
    precondition fn ws ->
      ws.user_request != nil and
      simple_request?(ws.user_request)
    end
    
    subtasks [
      "quick_implement",
      "validate_and_commit"
    ]
  end
  
  # Method 3: Recovery - previous attempt failed
  method "recovery_flow" do
    precondition fn ws ->
      ws.last_error != nil and
      ws.retry_count < ws.max_retries
    end
    
    subtasks [
      "analyze_failure",
      "create_recovery_plan",
      "execute_plan",
      "validate_and_commit"
    ]
  end
end
```

#### `understand_request`

Gather context needed before implementation.

```elixir
compound_task "understand_request" do
  method "gather_context" do
    precondition fn ws -> ws.user_request != nil end
    
    subtasks [
      "identify_relevant_files",
      "analyze_codebase_patterns",
      "extract_requirements"
    ]
  end
end
```

#### `execute_plan`

Execute the task queue by delegating to the inner ReAct agent.

```elixir
compound_task "execute_plan" do
  # Method 1: Sequential execution
  method "sequential" do
    precondition fn ws -> 
      length(ws.task_queue) > 0 and
      not has_parallel_tasks?(ws.task_queue)
    end
    
    subtasks [
      "execute_next_task",
      "check_task_result",
      "execute_plan"  # Recursive until queue empty
    ]
  end
  
  # Method 2: Queue exhausted - we're done
  method "complete" do
    precondition fn ws -> length(ws.task_queue) == 0 end
    subtasks []  # No-op, success
  end
end
```

#### `execute_next_task`

The key compound task that delegates to the inner loop.

```elixir
compound_task "execute_next_task" do
  # Method 1: Code implementation task → use inner ReAct agent
  method "inner_agent" do
    precondition fn ws ->
      task = hd(ws.task_queue)
      task.type in [:implement, :refactor, :fix_bug, :add_test]
    end
    
    subtasks ["run_inner_agent"]
  end
  
  # Method 2: Shell command task → run directly
  method "shell_command" do
    precondition fn ws ->
      task = hd(ws.task_queue)
      task.type in [:run_tests, :run_lint, :run_build]
    end
    
    subtasks ["run_shell_command"]
  end
  
  # Method 3: Git operation → run directly  
  method "git_operation" do
    precondition fn ws ->
      task = hd(ws.task_queue)
      task.type in [:git_add, :git_commit, :git_push]
    end
    
    subtasks ["run_git_command"]
  end
end
```

#### `validate_and_commit`

Quality gates before committing changes.

```elixir
compound_task "validate_and_commit" do
  # Method 1: Full validation
  method "full_validation" do
    precondition fn ws -> length(ws.files_changed) > 0 end
    
    subtasks [
      "run_tests",
      "run_lint", 
      "run_build",
      "git_stage_changes",
      "git_commit"
    ]
  end
  
  # Method 2: Quick validation (tests only)
  method "quick_validation" do
    precondition fn ws -> 
      length(ws.files_changed) > 0 and
      ws.files_changed |> Enum.all?(&test_file?/1)
    end
    
    subtasks [
      "run_tests",
      "git_stage_changes", 
      "git_commit"
    ]
  end
  
  # Method 3: No changes made
  method "no_changes" do
    precondition fn ws -> length(ws.files_changed) == 0 end
    subtasks []  # No-op
  end
end
```

#### `check_task_result`

Handle success/failure after inner agent completes.

```elixir
compound_task "check_task_result" do
  # Method 1: Success - pop task, continue
  method "success" do
    precondition fn ws ->
      ws.inner_agent_result != nil and
      ws.inner_agent_result.status == :success
    end
    
    subtasks ["pop_completed_task", "merge_file_changes"]
  end
  
  # Method 2: Failure - retry with feedback
  method "retry" do
    precondition fn ws ->
      ws.inner_agent_result != nil and
      ws.inner_agent_result.status == :failure and
      ws.retry_count < ws.max_retries
    end
    
    subtasks ["increment_retry", "enrich_task_with_feedback", "run_inner_agent"]
  end
  
  # Method 3: Max retries exceeded - escalate
  method "escalate" do
    precondition fn ws ->
      ws.inner_agent_result != nil and
      ws.inner_agent_result.status == :failure and
      ws.retry_count >= ws.max_retries
    end
    
    subtasks ["report_failure", "rollback_changes"]
  end
end
```

### Primitive Tasks

These are the leaf nodes—actual `Jido.Action` modules that execute.

```elixir
# === Context Gathering ===

primitive_task "identify_relevant_files" do
  action: Jido.Ralph.Actions.IdentifyFiles
  effects: fn result -> %{relevant_files: result.files} end
end

primitive_task "analyze_codebase_patterns" do
  action: Jido.Ralph.Actions.AnalyzePatterns
  effects: fn result -> %{patterns: result.patterns, conventions: result.conventions} end
end

primitive_task "extract_requirements" do
  action: Jido.Ralph.Actions.ExtractRequirements
  effects: fn result -> %{requirements: result.requirements, constraints: result.constraints} end
end

# === Planning ===

primitive_task "create_implementation_plan" do
  action: Jido.Ralph.Actions.CreatePlan
  effects: fn result -> %{task_queue: result.tasks} end
end

primitive_task "create_recovery_plan" do
  action: Jido.Ralph.Actions.CreateRecoveryPlan
  effects: fn result -> %{task_queue: result.tasks, recovery_strategy: result.strategy} end
end

# === Inner Agent Execution ===

primitive_task "run_inner_agent" do
  action: Jido.Ralph.Actions.RunInnerAgent
  
  # This is the key primitive - spawns a ReAct agent
  # See implementation below
  
  effects: fn result -> 
    %{
      inner_agent_result: result,
      files_changed: result.files_changed ++ get(:files_changed, [])
    }
  end
end

# === Shell Commands ===

primitive_task "run_tests" do
  action: Jido.Ralph.Actions.RunShell
  params: [command: "mix test"]
  effects: fn result -> %{tests_passing: result.exit_code == 0} end
end

primitive_task "run_lint" do
  action: Jido.Ralph.Actions.RunShell
  params: [command: "mix credo"]
  effects: fn result -> %{lint_clean: result.exit_code == 0} end
end

primitive_task "run_build" do
  action: Jido.Ralph.Actions.RunShell
  params: [command: "mix compile --warnings-as-errors"]
  effects: fn result -> %{build_passing: result.exit_code == 0} end
end

# === Git Operations ===

primitive_task "git_stage_changes" do
  action: Jido.Ralph.Actions.GitStage
  effects: fn _result -> %{staged: true} end
end

primitive_task "git_commit" do
  action: Jido.Ralph.Actions.GitCommit
  effects: fn result -> %{commit_sha: result.sha, committed: true} end
end

# === Task Queue Management ===

primitive_task "pop_completed_task" do
  action: Jido.Ralph.Actions.PopTask
  effects: fn result -> 
    %{
      task_queue: result.remaining_tasks,
      completed_tasks: [result.completed | get(:completed_tasks, [])]
    }
  end
end

primitive_task "increment_retry" do
  action: Jido.Ralph.Actions.IncrementRetry
  effects: fn _result -> %{retry_count: get(:retry_count, 0) + 1} end
end

# === Error Handling ===

primitive_task "report_failure" do
  action: Jido.Ralph.Actions.ReportFailure
  effects: fn _result -> %{failure_reported: true} end
end

primitive_task "rollback_changes" do
  action: Jido.Ralph.Actions.GitRollback
  effects: fn _result -> %{files_changed: [], rolled_back: true} end
end
```

## Key Action Implementations

### `Jido.Ralph.Actions.RunInnerAgent`

This is the bridge between the HTN outer loop and the ReAct inner loop:

```elixir
defmodule Jido.Ralph.Actions.RunInnerAgent do
  @moduledoc """
  Spawns a ReAct-powered inner agent to execute a coding task.
  
  This is the key primitive that bridges the deterministic HTN outer loop
  with the LLM-powered ReAct inner loop.
  """
  
  use Jido.Action,
    name: "ralph.run_inner_agent",
    description: "Execute a coding task using the inner ReAct agent",
    schema: Zoi.object(%{
      task: Zoi.string(),
      context: Zoi.map(%{
        files: Zoi.list(Zoi.string()) |> Zoi.optional(),
        patterns: Zoi.any() |> Zoi.optional(),
        constraints: Zoi.list(Zoi.string()) |> Zoi.optional()
      }) |> Zoi.optional(),
      timeout_ms: Zoi.integer() |> Zoi.default(120_000),
      max_iterations: Zoi.integer() |> Zoi.default(20)
    })

  @impl true
  def run(%{task: task, context: context, timeout_ms: timeout, max_iterations: max_iter}, _opts) do
    # Build inner agent configuration
    inner_config = %{
      model: :fast,  # Use cheap model for inner loop
      max_iterations: max_iter,
      tools: coding_tools(),
      system_prompt: build_inner_prompt(context)
    }
    
    # Start inner agent
    {:ok, pid} = Jido.AgentServer.start(
      agent: Jido.Ralph.InnerAgent,
      strategy_opts: inner_config,
      state: %{context: context}
    )
    
    # Kick off the ReAct loop
    :ok = Jido.Ralph.InnerAgent.ask(pid, task)
    
    # Wait for completion with timeout
    result = await_completion(pid, timeout)
    
    # Cleanup
    Jido.AgentServer.stop(pid)
    
    case result do
      {:ok, agent} ->
        snapshot = extract_result(agent)
        {:ok, snapshot}
        
      {:timeout, agent} ->
        snapshot = extract_result(agent)
        {:ok, Map.put(snapshot, :status, :timeout)}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp coding_tools do
    [
      Jido.Tools.FileSystem.Read,
      Jido.Tools.FileSystem.Write,
      Jido.Tools.FileSystem.List,
      Jido.Tools.Grep,
      Jido.Tools.AST.Parse,
      Jido.Tools.AST.Transform
    ]
  end
  
  defp await_completion(pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    
    Stream.repeatedly(fn -> 
      {Jido.AgentServer.get(pid), System.monotonic_time(:millisecond)}
    end)
    |> Enum.reduce_while(nil, fn {agent, now}, _acc ->
      strategy_state = agent.state.__strategy__
      
      cond do
        strategy_state.status in [:completed, :error] ->
          {:halt, {:ok, agent}}
          
        now > deadline ->
          {:halt, {:timeout, agent}}
          
        true ->
          Process.sleep(200)
          {:cont, nil}
      end
    end)
  end
  
  defp extract_result(agent) do
    strategy_state = agent.state.__strategy__
    
    %{
      status: map_status(strategy_state.status),
      files_changed: strategy_state[:files_changed] || [],
      summary: strategy_state[:final_answer],
      iterations: strategy_state[:iteration],
      usage: strategy_state[:usage]
    }
  end
  
  defp map_status(:completed), do: :success
  defp map_status(:error), do: :failure
  defp map_status(other), do: other
end
```

### `Jido.Ralph.InnerAgent`

The inner ReAct agent definition:

```elixir
defmodule Jido.Ralph.InnerAgent do
  @moduledoc """
  Inner loop agent for the Ralph Wiggum pattern.
  
  Uses ReAct strategy with a fast/cheap model to execute
  well-scoped coding tasks delegated by the outer HTN loop.
  """
  
  use Jido.AI.ReActAgent,
    name: "ralph_inner",
    description: "Inner coding agent for scoped implementation tasks",
    tools: [
      Jido.Tools.FileSystem.Read,
      Jido.Tools.FileSystem.Write,
      Jido.Tools.FileSystem.List,
      Jido.Tools.Grep,
      Jido.Tools.AST.Parse,
      Jido.Tools.AST.Transform
    ],
    model: :fast,
    max_iterations: 20,
    system_prompt: """
    You are an inner-loop coding agent. You receive well-scoped tasks from an outer planning system.
    
    Your job is to:
    1. Understand the specific task you've been given
    2. Use tools to read relevant files and understand context
    3. Make the minimal changes needed to complete the task
    4. Verify your changes are syntactically correct
    
    Guidelines:
    - Stay focused on the specific task - don't expand scope
    - Make small, incremental changes
    - If you're stuck after 3 attempts, report what's blocking you
    - Track all files you modify for the outer loop
    
    When done, summarize what you changed and any concerns.
    """
end
```

## HTN Strategy for Jido Agents

A new strategy that wraps the HTN planner for agent execution:

```elixir
defmodule Jido.Agent.Strategy.HTN do
  @moduledoc """
  HTN-based execution strategy for Jido agents.
  
  Uses hierarchical task network planning for goal decomposition
  and deterministic plan execution.
  
  ## Configuration
  
      use Jido.Agent,
        name: "my_htn_agent",
        strategy: {Jido.Agent.Strategy.HTN,
          domain: MyApp.CodingDomain,
          root_task: "fulfill_user_request"
        }
  """
  
  use Jido.Agent.Strategy
  
  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.HTN
  
  @impl true
  def init(%Agent{} = agent, ctx) do
    opts = ctx[:strategy_opts] || []
    domain = Keyword.fetch!(opts, :domain)
    root_task = Keyword.get(opts, :root_task, "root")
    
    state = %{
      domain: domain,
      root_task: root_task,
      plan: nil,
      plan_index: 0,
      world_state: %{},
      status: :idle,
      mtr: nil  # Method Traversal Record for replanning
    }
    
    agent = StratState.put(agent, state)
    {agent, []}
  end
  
  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    state = StratState.get(agent, %{})
    
    case instructions do
      [%{action: :start_planning, params: %{goal: goal, world_state: ws}}] ->
        handle_start_planning(agent, state, goal, ws)
        
      [%{action: :execute_next}] ->
        handle_execute_next(agent, state)
        
      [%{action: :task_completed, params: %{result: result}}] ->
        handle_task_completed(agent, state, result)
        
      [%{action: :task_failed, params: %{error: error}}] ->
        handle_task_failed(agent, state, error)
        
      _ ->
        {agent, []}
    end
  end
  
  defp handle_start_planning(agent, state, goal, world_state) do
    ws = Map.merge(world_state, %{user_request: goal})
    
    case HTN.plan(state.domain, ws, root_tasks: [state.root_task]) do
      {:ok, plan, mtr} ->
        new_state = %{state | 
          plan: plan, 
          plan_index: 0, 
          world_state: ws,
          status: :executing,
          mtr: mtr
        }
        agent = StratState.put(agent, new_state)
        
        # Emit directive to execute first primitive
        directive = build_execute_directive(hd(plan), ws)
        {agent, [directive]}
        
      {:error, reason} ->
        new_state = %{state | status: :failed, error: reason}
        agent = StratState.put(agent, new_state)
        {agent, [%Jido.Agent.Directive.Error{error: reason}]}
    end
  end
  
  defp handle_execute_next(agent, state) do
    case Enum.at(state.plan, state.plan_index) do
      nil ->
        # Plan complete
        new_state = %{state | status: :completed}
        agent = StratState.put(agent, new_state)
        {agent, []}
        
      task ->
        directive = build_execute_directive(task, state.world_state)
        {agent, [directive]}
    end
  end
  
  defp handle_task_completed(agent, state, result) do
    # Apply effects to world state
    new_ws = apply_effects(state.world_state, result)
    new_state = %{state | 
      plan_index: state.plan_index + 1,
      world_state: new_ws
    }
    agent = StratState.put(agent, new_state)
    
    # Continue to next task
    handle_execute_next(agent, new_state)
  end
  
  defp handle_task_failed(agent, state, error) do
    # Attempt replanning using MTR
    new_ws = Map.put(state.world_state, :last_error, error)
    
    case HTN.plan(state.domain, new_ws, 
           root_tasks: [state.root_task],
           current_plan_mtr: state.mtr) do
      {:ok, new_plan, new_mtr} ->
        new_state = %{state |
          plan: new_plan,
          plan_index: 0,
          world_state: new_ws,
          mtr: new_mtr
        }
        agent = StratState.put(agent, new_state)
        
        directive = build_execute_directive(hd(new_plan), new_ws)
        {agent, [directive]}
        
      {:error, reason} ->
        new_state = %{state | status: :failed, error: reason}
        agent = StratState.put(agent, new_state)
        {agent, [%Jido.Agent.Directive.Error{error: reason}]}
    end
  end
  
  defp build_execute_directive({action_module, params}, world_state) do
    %Jido.Agent.Directive.Exec{
      action: action_module,
      params: Map.merge(params, %{world_state: world_state})
    }
  end
  
  defp apply_effects(world_state, result) do
    # Effects are defined on primitive tasks
    # This would call the effect functions with the result
    Map.merge(world_state, result.effects || %{})
  end
  
  @impl true
  def snapshot(agent, _ctx) do
    state = StratState.get(agent, %{})
    
    %Jido.Agent.Strategy.Snapshot{
      status: state.status || :idle,
      done?: state.status in [:completed, :failed],
      result: state[:result],
      details: %{
        plan_length: length(state.plan || []),
        plan_index: state.plan_index || 0,
        world_state_keys: Map.keys(state.world_state || %{})
      }
    }
  end
end
```

## Execution Flow Example

Given user request: "Add Redis caching to the user service"

```
1. HTN receives goal, plans:
   Plan = [
     {IdentifyFiles, %{query: "user service"}},
     {AnalyzePatterns, %{focus: "caching"}},
     {ExtractRequirements, %{}},
     {CreatePlan, %{}},
     {RunInnerAgent, %{task: "Add Redis client dependency"}},
     {RunInnerAgent, %{task: "Create Redis connection module"}},
     {RunInnerAgent, %{task: "Add caching to UserService.get/1"}},
     {RunTests, %{}},
     {RunLint, %{}},
     {GitStage, %{}},
     {GitCommit, %{message: "feat: add Redis caching to user service"}}
   ]

2. Execute primitives sequentially:
   
   [IdentifyFiles] → world_state += {relevant_files: ["lib/user_service.ex", ...]}
   [AnalyzePatterns] → world_state += {patterns: %{caching: nil, ...}}
   [ExtractRequirements] → world_state += {requirements: [...]}
   [CreatePlan] → world_state += {task_queue: [...]}
   
   [RunInnerAgent] "Add Redis client dependency"
     └─► Spawns ReAct agent with :fast model
     └─► ReAct: reads mix.exs → adds {:redix, "~> 1.0"} → writes mix.exs
     └─► Returns {:ok, %{files_changed: ["mix.exs"], status: :success}}
   
   [RunInnerAgent] "Create Redis connection module"  
     └─► Spawns ReAct agent
     └─► ReAct: creates lib/my_app/redis.ex with connection pool
     └─► Returns {:ok, %{files_changed: ["lib/my_app/redis.ex"], status: :success}}
   
   [RunInnerAgent] "Add caching to UserService.get/1"
     └─► Spawns ReAct agent
     └─► ReAct: reads user_service.ex → adds cache check → writes
     └─► Returns {:ok, %{files_changed: ["lib/user_service.ex"], status: :success}}
   
   [RunTests] → mix test → exit_code: 0 → world_state += {tests_passing: true}
   [RunLint] → mix credo → exit_code: 0 → world_state += {lint_clean: true}
   [GitStage] → git add -A
   [GitCommit] → git commit -m "feat: add Redis caching to user service"

3. Plan complete, status: :completed
```

## Replanning on Failure

If `RunTests` fails:

```
1. Task fails: {RunTests, exit_code: 1, output: "test/user_service_test.exs:42 - expected ..."}

2. HTN receives :task_failed, attempts replan with MTR
   - MTR records which methods were chosen
   - Planner tries alternative methods or inserts fix tasks

3. New plan suffix:
   [
     {AnalyzeTestFailure, %{output: "..."}},
     {RunInnerAgent, %{task: "Fix failing test in user_service_test.exs:42"}},
     {RunTests, %{}},  # Retry
     {GitStage, %{}},
     {GitCommit, %{}}
   ]

4. Continue execution from new plan
```

## Benefits of This Architecture

1. **Cost Efficiency**: Outer loop is zero LLM cost; inner loop uses cheap model
2. **Predictability**: HTN plans are inspectable and deterministic
3. **Debuggability**: Full plan + MTR visible; can replay/step through
4. **Robustness**: Built-in replanning on failure via HTR
5. **Separation of Concerns**: Planning logic vs execution logic cleanly separated
6. **Testability**: Can test HTN domain without LLM; can test inner agent separately

## Future Enhancements

1. **Parallel Execution**: HTN supports background tasks; could run independent inner agents concurrently
2. **Progress Streaming**: Inner agent emits signals; outer loop can observe without LLM calls
3. **Human-in-the-Loop**: Insert approval checkpoints as primitive tasks
4. **Learning**: Record successful plans; use as examples for similar requests
5. **Cost Budgets**: Track token usage; abort if budget exceeded

## References

- [Ralph Wiggum Loop](https://ghuntley.com/ralph/) - Original pattern description
- [HTN Planning](https://en.wikipedia.org/wiki/Hierarchical_task_network) - Academic background
- [Jido HTN](../lib/jido_htn/) - Jido's HTN implementation
- [Jido ReAct Strategy](../../jido_ai/lib/jido_ai/strategy/react.ex) - Inner loop implementation
