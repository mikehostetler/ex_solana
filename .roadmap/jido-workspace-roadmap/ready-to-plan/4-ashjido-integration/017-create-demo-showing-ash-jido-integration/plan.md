# Implementation Plan: Ash + Jido Integration Demo

**Item ID**: 017-create-demo-showing-ash-jido-integration
**Status**: Planned
**Estimated Effort**: Medium (3-4 phases)

---

## 1. Executive Summary

This implementation plan creates a comprehensive, runnable demo showcasing the integration between Ash Framework resources and Jido agents via the `ash_jido` extension. The demo will be implemented as a standalone Mix project at `projects/ash_jido_demo/` containing two Ash resources (Task and Project), a Jido skill wrapping the generated actions, and a ReAct agent demonstrating LLM-powered task management. The deliverable includes a production-ready reference implementation with extensive README documentation, runnable demo scripts, and a complete test suite. The demo serves as the primary onboarding reference for developers building Ash + Jido applications.

**Key Architectural Decisions**:
- Standalone Mix project (not umbrella app) for easier isolation and copying
- Two resources demonstrating both simple and advanced AshJido patterns
- ReAct agent pattern showing LLM-powered workflow
- Comprehensive documentation covering quick start through extension

**Target Audience**: Developers familiar with Ash who want to add AI agent capabilities, and developers familiar with Jido who want to leverage Ash resources.

---

## 2. Impact Analysis Summary

### Research Findings Reference

The research phase (`projects/ash_jido/test/support/`) identified that `ash_jido` is fully functional but lacks:
- Demo application for users to study
- End-to-end examples beyond test files
- Production-ready reference implementation

### Files to Create

**Project Structure** (Phase 1):
- `projects/ash_jido_demo/mix.exs` - Project configuration with dependencies
- `projects/ash_jido_demo/README.md` - Comprehensive documentation
- `projects/ash_jido_demo/config/config.exs` - Ash and Jido configuration
- `projects/ash_jido_demo/lib/application.ex` - Application supervisor
- `projects/ash_jido_demo/lib/domain.ex` - Ash domain declaration

**Resources** (Phase 2):
- `projects/ash_jido_demo/lib/resources/task.ex` - Task resource with custom actions
- `projects/ash_jido_demo/lib/resources/project.ex` - Project resource (simpler pattern)

**Agent Layer** (Phase 3):
- `projects/ash_jido_demo/lib/skills/task_management.ex` - Skill wrapping Ash actions
- `projects/ash_jido_demo/lib/agents/task_manager_agent.ex` - ReAct agent implementation
- `projects/ash_jido_demo/lib/demo.ex` - Runnable demo script

**Tests** (Phase 3):
- `projects/ash_jido_demo/test/demo_test.exs` - End-to-end demo test
- `projects/ash_jido_demo/test/task_management_test.exs` - Skill and agent tests

### Existing Patterns to Follow

**AshJido DSL** (`projects/ash_jido/lib/ash_jido/resource/dsl.ex`):
```elixir
jido do
  action :create
  action :read, name: :list_tasks
  all_actions except: [:destroy]
end
```

**Generated Action Pattern** (`projects/ash_jido/test/support/test_user.ex`):
- Resources implement `use Ash.Resource, extensions: [AshJido]`
- Generated modules: `Resource.Jido.ActionName`
- Implement `Jido.Action` behavior with `run/2` and `schema/0`

**Skill Pattern** (`projects/jido/lib/jido/skill.ex`):
```elixir
use Jido.Skill,
  name: "task_management",
  actions: [...],
  description: "..."

def mount(_agent, _config) do
  {:ok, %{domain: AshJidoDemo.Domain}}
end
```

**ReAct Agent Pattern** (`projects/jido_ai/lib/jido_ai/examples/react_demo_agent.ex`):
```elixir
use Jido.AI.ReActAgent,
  name: "task_manager",
  tools: [...],
  max_iterations: 10
```

### Integration Points Identified

1. **Ash Context Domain**: All actions require `domain:` in context
2. **Error Conversion**: Ash errors automatically convert via `AshJido.Mapper.to_result/2`
3. **Type Mappings**: Documented in `projects/ash_jido/lib/ash_jido/type_mapper.ex`
4. **Authorization**: Can pass `actor:` and `tenant:` via skill mount or agent state

---

## 3. Feature Specification

### User Stories with Acceptance Criteria

**Story 1: Quick Start Experience**
> As a developer new to Ash + Jido, I want to run the demo with one command so I can see the integration in action.

**Acceptance Criteria**:
- `mix ash_jido_demo.run` executes a complete demo workflow
- Output shows: project creation, task creation, listing, status update, completion
- No manual setup beyond `mix deps.get`
- Clear success/error messages

**Story 2: Resource Definition Patterns**
> As a developer, I want to see how to define Ash resources that expose Jido actions so I can copy the pattern.

**Acceptance Criteria**:
- Task resource demonstrates: custom actions, selective exposure, AI-friendly naming
- Project resource demonstrates: `all_actions` pattern for simplicity
- README shows code for both patterns with explanations
- Generated action modules are documented

**Story 3: Agent Integration**
> As a developer, I want to see how to use Ash-generated actions in a Jido agent so I can build AI-powered workflows.

**Acceptance Criteria**:
- Demo shows direct action usage (without agent)
- Demo shows skill-based usage (actions attached to agent)
- Demo shows ReAct agent (LLM chooses actions)
- README explains when to use each pattern

**Story 4: Context and Authorization**
> As a developer, I want to understand how to pass domain, actor, and tenant so my actions work correctly.

**Acceptance Criteria**:
- Skill mount pattern demonstrates default context
- README documents context requirements
- Example shows passing actor for authorization
- Error handling shown for missing domain

**Story 5: Extension Guide**
> As a developer, I want to add my own resources to the demo so I can learn by extending it.

**Acceptance Criteria**:
- README has "Adding Resources" section
- Checklist for resource definition
- Example of custom action with parameters
- Testing guidance for new resources

### API Contracts and Data Flow

**Direct Action Execution**:
```elixir
# Input
params = %{title: "Review demo", description: "Check the AshJido integration"}
context = %{domain: AshJidoDemo.Domain}

# Output
{:ok, %AshJidoDemo.Task{id: ..., title: "Review demo", status: :pending}}
# or
{:error, %Jido.Error{reason: :validation_error, ...}}
```

**Skill-Based Execution**:
```elixir
# Attach skill to agent
Jido.Agent.add_skill(agent, AshJidoDemo.Skills.TaskManagement)

# Execute via agent
Jido.Agent.execute(agent, AshJidoDemo.Task.Jido.Create, params)
```

**ReAct Agent Execution**:
```elixir
# Natural language input
AshJidoDemo.Agents.TaskManager.ask(agent_pid, "Create a task to review the AshJido demo")

# Agent: 1) Thinks, 2) Selects Create action, 3) Executes, 4) Returns result
{:ok, %Jido.AI.Response{content: "Created task 'Review demo' with ID ...", ...}}
```

### State Management Requirements

**Agent State** (managed by `Jido.AgentServer`):
- Current task list (for context in LLM prompts)
- Last operation result
- Skill-mounted domain reference

**Ash State** (managed by Ash's data layer):
- In-memory for demo (no database required)
- Could be Postgres/SQLite via configuration

**No Additional State Required**: Demo is stateless between runs

### Error Handling Approach

**Ash Validation Errors**:
- Converted by `AshJido.Mapper` to `Jido.Error`
- Preserved validation details in `reason` field
- Returned as `{:error, error_struct}`

**Authorization Failures**:
- Returned as `Jido.Error` with `:forbidden` reason
- Documented in README

**Missing Context**:
- Clear error: "domain is required in context"
- Documented with solution

---

## 4. Technical Design

### Data Model Changes

**No Changes Required**: Demo creates new data structures in isolated project.

**Task Resource Schema**:
```elixir
attributes do
  uuid_primary_key(:id)
  attribute(:title, :string, allow_nil?: false)
  attribute(:description, :string)
  attribute(:status, :atom, default: :pending, constraints: [one_of: [:pending, :in_progress, :completed]])
  attribute(:priority, :atom, default: :normal, constraints: [one_of: [:low, :normal, :high]])
  attribute(:project_id, :uuid)
  timestamps()
end
```

**Project Resource Schema**:
```elixir
attributes do
  uuid_primary_key(:id)
  attribute(:name, :string, allow_nil?: false)
  attribute(:description, :string)
  attribute(:status, :atom, default: :active)
  timestamps()
end
```

### Module Organization

```
AshJidoDemo
├── Application           # OTP application
├── Domain                # Ash domain
├── Resources
│   ├── Task             # Task resource + generated Jido actions
│   └── Project          # Project resource + generated Jido actions
├── Skills
│   └── TaskManagement   # Wraps actions for agent attachment
├── Agents
│   └── TaskManagerAgent # ReAct agent using Ash tools
└── Demo                 # Runnable demo script
```

### Third-Party Integration Details

**Ash 3.x**:
- Provides resource DSL
- Data layer (in-memory for demo)
- Validation and authorization

**Jido 0.2+**:
- Provides `Jido.Action` behavior
- `Jido.Skill` for action grouping
- `Jido.Agent` for execution
- `Jido.AI.ReActAgent` for LLM-powered agents

**AshJido** (path dependency):
- Generates `Jido.Action` modules from Ash resources
- Type mapping between Ash and NimbleOptions
- Result/error conversion

**Optional: Jido.AI 0.1+**:
- ReAct agent implementation
- LLM backend (user provides API key)

### Configuration and Environment Changes

**config/config.exs**:
```elixir
import Config

# Ash configuration
config :ash, :apis, [AshJidoDemo.Domain]

# Ash data layer (in-memory for demo)
config :ash, :data_layer, Ash.DataLayer.Simple

# Jido.AI configuration (optional, for ReAct agent)
config :jido_ai, :backend, Jido.AI.Backends.OpenAI

# Import environment-specific config
import_config "#{config_env()}.exs"
```

**config/dev.exs**, **config/test.exs**:
- API keys for LLM backend (optional for ReAct agent)
- Logging configuration

**No Runtime Environment Variables Required**: Demo works without external configuration (using in-memory data layer).

---

## 5. Implementation Phases

### Phase 1: Foundation

**Objective**: Set up the demo project structure with Ash and Jido dependencies and basic configuration.

**Success Criteria**:
- `mix new` project created at `projects/ash_jido_demo/`
- Dependencies compile successfully
- Basic application starts and stops cleanly
- Ash domain is defined and registered

**Files to Create**:
1. `projects/ash_jido_demo/mix.exs` - Project configuration
2. `projects/ash_jido_demo/config/config.exs` - Ash and Jido config
3. `projects/ash_jido_demo/config/dev.exs` - Development config
4. `projects/ash_jido_demo/config/test.exs` - Test config
5. `projects/ash_jido_demo/lib/application.ex` - OTP app
6. `projects/ash_jido_demo/lib/domain.ex` - Ash domain

**Tests to Add**:
1. `projects/ash_jido_demo/test/test_helper.exs` - Test setup
2. `projects/ash_jido_demo/test/application_test.exs` - App starts successfully

**Dependencies on Other Work**:
- None (all dependencies exist)

**Implementation Checklist**:
- [ ] Create project with `mix new ash_jido_demo --sup`
- [ ] Add Ash, Jido, AshJido to `mix.exs`
- [ ] Configure Ash domain in `config.exs`
- [ ] Create `AshJidoDemo.Application` with domain child spec
- [ ] Verify `iex -S mix` starts application cleanly

---

### Phase 2: Ash Resources with AshJido

**Objective**: Define Task and Project resources demonstrating different AshJido configuration patterns.

**Success Criteria**:
- Task resource compiles with custom actions and selective Jido exposure
- Project resource compiles with `all_actions` pattern
- Generated Jido action modules exist (e.g., `AshJidoDemo.Task.Jido.Create`)
- Actions execute successfully via `run/2`

**Files to Create**:
1. `projects/ash_jido_demo/lib/resources/task.ex` - Task resource
2. `projects/ash_jido_demo/lib/resources/project.ex` - Project resource

**Tests to Add**:
1. `projects/ash_jido_demo/test/resources/task_test.exs` - Task actions work
2. `projects/ash_jido_demo/test/resources/project_test.exs` - Project actions work

**Dependencies on Other Work**:
- Requires Phase 1 (project setup)

**Implementation Checklist**:
- [ ] Create Task resource with attributes (title, description, status, priority, project_id)
- [ ] Add Ash actions: create, read, by_status, update_status, mark_complete, destroy
- [ ] Configure AshJido DSL with selective actions and AI-friendly names
- [ ] Create Project resource with attributes (name, description, status)
- [ ] Add Ash actions: create, read, update, destroy
- [ ] Configure AshJido DSL with `all_actions` pattern
- [ ] Write tests for direct action execution
- [ ] Verify generated modules exist and implement `Jido.Action`

---

### Phase 3: Skills, Agents, and Demo Script

**Objective**: Create the Jido integration layer with skills, agents, and a runnable demo script.

**Success Criteria**:
- TaskManagement skill wraps Ash actions successfully
- ReAct agent uses Ash actions via natural language
- Demo script runs end-to-end workflow
- Tests demonstrate all three execution patterns

**Files to Create**:
1. `projects/ash_jido_demo/lib/skills/task_management.ex` - Skill definition
2. `projects/ash_jido_demo/lib/agents/task_manager_agent.ex` - ReAct agent
3. `projects/ash_jido_demo/lib/demo.ex` - Runnable demo script

**Tests to Add**:
1. `projects/ash_jido_demo/test/skills/task_management_test.exs` - Skill tests
2. `projects/ash_jido_demo/test/demo_test.exs` - End-to-end demo test

**Dependencies on Other Work**:
- Requires Phase 2 (resources with generated actions)

**Implementation Checklist**:
- [ ] Create TaskManagement skill with Ash actions
- [ ] Implement `mount/2` to provide domain context
- [ ] Create ReAct agent with tools referencing Ash actions
- [ ] Write demo script showing: create project, create tasks, list by status, mark complete
- [ ] Add `mix ash_jido_demo.run` task to `mix.exs`
- [ ] Write tests for skill attachment and execution
- [ ] Write test for ReAct agent (may be integration/skip if no API key)
- [ ] Verify demo runs without errors

---

### Phase 4: Documentation and Polish

**Objective**: Create comprehensive README documentation and polish the demo for production-ready reference.

**Success Criteria**:
- README covers all sections (quick start through extension)
- Demo runs without warnings or errors
- Code follows style guidelines
- Examples in README match actual code

**Files to Modify**:
1. `projects/ash_jido_demo/README.md` - Main documentation
2. `projects/ash_jido_demo/mix.exs` - Add demo run task

**Tests to Add**:
- None (documentation phase)

**Dependencies on Other Work**:
- Requires Phase 3 (working demo)

**Implementation Checklist**:
- [ ] Write README sections: Quick Start, Architecture, Resource Definition, Agent Setup, Execution Patterns, Best Practices, Testing, Extension Guide
- [ ] Add code examples to README (verify they match actual code)
- [ ] Add troubleshooting section
- [ ] Add .formatter.exs for consistent formatting
- [ ] Run `mix format` and `mix compile` to verify no warnings
- [ ] Run full test suite
- [ ] Test quick start instructions from scratch
- [ ] Add screenshot or sample output to README

---

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests**:
- Resource actions execute with valid parameters
- Resource actions reject invalid parameters
- Generated action modules implement `Jido.Action` behavior
- Skill mounting provides correct context

**Integration Tests**:
- Direct action execution with context
- Skill-based execution via agent
- Multi-step workflows (create project, create tasks, list, complete)
- Error handling (validation, authorization)

**Property-Based Tests** (Optional):
- Actions maintain data invariants
- Status transitions follow allowed states

**Demo Test**:
- `mix test test/demo_test.exs` runs full workflow
- Verifies each step completes successfully
- Checks final state matches expectations

### Coverage Targets

- **Minimum 80% coverage** for core modules
- **100% coverage** for critical paths (resource actions, skill mount)
- Document any uncovered code with `# cover: ignore`

### Quality Gates Before Completion

- [ ] All tests pass: `mix test`
- [ ] No compilation warnings: `mix compile`
- [ ] Code formatted: `mix format`
- [ ] Linting passes: `mix credo` (if added)
- [ ] Demo runs successfully: `mix ash_jido_demo.run`
- [ ] README quick start verified from scratch
- [ ] No TODO comments without associated issue

---

## 7. Risk Assessment

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| AshJido generates unexpected schemas | High | Low | Test each action individually; verify schema generation |
| ReAct agent requires paid API | Medium | Medium | Provide alternative execution patterns; document API key requirement |
| Context requirements confusing | Medium | High | Extensive documentation with examples; clear error messages |
| Type mapping edge cases | Low | Low | Document known mappings; test complex types |

### Dependency Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Ash version incompatible | High | Low | Pin to tested versions in mix.exs |
| Jido API changes | Medium | Low | Use path dependencies during development |
| AshJido has bugs | High | Low | Report issues; work around in demo if needed |

### Timeline Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Documentation takes longer than expected | Medium | Medium | Start documentation early; reuse existing patterns |
| ReAct agent testing requires API key | Low | High | Make tests skip-able without key; provide mock mode |

---

## 8. Success Criteria

### Measurable Outcomes

1. **Demo Runs Successfully**
   - `mix ash_jido_demo.run` executes without errors
   - Output shows complete workflow execution
   - Takes < 5 seconds to complete

2. **Documentation Complete**
   - README covers all 8 required sections
   - Code examples are accurate and runnable
   - Quick start takes < 5 minutes

3. **Tests Pass**
   - 100% test pass rate
   - Coverage >= 80%
   - CI/CD passes (if applicable)

4. **Code Quality**
   - No compiler warnings
   - Formatted with `mix format`
   - No TODO/FIXME comments without issues

5. **Reusability**
   - User can copy project and add custom resource in < 30 minutes
   - Patterns are clear and consistent
   - Extension guide is comprehensive

### Definition of "Done"

The implementation is complete when:

- [ ] All 4 phases implemented
- [ ] README documents all patterns and examples
- [ ] Demo runs without errors
- [ ] Test suite passes with >= 80% coverage
- [ ] Code is formatted and linted
- [ ] At least one custom resource can be added following the extension guide
- [ ] Item state updated to "planned" in roadmap
- [ ] Progress logged to `ralph/progress.txt`

### Acceptance Testing Approach

1. **Smoke Test**: Run demo from scratch in clean environment
2. **Pattern Verification**: Each README example matches actual code
3. **Extension Test**: Add a custom resource following extension guide
4. **Documentation Review**: Peer review of README for clarity
5. **User Testing**: One other person runs quick start successfully

---

## Appendix: Quick Reference

### Key File Paths

- **Demo Project**: `projects/ash_jido_demo/`
- **AshJido Reference**: `projects/ash_jido/`
- **Agent Examples**: `projects/jido_ai/lib/jido_ai/examples/`
- **Test Patterns**: `projects/ash_jido/test/support/`

### Commands

```bash
# Setup
cd projects/ash_jido_demo
mix deps.get

# Run demo
mix ash_jido_demo.run

# Run tests
mix test

# Format
mix format

# Compile
mix compile
```

### Contact Points

- **AshJido Implementation**: `projects/ash_jido/lib/ash_jido/`
- **Jido.Agent Documentation**: `projects/jido/AGENTS.md`
- **ReAct Agent Pattern**: `projects/jido_ai/lib/jido_ai/examples/react_demo_agent.ex`
