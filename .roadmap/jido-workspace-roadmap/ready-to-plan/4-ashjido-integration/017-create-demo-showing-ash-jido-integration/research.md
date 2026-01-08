# Research: Create Demo Showing Ash + Jido Integration

## Item Overview

**ID**: 017-create-demo-showing-ash-jido-integration
**Title**: Create demo showing Ash + Jido integration strategy
**Goal**: Build a runnable end-to-end demo showcasing how to use Ash resources with Jido agents

## Key Findings

### AshJido Integration Status

The `ash_jido` project (`projects/ash_jido/`) is **complete and functional** but has:
- No demo application
- No end-to-end example for users
- Test examples but no production-ready demo

### Integration Architecture

**AshJido** is an Ash Framework extension that automatically generates `Jido.Action` modules from Ash Resource actions through:

1. **Compile-time generation** via Spark transformers
2. **Type mapping** from Ash types to NimbleOptions schemas
3. **Policy integration** respecting Ash authorization
4. **Context-based execution** requiring domain/actor/tenant

### How Ash Resources Become Jido Tools

```elixir
# 1. Define Ash Resource with AshJido extension
defmodule MyApp.Task do
  use Ash.Resource,
    extensions: [AshJido],
    domain: MyApp.Domain

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false)
    attribute(:description, :string)
    attribute(:status, :atom, default: :pending)
    timestamps()
  end

  actions do
    create :create
    read :read
    update :update
    destroy :destroy
  end

  jido do
    action :create
    action :read
    action :update
    action :destroy
  end
end

# 2. This generates: MyApp.Task.Jido.Create, .Read, .Update, .Destroy
# 3. These implement Jido.Action behavior with proper schemas
# 4. Can be used directly or attached to agents via skills
```

## Files Identified

### Core AshJido Files (Reference for Demo)

| File | Purpose |
|------|---------|
| `projects/ash_jido/lib/ash_jido.ex` | Main entry point |
| `projects/ash_jido/lib/ash_jido/generator.ex` | Generates Jido.Action modules |
| `projects/ash_jido/lib/ash_jido/mapper.ex` | Result conversion |
| `projects/ash_jido/lib/ash_jido/type_mapper.ex` | Type mappings |
| `projects/ash_jido/lib/ash_jido/resource/dsl.ex` | DSL definition |
| `projects/ash_jido/lib/ash_jido/resource/transformers/generate_jido_actions.ex` | Spark transformer |

### Test Support Files (Can Model Demo After)

| File | Purpose |
|------|---------|
| `projects/ash_jido/test/support/test_user.ex` | Example User resource |
| `projects/ash_jido/test/support/test_post.ex` | Example Post resource |
| `projects/ash_jido/test/support/test_domain.ex` | Example Domain |
| `projects/ash_jido/test/integration/ash_jido_integration_test.exs` | Integration examples |

### Agent Pattern Files (For Jido Agent Demo)

| File | Purpose |
|------|---------|
| `projects/jido_ai/lib/jido_ai/examples/react_demo_agent.ex` | ReAct AI agent pattern |
| `projects/jido/lib/jido/agent.ex` | Core Agent behavior |
| `projects/jido/lib/jido/skill.ex` | Skill behavior |
| `projects/jido/examples/code_mapper/agents/root_coordinator.ex` | Basic agent example |

### Documentation Files

| File | Purpose |
|------|---------|
| `projects/ash_jido/README.md` | Quick start guide |
| `projects/ash_jido/usage-rules.md` | Best practices |
| `projects/jido/AGENTS.md` | Agent development guide |

## Recommended Demo Structure

### Option 1: Standalone Mix Project (Recommended)

Create a new demo project at `projects/ash_jido_demo/`:

```
projects/ash_jido_demo/
├── mix.exs
├── README.md
├── config/
│   └── config.exs
├── lib/
│   ├── application.ex
│   ├── domain.ex                  # Ash domain
│   ├── resources/
│   │   ├── task.ex               # Task resource with AshJido
│   │   └── project.ex            # Project resource with AshJido
│   ├── agents/
│   │   └── task_manager_agent.ex # Jido agent using the tools
│   └── skills/
│       └── task_management.ex    # Skill wrapping Ash actions
└── test/
    └── demo_test.exs             # Runnable demo test
```

### Option 2: Umbrella App Folder

Add to existing workspace as `apps/ash_jido_demo/`

### Option 3: Documentation Example

Add as `projects/ash_jido/examples/demo/`

## Demo Implementation Plan

### 1. Ash Resources to Define

**Task Resource**:
- Attributes: id, title, description, status (atom), priority, project_id, timestamps
- Actions: create, read, by_status, update_status, mark_complete, destroy
- Jido config: Expose key actions with AI-friendly names

**Project Resource**:
- Attributes: id, name, description, status, timestamps
- Actions: create, read, update, destroy
- Jido config: Use `all_actions` for simplicity

### 2. Domain Configuration

```elixir
defmodule AshJidoDemo.Domain do
  use Ash.Domain

  resources do
    resource AshJidoDemo.Task
    resource AshJidoDemo.Project
  end
end
```

### 3. Jido Skill to Wrap Actions

```elixir
defmodule AshJidoDemo.Skills.TaskManagement do
  use Jido.Skill,
    name: "task_management",
    state_key: :tasks,
    actions: [
      AshJidoDemo.Task.Jido.Create,
      AshJidoDemo.Task.Jido.Read,
      AshJidoDemo.Task.Jido.ByStatus,
      AshJidoDemo.Task.Jido.UpdateStatus,
      AshJidoDemo.Task.Jido.MarkComplete,
      AshJidoDemo.Project.Jido.Create,
      AshJidoDemo.Project.Jido.Read
    ],
    description: "Task and project management capabilities"

  def mount(_agent, _config) do
    {:ok, %{domain: AshJidoDemo.Domain}}
  end
end
```

### 4. Jido Agent Using the Skill

```elixir
defmodule AshJidoDemo.Agents.TaskManager do
  use Jido.AI.ReActAgent,
    name: "task_manager",
    description: "Manages tasks and projects using Ash resources",
    tools: [
      # Direct tool references
      AshJidoDemo.Task.Jido.Create,
      AshJidoDemo.Task.Jido.Read,
      AshJidoDemo.Task.Jido.MarkComplete
    ],
    max_iterations: 10
end
```

### 5. Runnable Demo Script

```elixir
defmodule AshJidoDemo.Demo do
  @moduledoc """
  Run with: mix run -e "AshJidoDemo.Demo.run()"
  """

  def run do
    # Start the agent
    {:ok, pid} = Jido.AgentServer.start(agent: AshJidoDemo.Agents.TaskManager)

    # Create a task via the agent
    AshJidoDemo.Agents.TaskManager.ask(pid, "Create a task to review the AshJido demo")

    # List tasks
    AshJidoDemo.Agents.TaskManager.ask(pid, "Show me all pending tasks")

    # Mark complete
    AshJidoDemo.Agents.TaskManager.ask(pid, "Mark the review task as complete")
  end
end
```

## Key Integration Points

### 1. Context Requirements

All Ash-generated Jido actions require context with:
- `domain:` - Required Ash domain
- `actor:` - Optional, for authorization
- `tenant:` - Optional, for multi-tenancy

**Solution**: Mount skill with default context or pass via agent state.

### 2. Type Mappings to Document

| Ash Type | NimbleOptions Type |
|----------|-------------------|
| Ash.Type.String | :string |
| Ash.Type.Integer | :integer |
| Ash.Type.Decimal | :float |
| Ash.Type.Boolean | :boolean |
| Ash.Type.Date | :string |
| {:array, type} | {:list, mapped_type} |

### 3. Best Practices to Showcase

1. **Action Naming**: Use `name:` option for AI-friendly names
2. **Tagging**: Use `tags:` for categorization
3. **Filtering**: Use `except:` for sensitive actions
4. **Descriptions**: Add clear descriptions for LLM understanding
5. **Error Handling**: Show Ash error → Jido error conversion

### 4. LLM Optimization Tips

- Use verb-first names: `create_task`, `mark_complete`, `list_tasks`
- Add domain tags: `["task-management", "project-management"]`
- Include comprehensive descriptions
- Group related actions in skills

## Documentation Structure

The demo README should include:

1. **Quick Start** - Run the demo in 3 steps
2. **Architecture** - How Ash + Jido integrate
3. **Resource Definition** - Defining Ash resources with AshJido
4. **Agent Setup** - Creating agents with Ash tools
5. **Execution Patterns** - Different ways to invoke actions
6. **Best Practices** - Naming, tagging, security
7. **Testing** - Running the test suite
8. **Extension Guide** - Adding custom resources

## Dependencies

### Required

```elixir
{:ash, "~> 3.0"},
{:jido, "~> 0.2"},  # or path dependency
{:ash_jido, path: "../ash_jido"}
```

### Optional for Demo

```elixir
{:jido_ai, "~> 0.1"}  # For ReAct agents
```

## Test Strategy

Create runnable tests demonstrating:

1. Direct action execution: `Task.Jido.Create.run(params, context)`
2. Agent with skills: Attach skill, invoke actions
3. ReAct agent: LLM-powered task management
4. Error handling: Validation, authorization failures
5. Read actions: Pagination, filtering

## Success Criteria

The demo should enable users to:

1. Understand how Ash resources become Jido tools
2. Copy patterns for their own resources
3. Run a working example locally
4. Extend the demo with custom resources
5. Integrate with their existing Ash apps

## Next Steps

1. Create demo project structure
2. Define Ash resources (Task, Project)
3. Set up Ash domain
4. Create Jido skill wrapping actions
5. Build demo agent
6. Write README documentation
7. Add runnable demo script
8. Create test suite
