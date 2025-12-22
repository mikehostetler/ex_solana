# DAG-Based AI Workflow Orchestration System for JidoCode

A comprehensive design integrating Reactor's programmatic DAG execution with Jido's agent, signal, and action ecosystems to create a powerful, markdown-defined workflow system for the JidoCode TUI coding assistant.

## Bottom line: Reactor's Builder API enables dynamic DAG construction

The Reactor library provides a **programmatic Builder API** that produces identical runtime structures to its DSL, making it ideal for constructing workflows from parsed markdown definitions at runtime. Combined with Jido's Signal Bus for triggering and Agent lifecycle hooks for orchestration, this creates a complete workflow engine that integrates seamlessly with JidoCode's existing extensibility system.

---

## Markdown workflow definition format

Workflows are defined in `.jido_code/workflows/*.md` files using YAML frontmatter for configuration and structured content for the DAG definition.

### Complete workflow example

```markdown
---
name: code_review_pipeline
version: "1.0.0"
description: Automated code review workflow with AI agents
enabled: true

inputs:
  - name: file_path
    type: string
    required: true
    description: Path to file being reviewed
  - name: diff_content
    type: string
    required: false
    description: Git diff content if available

triggers:
  - type: file_system
    patterns: ["lib/**/*.ex", "test/**/*_test.exs"]
    events: [modified, created]
    debounce_ms: 1000
  - type: git_hook
    events: [pre_commit]
  - type: signal
    patterns: ["code.review.requested"]
  - type: manual
    command: "/workflow:review"

settings:
  max_concurrency: 4
  timeout_ms: 300000
  retry_policy:
    max_retries: 3
    backoff: exponential
    base_delay_ms: 1000
  on_failure: compensate

channel:
  topic: "workflow:code_review"
  broadcast_events: [step_started, step_completed, step_failed, workflow_complete]
---

# Code Review Pipeline

Automated code review combining static analysis with AI-powered suggestions.

## Steps

### parse_file
- **type**: action
- **module**: JidoCode.Actions.ParseElixirFile
- **inputs**:
  - file_path: `input:file_path`
- **outputs**: [ast, module_info, functions]
- **async**: true

### static_analysis
- **type**: action
- **module**: JidoCode.Actions.RunCredo
- **inputs**:
  - file_path: `input:file_path`
- **depends_on**: []
- **outputs**: [issues, suggestions]
- **async**: true

### type_check
- **type**: action
- **module**: JidoCode.Actions.RunDialyzer
- **inputs**:
  - file_path: `input:file_path`
- **depends_on**: []
- **outputs**: [warnings, types]
- **optional**: true
- **async**: true

### ai_code_review
- **type**: agent
- **agent**: code_reviewer
- **pre_actions**:
  - module: JidoCode.Actions.PrepareContext
    inputs:
      ast: `result:parse_file.ast`
      issues: `result:static_analysis.issues`
- **inputs**:
  - code: `input:file_path`
  - ast: `result:parse_file.ast`
  - static_issues: `result:static_analysis.issues`
  - type_info: `result:type_check.types`
- **depends_on**: [parse_file, static_analysis, type_check]
- **mode**: sync
- **timeout_ms**: 60000
- **post_actions**:
  - module: JidoCode.Actions.FormatReviewOutput
    inputs:
      review: `result:ai_code_review`

### security_scan
- **type**: agent
- **agent**: security_analyzer
- **inputs**:
  - ast: `result:parse_file.ast`
  - functions: `result:parse_file.functions`
- **depends_on**: [parse_file]
- **mode**: async
- **callback_signal**: "security.scan.complete"

### generate_suggestions
- **type**: agent
- **agent**: suggestion_generator
- **inputs**:
  - review: `result:ai_code_review`
  - security: `result:security_scan`
  - issues: `result:static_analysis.issues`
- **depends_on**: [ai_code_review, security_scan]

### apply_fixes
- **type**: sub_workflow
- **workflow**: auto_fix_pipeline
- **inputs**:
  - suggestions: `result:generate_suggestions.suggestions`
  - file_path: `input:file_path`
- **depends_on**: [generate_suggestions]
- **condition**: `result:generate_suggestions.has_auto_fixable`

## Error Handling

### compensate:ai_code_review
- **action**: JidoCode.Actions.RevertContext
- **inputs**:
  - context_id: `result:ai_code_review.context_id`

## Return
- **value**: generate_suggestions
- **transform**: |
    fn result -> 
      %{
        summary: result.summary,
        suggestions: result.suggestions,
        auto_applied: result.auto_applied
      }
    end
```

### Workflow syntax reference

**Step types support three primary node categories:**

| Type | Description | Key Properties |
|------|-------------|----------------|
| `action` | Deterministic Jido.Action execution | `module`, `inputs`, `outputs` |
| `agent` | LLM-powered agent with tools | `agent`, `mode`, `pre_actions`, `post_actions` |
| `sub_workflow` | Nested workflow invocation | `workflow`, `condition`, `parallel` |

**Input reference syntax:**

```yaml
# Reference workflow inputs
file_path: `input:file_path`

# Reference step results
ast: `result:parse_file.ast`
issues: `result:static_analysis.issues`

# Reference nested values
types: `result:type_check.output.types`

# Static values
timeout: 5000
enabled: true
```

---

## Reactor programmatic API integration

The workflow engine translates parsed markdown definitions into Reactor workflows using the Builder API.

### Core workflow compiler module

```elixir
defmodule JidoCode.Workflow.Compiler do
  @moduledoc """
  Compiles parsed workflow definitions into executable Reactor workflows.
  Uses Reactor.Builder programmatic API - no DSL macros.
  """
  
  alias Reactor.{Builder, Argument}
  alias JidoCode.Workflow.{StepFactory, ArgumentResolver}
  
  @doc """
  Compiles a workflow definition map into a Reactor struct.
  """
  def compile(%{inputs: inputs, steps: steps, return: return_config} = definition) do
    with {:ok, reactor} <- initialize_reactor(inputs),
         {:ok, reactor} <- add_steps(reactor, steps),
         {:ok, reactor} <- set_return(reactor, return_config) do
      {:ok, reactor}
    end
  end
  
  defp initialize_reactor(inputs) do
    reactor = Builder.new()
    
    Enum.reduce_while(inputs, {:ok, reactor}, fn input_def, {:ok, reactor} ->
      case Builder.add_input(reactor, input_def.name) do
        {:ok, reactor} -> {:cont, {:ok, reactor}}
        error -> {:halt, error}
      end
    end)
  end
  
  defp add_steps(reactor, steps) do
    # Topologically sort steps by dependencies
    sorted_steps = topological_sort(steps)
    
    Enum.reduce_while(sorted_steps, {:ok, reactor}, fn step, {:ok, reactor} ->
      case compile_step(reactor, step) do
        {:ok, reactor} -> {:cont, {:ok, reactor}}
        error -> {:halt, error}
      end
    end)
  end
  
  defp compile_step(reactor, %{type: :action} = step) do
    arguments = ArgumentResolver.resolve_arguments(step.inputs)
    
    Builder.add_step(
      reactor,
      step.name,
      StepFactory.action_step(step.module),
      arguments,
      max_retries: step[:max_retries] || 0,
      async?: step[:async] || true
    )
  end
  
  defp compile_step(reactor, %{type: :agent} = step) do
    # Agent steps use a wrapper that handles pre/post actions
    arguments = ArgumentResolver.resolve_arguments(step.inputs)
    
    step_impl = StepFactory.agent_step(
      step.agent,
      pre_actions: step[:pre_actions] || [],
      post_actions: step[:post_actions] || [],
      mode: step[:mode] || :sync,
      timeout_ms: step[:timeout_ms]
    )
    
    Builder.add_step(
      reactor,
      step.name,
      step_impl,
      arguments,
      max_retries: step[:max_retries] || 0,
      async?: step[:mode] != :sync
    )
  end
  
  defp compile_step(reactor, %{type: :sub_workflow} = step) do
    arguments = ArgumentResolver.resolve_arguments(step.inputs)
    
    # Use Reactor.Builder.Compose for nested workflows
    sub_reactor = load_sub_workflow(step.workflow)
    
    Builder.Compose.compose(
      reactor,
      step.name,
      sub_reactor,
      arguments,
      async?: true
    )
  end
  
  defp set_return(reactor, %{value: step_name, transform: transform_fn}) do
    reactor = if transform_fn do
      # Apply transformation to return value
      {:ok, reactor} = Builder.add_step(
        reactor,
        :__return_transform__,
        {JidoCode.Workflow.Steps.Transform, transform: transform_fn},
        [Argument.from_result(:value, step_name)]
      )
      Builder.return(reactor, :__return_transform__)
    else
      Builder.return(reactor, step_name)
    end
  end
end
```

### Argument resolution for DAG edges

```elixir
defmodule JidoCode.Workflow.ArgumentResolver do
  @moduledoc """
  Resolves workflow argument references into Reactor.Argument structs.
  Handles input:, result:, and static value references.
  """
  
  alias Reactor.Argument
  
  def resolve_arguments(inputs) when is_list(inputs) do
    Enum.map(inputs, &resolve_argument/1)
  end
  
  def resolve_arguments(inputs) when is_map(inputs) do
    Enum.map(inputs, fn {name, value} -> resolve_argument({name, value}) end)
  end
  
  defp resolve_argument({name, value}) when is_binary(value) do
    case parse_reference(value) do
      {:input, input_name} ->
        Argument.from_input(name, String.to_atom(input_name))
        
      {:result, step_name, path} ->
        arg = Argument.from_result(name, String.to_atom(step_name))
        if path, do: Argument.sub_path(arg, parse_path(path)), else: arg
        
      :static ->
        Argument.from_value(name, value)
    end
  end
  
  defp resolve_argument({name, value}) do
    Argument.from_value(name, value)
  end
  
  defp parse_reference(value) do
    cond do
      String.starts_with?(value, "`input:") ->
        input_name = value |> String.trim_leading("`input:") |> String.trim_trailing("`")
        {:input, input_name}
        
      String.starts_with?(value, "`result:") ->
        ref = value |> String.trim_leading("`result:") |> String.trim_trailing("`")
        case String.split(ref, ".", parts: 2) do
          [step] -> {:result, step, nil}
          [step, path] -> {:result, step, path}
        end
        
      true ->
        :static
    end
  end
  
  defp parse_path(path), do: String.split(path, ".") |> Enum.map(&String.to_atom/1)
end
```

### Step factory for different step types

```elixir
defmodule JidoCode.Workflow.StepFactory do
  @moduledoc """
  Creates Reactor step implementations for different step types.
  """
  
  @doc """
  Creates an action step wrapper implementing Reactor.Step behaviour.
  """
  def action_step(module) when is_atom(module) do
    {JidoCode.Workflow.Steps.ActionStep, module: module}
  end
  
  @doc """
  Creates an agent step wrapper with lifecycle hooks.
  """
  def agent_step(agent_name, opts) do
    {JidoCode.Workflow.Steps.AgentStep, 
     Keyword.merge(opts, agent: agent_name)}
  end
end

defmodule JidoCode.Workflow.Steps.ActionStep do
  @moduledoc """
  Reactor step that executes a Jido.Action.
  """
  use Reactor.Step
  
  @impl true
  def run(arguments, context, options) do
    module = Keyword.fetch!(options, :module)
    
    case module.run(Map.new(arguments), context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def compensate(error, _arguments, _context, options) do
    module = Keyword.fetch!(options, :module)
    
    if function_exported?(module, :compensate, 1) do
      module.compensate(error)
    else
      :ok
    end
  end
  
  @impl true
  def undo(result, arguments, _context, options) do
    module = Keyword.fetch!(options, :module)
    
    if function_exported?(module, :undo, 2) do
      module.undo(result, Map.new(arguments))
    else
      :ok
    end
  end
end

defmodule JidoCode.Workflow.Steps.AgentStep do
  @moduledoc """
  Reactor step that executes a Jido Agent with pre/post actions.
  """
  use Reactor.Step
  
  alias JidoCode.Workflow.AgentLifecycle
  
  @impl true
  def run(arguments, context, options) do
    agent_name = Keyword.fetch!(options, :agent)
    pre_actions = Keyword.get(options, :pre_actions, [])
    post_actions = Keyword.get(options, :post_actions, [])
    mode = Keyword.get(options, :mode, :sync)
    timeout = Keyword.get(options, :timeout_ms, 60_000)
    
    with {:ok, pre_results} <- AgentLifecycle.run_pre_actions(pre_actions, arguments),
         {:ok, agent_result} <- execute_agent(agent_name, arguments, pre_results, mode, timeout),
         {:ok, final_result} <- AgentLifecycle.run_post_actions(post_actions, agent_result) do
      {:ok, final_result}
    end
  end
  
  defp execute_agent(agent_name, arguments, pre_results, :sync, timeout) do
    merged_args = Map.merge(Map.new(arguments), pre_results)
    
    case JidoCode.AgentRegistry.get_agent(agent_name) do
      {:ok, agent_pid} ->
        Jido.Agent.Runtime.cmd(agent_pid, :execute, merged_args, timeout: timeout)
      {:error, :not_found} ->
        {:error, {:agent_not_found, agent_name}}
    end
  end
  
  defp execute_agent(agent_name, arguments, pre_results, :async, _timeout) do
    merged_args = Map.merge(Map.new(arguments), pre_results)
    
    case JidoCode.AgentRegistry.get_agent(agent_name) do
      {:ok, agent_pid} ->
        :ok = Jido.Agent.Runtime.cmd_async(agent_pid, :execute, merged_args)
        {:ok, %{status: :async_started, agent: agent_name}}
      {:error, :not_found} ->
        {:error, {:agent_not_found, agent_name}}
    end
  end
  
  @impl true
  def compensate(_error, _arguments, _context, options) do
    # Agent compensation logic - potentially notify agent to rollback
    agent_name = Keyword.fetch!(options, :agent)
    JidoCode.AgentRegistry.notify_compensation(agent_name)
    :ok
  end
end
```

---

## Trigger system architecture

The trigger system supports five trigger types, each implemented as a supervised process that monitors its source and emits workflow execution requests.

### Trigger supervisor and registry

```elixir
defmodule JidoCode.Workflow.TriggerSupervisor do
  @moduledoc """
  Supervises all workflow triggers with dynamic child management.
  """
  use DynamicSupervisor
  
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  def start_trigger(trigger_config) do
    child_spec = trigger_child_spec(trigger_config)
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  def stop_trigger(trigger_id) do
    case Registry.lookup(JidoCode.TriggerRegistry, trigger_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
  
  defp trigger_child_spec(%{type: :file_system} = config) do
    {JidoCode.Workflow.Triggers.FileSystem, config}
  end
  
  defp trigger_child_spec(%{type: :git_hook} = config) do
    {JidoCode.Workflow.Triggers.GitHook, config}
  end
  
  defp trigger_child_spec(%{type: :signal} = config) do
    {JidoCode.Workflow.Triggers.Signal, config}
  end
  
  defp trigger_child_spec(%{type: :scheduled} = config) do
    {JidoCode.Workflow.Triggers.Scheduled, config}
  end
  
  defp trigger_child_spec(%{type: :manual} = config) do
    {JidoCode.Workflow.Triggers.Manual, config}
  end
end
```

### File system trigger implementation

```elixir
defmodule JidoCode.Workflow.Triggers.FileSystem do
  @moduledoc """
  Watches file system for changes and triggers workflows.
  Uses the file_system package for cross-platform support.
  """
  use GenServer
  
  require Logger
  
  defstruct [:workflow_id, :patterns, :events, :debounce_ms, :watcher_pid, :pending_events]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
  end
  
  def init(config) do
    dirs = resolve_watch_directories(config.patterns)
    {:ok, watcher_pid} = FileSystem.start_link(dirs: dirs)
    FileSystem.subscribe(watcher_pid)
    
    state = %__MODULE__{
      workflow_id: config.workflow_id,
      patterns: compile_patterns(config.patterns),
      events: MapSet.new(config.events || [:modified, :created]),
      debounce_ms: config.debounce_ms || 500,
      watcher_pid: watcher_pid,
      pending_events: %{}
    }
    
    {:ok, state}
  end
  
  def handle_info({:file_event, _pid, {path, events}}, state) do
    if should_trigger?(path, events, state) do
      # Debounce rapid file changes
      state = schedule_debounced_trigger(state, path, events)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  def handle_info({:trigger_debounced, path}, state) do
    case Map.pop(state.pending_events, path) do
      {nil, state} -> 
        {:noreply, state}
      {events, pending} ->
        trigger_workflow(state.workflow_id, %{
          file_path: path,
          events: events,
          trigger_type: :file_system
        })
        {:noreply, %{state | pending_events: pending}}
    end
  end
  
  defp should_trigger?(path, events, state) do
    path_matches? = Enum.any?(state.patterns, &Regex.match?(&1, path))
    events_match? = Enum.any?(events, &MapSet.member?(state.events, normalize_event(&1)))
    not_git_internal? = not String.contains?(path, ".git/")
    
    path_matches? and events_match? and not_git_internal?
  end
  
  defp schedule_debounced_trigger(state, path, events) do
    pending = Map.update(state.pending_events, path, events, &(&1 ++ events))
    Process.send_after(self(), {:trigger_debounced, path}, state.debounce_ms)
    %{state | pending_events: pending}
  end
  
  defp trigger_workflow(workflow_id, params) do
    JidoCode.Workflow.Engine.execute(workflow_id, params)
  end
  
  defp via_tuple(id), do: {:via, Registry, {JidoCode.TriggerRegistry, id}}
end
```

### Signal-based trigger (Jido Signal Bus integration)

```elixir
defmodule JidoCode.Workflow.Triggers.Signal do
  @moduledoc """
  Triggers workflows based on Jido Signal Bus events.
  Integrates with the existing Signal system for event-driven workflows.
  """
  use GenServer
  
  alias Jido.Signal.Bus
  
  defstruct [:workflow_id, :patterns, :subscription_ids]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
  end
  
  def init(config) do
    subscription_ids = Enum.map(config.patterns, fn pattern ->
      {:ok, sub_id} = Bus.subscribe(
        :jido_code_bus,
        pattern,
        dispatch: {:pid, target: self()}
      )
      sub_id
    end)
    
    state = %__MODULE__{
      workflow_id: config.workflow_id,
      patterns: config.patterns,
      subscription_ids: subscription_ids
    }
    
    {:ok, state}
  end
  
  def handle_info({:signal, signal}, state) do
    JidoCode.Workflow.Engine.execute(state.workflow_id, %{
      trigger_type: :signal,
      signal_type: signal.type,
      signal_data: signal.data,
      signal_source: signal.source,
      signal_id: signal.id
    })
    
    {:noreply, state}
  end
  
  def terminate(_reason, state) do
    Enum.each(state.subscription_ids, fn sub_id ->
      Bus.unsubscribe(:jido_code_bus, sub_id)
    end)
    :ok
  end
  
  defp via_tuple(id), do: {:via, Registry, {JidoCode.TriggerRegistry, id}}
end
```

### Scheduled trigger (Quantum integration)

```elixir
defmodule JidoCode.Workflow.Triggers.Scheduled do
  @moduledoc """
  Cron-based workflow scheduling using Quantum.
  """
  use GenServer
  
  defstruct [:workflow_id, :schedule, :job_name, :params]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
  end
  
  def init(config) do
    job_name = String.to_atom("workflow_#{config.workflow_id}_#{config.id}")
    
    job = %Quantum.Job{
      name: job_name,
      schedule: parse_schedule(config.schedule),
      task: {__MODULE__, :trigger_workflow, [config.workflow_id, config.params || %{}]},
      overlap: false
    }
    
    JidoCode.Scheduler.add_job(job)
    
    state = %__MODULE__{
      workflow_id: config.workflow_id,
      schedule: config.schedule,
      job_name: job_name,
      params: config.params || %{}
    }
    
    {:ok, state}
  end
  
  def trigger_workflow(workflow_id, params) do
    JidoCode.Workflow.Engine.execute(workflow_id, Map.merge(params, %{
      trigger_type: :scheduled,
      triggered_at: DateTime.utc_now()
    }))
  end
  
  def terminate(_reason, state) do
    JidoCode.Scheduler.delete_job(state.job_name)
    :ok
  end
  
  defp parse_schedule(schedule) when is_binary(schedule) do
    Crontab.CronExpression.Parser.parse!(schedule)
  end
  
  defp via_tuple(id), do: {:via, Registry, {JidoCode.TriggerRegistry, id}}
end
```

### Git hook trigger

```elixir
defmodule JidoCode.Workflow.Triggers.GitHook do
  @moduledoc """
  Triggers workflows on git events (commit, push, merge).
  Watches .git directory and/or receives webhook notifications.
  """
  use GenServer
  
  defstruct [:workflow_id, :events, :repo_path, :watcher_pid]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
  end
  
  def init(config) do
    repo_path = config[:repo_path] || File.cwd!()
    git_path = Path.join(repo_path, ".git")
    
    # Watch refs for branch updates (push, commit)
    watch_paths = [
      Path.join(git_path, "refs/heads"),
      Path.join(git_path, "COMMIT_EDITMSG"),
      Path.join(git_path, "MERGE_HEAD")
    ] |> Enum.filter(&File.exists?/1)
    
    {:ok, watcher_pid} = FileSystem.start_link(dirs: watch_paths)
    FileSystem.subscribe(watcher_pid)
    
    state = %__MODULE__{
      workflow_id: config.workflow_id,
      events: MapSet.new(config.events || [:commit, :push]),
      repo_path: repo_path,
      watcher_pid: watcher_pid
    }
    
    {:ok, state}
  end
  
  def handle_info({:file_event, _pid, {path, events}}, state) do
    git_event = detect_git_event(path, events, state.repo_path)
    
    if git_event && MapSet.member?(state.events, git_event) do
      JidoCode.Workflow.Engine.execute(state.workflow_id, %{
        trigger_type: :git_hook,
        git_event: git_event,
        branch: get_current_branch(state.repo_path),
        commit: get_head_commit(state.repo_path)
      })
    end
    
    {:noreply, state}
  end
  
  defp detect_git_event(path, _events, repo_path) do
    cond do
      String.contains?(path, "refs/heads") -> :push
      String.contains?(path, "COMMIT_EDITMSG") -> :commit
      String.contains?(path, "MERGE_HEAD") -> :merge
      true -> nil
    end
  end
  
  defp get_current_branch(repo_path) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"], cd: repo_path) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  end
  
  defp get_head_commit(repo_path) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: repo_path) do
      {commit, 0} -> String.trim(commit)
      _ -> "unknown"
    end
  end
  
  defp via_tuple(id), do: {:via, Registry, {JidoCode.TriggerRegistry, id}}
end
```

### Manual trigger (slash commands)

```elixir
defmodule JidoCode.Workflow.Triggers.Manual do
  @moduledoc """
  Handles manual workflow triggers via slash commands.
  Integrates with JidoCode TUI command system.
  """
  use GenServer
  
  defstruct [:workflow_id, :command, :params_schema]
  
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.id))
  end
  
  def init(config) do
    command = config.command || "/workflow:#{config.workflow_id}"
    
    # Register command with TUI command handler
    JidoCode.Commands.register(command, __MODULE__, :handle_command, config)
    
    state = %__MODULE__{
      workflow_id: config.workflow_id,
      command: command,
      params_schema: config[:params_schema] || []
    }
    
    {:ok, state}
  end
  
  def handle_command(args, config) do
    params = parse_command_args(args, config.params_schema)
    
    JidoCode.Workflow.Engine.execute(config.workflow_id, Map.merge(params, %{
      trigger_type: :manual,
      triggered_by: :command
    }))
  end
  
  defp via_tuple(id), do: {:via, Registry, {JidoCode.TriggerRegistry, id}}
end
```

---

## Agent lifecycle within workflows

### Pre/post action execution

```elixir
defmodule JidoCode.Workflow.AgentLifecycle do
  @moduledoc """
  Manages agent lifecycle hooks within workflow execution.
  Handles pre-actions, post-actions, and mode-specific execution.
  """
  
  @doc """
  Executes pre-actions before agent step runs.
  Returns merged results to pass to agent.
  """
  def run_pre_actions([], _arguments), do: {:ok, %{}}
  
  def run_pre_actions(pre_actions, arguments) do
    Enum.reduce_while(pre_actions, {:ok, %{}}, fn action_config, {:ok, acc} ->
      resolved_inputs = resolve_action_inputs(action_config.inputs, arguments, acc)
      
      case execute_action(action_config.module, resolved_inputs) do
        {:ok, result} -> {:cont, {:ok, Map.merge(acc, result)}}
        {:error, reason} -> {:halt, {:error, {:pre_action_failed, action_config.module, reason}}}
      end
    end)
  end
  
  @doc """
  Executes post-actions after agent step completes.
  Transforms or enriches agent output.
  """
  def run_post_actions([], agent_result), do: {:ok, agent_result}
  
  def run_post_actions(post_actions, agent_result) do
    Enum.reduce_while(post_actions, {:ok, agent_result}, fn action_config, {:ok, acc} ->
      resolved_inputs = resolve_action_inputs(action_config.inputs, %{}, acc)
      
      case execute_action(action_config.module, resolved_inputs) do
        {:ok, result} -> {:cont, {:ok, Map.merge(acc, result)}}
        {:error, reason} -> {:halt, {:error, {:post_action_failed, action_config.module, reason}}}
      end
    end)
  end
  
  defp execute_action(module, inputs) when is_atom(module) do
    module.run(inputs, %{})
  end
  
  defp resolve_action_inputs(inputs, arguments, context) do
    Enum.into(inputs, %{}, fn {key, value} ->
      resolved = case value do
        "`result:" <> ref -> get_in(context, parse_path(ref))
        "`arg:" <> ref -> Map.get(arguments, String.to_atom(ref))
        other -> other
      end
      {key, resolved}
    end)
  end
end
```

### Agent execution modes

```elixir
defmodule JidoCode.Workflow.AgentExecutor do
  @moduledoc """
  Handles different agent execution modes within workflows.
  """
  
  @doc """
  Synchronous execution - workflow blocks until agent completes.
  """
  def execute_sync(agent_pid, instruction, timeout) do
    case Jido.Agent.Runtime.cmd(agent_pid, instruction.action, instruction.params, timeout: timeout) do
      {:ok, result} -> {:ok, result}
      {:error, :timeout} -> {:error, {:agent_timeout, timeout}}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Asynchronous execution with callback signal.
  Workflow can continue or wait at sync points.
  """
  def execute_async(agent_pid, instruction, callback_config) do
    task_id = generate_task_id()
    
    :ok = Jido.Agent.Runtime.cmd_async(agent_pid, instruction.action, 
      Map.put(instruction.params, :__task_id__, task_id)
    )
    
    # Register callback handler if specified
    if callback_config[:signal] do
      register_callback_handler(task_id, callback_config)
    end
    
    {:ok, %{task_id: task_id, status: :running}}
  end
  
  @doc """
  Waits for async agent at a sync point.
  """
  def await_async(task_id, timeout \\ 60_000) do
    receive do
      {:agent_complete, ^task_id, result} -> {:ok, result}
      {:agent_error, ^task_id, error} -> {:error, error}
    after
      timeout -> {:error, {:async_timeout, task_id}}
    end
  end
  
  defp register_callback_handler(task_id, config) do
    # Subscribe to callback signal
    Jido.Signal.Bus.subscribe(:jido_code_bus, config.signal, 
      dispatch: {:pid, target: self()},
      metadata: %{task_id: task_id}
    )
  end
end
```

---

## Phoenix channel integration

### Workflow channel for real-time updates

```elixir
defmodule JidoCodeWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for real-time workflow state updates.
  Broadcasts step progress, agent states, and workflow completion.
  """
  use JidoCodeWeb, :channel
  
  alias JidoCode.Workflow.{Engine, Registry}
  
  def join("workflow:" <> workflow_id, _params, socket) do
    # Subscribe to workflow-specific events
    Phoenix.PubSub.subscribe(JidoCode.PubSub, "workflow:#{workflow_id}")
    
    # Get current workflow state if running
    state = case Registry.get_run_state(workflow_id) do
      {:ok, state} -> state
      {:error, :not_found} -> %{status: :idle}
    end
    
    {:ok, %{status: state.status, workflow_id: workflow_id}, 
     assign(socket, :workflow_id, workflow_id)}
  end
  
  # Client commands
  def handle_in("start", params, socket) do
    case Engine.execute(socket.assigns.workflow_id, params) do
      {:ok, run_id} -> 
        {:reply, {:ok, %{run_id: run_id}}, socket}
      {:error, reason} -> 
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end
  
  def handle_in("pause", %{"run_id" => run_id}, socket) do
    Engine.pause(run_id)
    {:reply, :ok, socket}
  end
  
  def handle_in("resume", %{"run_id" => run_id}, socket) do
    Engine.resume(run_id)
    {:reply, :ok, socket}
  end
  
  def handle_in("cancel", %{"run_id" => run_id}, socket) do
    Engine.cancel(run_id)
    {:reply, :ok, socket}
  end
  
  # Broadcast handlers from PubSub
  def handle_info({:workflow_event, event}, socket) do
    push(socket, event.type, event.payload)
    {:noreply, socket}
  end
end
```

### Workflow broadcaster module

```elixir
defmodule JidoCode.Workflow.Broadcaster do
  @moduledoc """
  Broadcasts workflow events to configured channels.
  Integrates with Phoenix PubSub and Jido Signal Bus.
  """
  
  @pubsub JidoCode.PubSub
  
  def broadcast_step_started(workflow_id, run_id, step) do
    broadcast(workflow_id, %{
      type: "step:started",
      payload: %{
        run_id: run_id,
        step_name: step.name,
        step_type: step.type,
        started_at: DateTime.utc_now()
      }
    })
  end
  
  def broadcast_step_completed(workflow_id, run_id, step, result) do
    broadcast(workflow_id, %{
      type: "step:completed",
      payload: %{
        run_id: run_id,
        step_name: step.name,
        duration_ms: calculate_duration(step),
        result_preview: preview_result(result),
        completed_at: DateTime.utc_now()
      }
    })
  end
  
  def broadcast_step_failed(workflow_id, run_id, step, error) do
    broadcast(workflow_id, %{
      type: "step:failed",
      payload: %{
        run_id: run_id,
        step_name: step.name,
        error: format_error(error),
        failed_at: DateTime.utc_now()
      }
    })
  end
  
  def broadcast_agent_state(workflow_id, run_id, agent_name, state) do
    broadcast(workflow_id, %{
      type: "agent:state",
      payload: %{
        run_id: run_id,
        agent: agent_name,
        state: sanitize_agent_state(state),
        timestamp: DateTime.utc_now()
      }
    })
  end
  
  def broadcast_workflow_complete(workflow_id, run_id, status, result) do
    broadcast(workflow_id, %{
      type: "workflow:complete",
      payload: %{
        run_id: run_id,
        status: status,
        result_preview: preview_result(result),
        completed_at: DateTime.utc_now()
      }
    })
    
    # Also emit signal for other systems
    emit_completion_signal(workflow_id, run_id, status, result)
  end
  
  defp broadcast(workflow_id, event) do
    # Phoenix PubSub for channels
    Phoenix.PubSub.broadcast(@pubsub, "workflow:#{workflow_id}", {:workflow_event, event})
    
    # Also broadcast to TUI
    JidoCode.TUI.notify(:workflow_event, event)
  end
  
  defp emit_completion_signal(workflow_id, run_id, status, result) do
    {:ok, signal} = Jido.Signal.new(
      "workflow.#{workflow_id}.completed",
      %{run_id: run_id, status: status, result: result},
      source: "/jidocode/workflows"
    )
    Jido.Signal.Bus.publish(:jido_code_bus, [signal])
  end
end
```

---

## Workflow engine core

```elixir
defmodule JidoCode.Workflow.Engine do
  @moduledoc """
  Core workflow execution engine.
  Coordinates Reactor execution with triggers, broadcasting, and lifecycle management.
  """
  use GenServer
  
  alias JidoCode.Workflow.{Compiler, Broadcaster, Registry}
  
  defstruct [:workflow_id, :reactor, :run_id, :status, :context, :started_at]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Executes a workflow with given inputs.
  """
  def execute(workflow_id, inputs) do
    GenServer.call(__MODULE__, {:execute, workflow_id, inputs})
  end
  
  def pause(run_id), do: GenServer.call(__MODULE__, {:pause, run_id})
  def resume(run_id), do: GenServer.call(__MODULE__, {:resume, run_id})
  def cancel(run_id), do: GenServer.call(__MODULE__, {:cancel, run_id})
  
  @impl true
  def init(_opts) do
    {:ok, %{runs: %{}}}
  end
  
  @impl true
  def handle_call({:execute, workflow_id, inputs}, _from, state) do
    with {:ok, definition} <- Registry.get_workflow(workflow_id),
         {:ok, reactor} <- Compiler.compile(definition),
         run_id <- generate_run_id() do
      
      # Start async execution
      task = Task.async(fn -> 
        execute_reactor(reactor, inputs, workflow_id, run_id, definition.settings)
      end)
      
      run_state = %{
        workflow_id: workflow_id,
        run_id: run_id,
        task: task,
        status: :running,
        started_at: DateTime.utc_now()
      }
      
      Broadcaster.broadcast_step_started(workflow_id, run_id, %{name: :workflow, type: :workflow})
      
      {:reply, {:ok, run_id}, put_in(state, [:runs, run_id], run_state)}
    else
      error -> {:reply, error, state}
    end
  end
  
  defp execute_reactor(reactor, inputs, workflow_id, run_id, settings) do
    options = [
      max_concurrency: settings[:max_concurrency] || System.schedulers_online(),
      timeout: settings[:timeout_ms] || :infinity,
      async?: true
    ]
    
    # Inject broadcast middleware
    context = %{
      workflow_id: workflow_id,
      run_id: run_id,
      broadcast_fn: &Broadcaster.broadcast_step_completed/4
    }
    
    case Reactor.run(reactor, inputs, context, options) do
      {:ok, result} ->
        Broadcaster.broadcast_workflow_complete(workflow_id, run_id, :completed, result)
        {:ok, result}
        
      {:error, reason} ->
        Broadcaster.broadcast_workflow_complete(workflow_id, run_id, :failed, reason)
        {:error, reason}
        
      {:halted, halted_reactor} ->
        Broadcaster.broadcast_workflow_complete(workflow_id, run_id, :halted, nil)
        {:halted, halted_reactor}
    end
  end
  
  defp generate_run_id do
    "run_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
```

---

## JSON schemas for configuration

### Workflow definition schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "JidoCode Workflow Definition",
  "type": "object",
  "required": ["name", "version"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9_]*$",
      "description": "Unique workflow identifier"
    },
    "version": {
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+$"
    },
    "description": {"type": "string"},
    "enabled": {"type": "boolean", "default": true},
    "inputs": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "type"],
        "properties": {
          "name": {"type": "string"},
          "type": {"enum": ["string", "integer", "boolean", "map", "list"]},
          "required": {"type": "boolean", "default": false},
          "default": {},
          "description": {"type": "string"}
        }
      }
    },
    "triggers": {
      "type": "array",
      "items": {"$ref": "#/definitions/trigger"}
    },
    "settings": {
      "type": "object",
      "properties": {
        "max_concurrency": {"type": "integer", "minimum": 1, "maximum": 100},
        "timeout_ms": {"type": "integer", "minimum": 1000},
        "retry_policy": {
          "type": "object",
          "properties": {
            "max_retries": {"type": "integer", "minimum": 0},
            "backoff": {"enum": ["linear", "exponential", "constant"]},
            "base_delay_ms": {"type": "integer"}
          }
        },
        "on_failure": {"enum": ["compensate", "halt", "continue"]}
      }
    },
    "channel": {
      "type": "object",
      "properties": {
        "topic": {"type": "string"},
        "broadcast_events": {
          "type": "array",
          "items": {"enum": ["step_started", "step_completed", "step_failed", "workflow_complete", "agent_state"]}
        }
      }
    }
  },
  "definitions": {
    "trigger": {
      "type": "object",
      "required": ["type"],
      "properties": {
        "type": {"enum": ["file_system", "git_hook", "signal", "scheduled", "manual"]},
        "patterns": {"type": "array", "items": {"type": "string"}},
        "events": {"type": "array", "items": {"type": "string"}},
        "schedule": {"type": "string"},
        "command": {"type": "string"},
        "debounce_ms": {"type": "integer"}
      }
    },
    "step": {
      "type": "object",
      "required": ["type"],
      "oneOf": [
        {"$ref": "#/definitions/action_step"},
        {"$ref": "#/definitions/agent_step"},
        {"$ref": "#/definitions/sub_workflow_step"}
      ]
    },
    "action_step": {
      "type": "object",
      "required": ["type", "module"],
      "properties": {
        "type": {"const": "action"},
        "module": {"type": "string"},
        "inputs": {"type": "object"},
        "outputs": {"type": "array", "items": {"type": "string"}},
        "depends_on": {"type": "array", "items": {"type": "string"}},
        "async": {"type": "boolean"},
        "optional": {"type": "boolean"},
        "max_retries": {"type": "integer"}
      }
    },
    "agent_step": {
      "type": "object",
      "required": ["type", "agent"],
      "properties": {
        "type": {"const": "agent"},
        "agent": {"type": "string"},
        "inputs": {"type": "object"},
        "depends_on": {"type": "array", "items": {"type": "string"}},
        "mode": {"enum": ["sync", "async"]},
        "timeout_ms": {"type": "integer"},
        "pre_actions": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["module"],
            "properties": {
              "module": {"type": "string"},
              "inputs": {"type": "object"}
            }
          }
        },
        "post_actions": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["module"],
            "properties": {
              "module": {"type": "string"},
              "inputs": {"type": "object"}
            }
          }
        }
      }
    },
    "sub_workflow_step": {
      "type": "object",
      "required": ["type", "workflow"],
      "properties": {
        "type": {"const": "sub_workflow"},
        "workflow": {"type": "string"},
        "inputs": {"type": "object"},
        "depends_on": {"type": "array", "items": {"type": "string"}},
        "condition": {"type": "string"},
        "parallel": {"type": "boolean"}
      }
    }
  }
}
```

### Triggers configuration schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "JidoCode Triggers Configuration",
  "type": "object",
  "properties": {
    "global_settings": {
      "type": "object",
      "properties": {
        "default_debounce_ms": {"type": "integer", "default": 500},
        "max_concurrent_triggers": {"type": "integer", "default": 10}
      }
    },
    "triggers": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "workflow_id", "type"],
        "properties": {
          "id": {"type": "string"},
          "workflow_id": {"type": "string"},
          "type": {"enum": ["file_system", "git_hook", "signal", "scheduled", "manual"]},
          "enabled": {"type": "boolean", "default": true},
          "config": {"type": "object"}
        }
      }
    }
  }
}
```

---

## Directory structure

```
.jido_code/
├── workflows/
│   ├── code_review.md          # Workflow definitions
│   ├── test_runner.md
│   ├── deploy_preview.md
│   └── triggers.json           # Global trigger configurations
├── agents/
│   ├── code_reviewer.md        # Agent definitions
│   ├── security_analyzer.md
│   └── suggestion_generator.md
├── skills/
│   ├── elixir_analysis.md      # Skill definitions
│   └── git_operations.md
├── actions/
│   └── custom_actions.ex       # Custom action modules
└── config.json                 # Global JidoCode configuration
```

---

## Integration with existing extensibility system

### Hooks integration

```elixir
defmodule JidoCode.Workflow.HooksIntegration do
  @moduledoc """
  Integrates workflow events with JidoCode's hook system.
  """
  
  def emit_workflow_hooks(event_type, payload) do
    case event_type do
      :workflow_started ->
        JidoCode.Hooks.run(:before_workflow, payload)
        
      :step_before_execute ->
        JidoCode.Hooks.run(:before_workflow_step, payload)
        
      :step_after_execute ->
        JidoCode.Hooks.run(:after_workflow_step, payload)
        
      :workflow_completed ->
        JidoCode.Hooks.run(:after_workflow, payload)
    end
  end
end
```

### Skills as workflow components

```elixir
defmodule JidoCode.Workflow.SkillStep do
  @moduledoc """
  Allows Skills to be used as workflow steps.
  """
  use Reactor.Step
  
  @impl true
  def run(arguments, context, options) do
    skill_module = Keyword.fetch!(options, :skill)
    
    # Skills can handle signals and produce outputs
    case skill_module.handle_workflow_step(arguments, context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Plugin workflow extensions

```elixir
defmodule JidoCode.Workflow.PluginExtensions do
  @moduledoc """
  Allows plugins to register custom step types and triggers.
  """
  
  def register_step_type(type_name, step_module) do
    JidoCode.Workflow.StepRegistry.register(type_name, step_module)
  end
  
  def register_trigger_type(type_name, trigger_module) do
    JidoCode.Workflow.TriggerRegistry.register(type_name, trigger_module)
  end
end
```

---

## Key design decisions

**Reactor over custom DAG implementation**: Reactor provides battle-tested saga patterns with retry, compensation, and undo capabilities. Its Builder API allows complete runtime workflow construction from parsed markdown, eliminating the need for compile-time DSL macros.

**Markdown-based definitions**: Following the existing JidoCode pattern for agents and skills, markdown provides human-readable workflow definitions with YAML frontmatter for structured configuration. This enables version control, documentation, and easy editing.

**Actions vs Agents distinction**: Actions are deterministic Jido.Action modules for data transformation and API calls. Agents are LLM-powered steps with pre/post action hooks, supporting both synchronous blocking and asynchronous callback patterns.

**Signal Bus for triggers**: Leveraging Jido's existing CloudEvents-based Signal Bus provides a unified event system. File system, git, and scheduled triggers all emit signals that can be routed to workflows, enabling complex event-driven orchestration.

**Phoenix Channels for real-time updates**: Each workflow run broadcasts progress to its configured channel topic, enabling TUI updates and external integrations to observe workflow execution in real-time.

This design creates a powerful, extensible workflow orchestration system that integrates deeply with JidoCode's existing architecture while leveraging Reactor's robust execution engine for reliable DAG processing.
