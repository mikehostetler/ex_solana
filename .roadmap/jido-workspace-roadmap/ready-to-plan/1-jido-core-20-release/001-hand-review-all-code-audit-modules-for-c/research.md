# Research: Hand Review All Code - Audit Modules for Correctness, Patterns, Edge Cases

**Item ID**: `001-hand-review-all-code-audit-modules-for-c`
**Roadmap Section**: 1. Jido Core 2.0 Release
**Research Date**: 2026-01-07

---

## Executive Summary

This research documents the scope and approach for a comprehensive, hand-driven code audit of the Jido Core 2.0 module. The audit focuses on validating correctness, consistency, and production readiness across public APIs, internal abstractions, concurrency, error handling, configuration, and boundary conditions.

**Key Finding**: Jido Core 2.0 comprises ~45 modules covering the agent framework, directives, strategies, observability, and built-in actions.

**Scope Notes**:
- `jido_action` - Already audited and complete
- `jido_signal` - Already audited and complete
- `jido_ai` - Being managed separately by Pascal

---

## 1. Project Dependencies Discovered

### Jido Core 2.0 (Target of Audit)

| Project | Version | Location | Purpose |
|---------|---------|----------|---------|
| **jido** | 1.2.0 → 2.0 | `projects/jido/` | Core agent framework with immutable agents, directives, strategies |

### Dependencies (Already Audited)

| Project | Version | Status |
|---------|---------|--------|
| **jido_action** | 1.0.0 | ✅ Audited and complete |
| **jido_signal** | 1.2.0 | ✅ Audited and complete |
| **jido_ai** | 2.0.0 | 🔄 Managed separately by Pascal |

### Key Dependencies (from mix.exs analysis)

**Shared Core Dependencies:**
- `zoi` ~> 0.14 - Schema validation with transformations
- `splode` ~> 0.2.4 - Unified error handling
- `nimble_options` ~> 1.1 - Option parsing and validation
- `telemetry` ~> 1.3 - Application telemetry
- `typed_struct` ~> 0.3.0 - Type-safe struct definitions
- `jason` ~> 1.4 - JSON serialization

**Concurrency & Processes:**
- `fsmx` ~> 0.5 - State machine implementation
- `phoenix_pubsub` - Distributed messaging
- `poolboy` - Connection pooling

**AI Integration:**
- `req_llm` (from GitHub, branch: main) - Universal LLM client

**Testing:**
- ExUnit with custom test helpers (`JidoTest.Case`, `Jido.Action.Test.Case`)
- Mimic for mocking
- StreamData for property-based testing
- ExCoveralls targeting 80-90% coverage

**Quality Tools:**
- Credo - Code consistency
- Dialyxir - Dialyzer for type checking
- Doctor - Documentation coverage

---

## 2. Files Requiring Changes (Audit Scope)

### 2.1 Core Framework: `jido` (~45 modules)

**Primary Abstractions:**
- `lib/jido/agent.ex` - Core agent data structure and `cmd/2` API
- `lib/jido/agent_server.ex` - OTP GenServer runtime for agents
- `lib/jido/agent_pool.ex` - Agent pooling and management
- `lib/jido/skill.ex` - Skill mounting and composition
- `lib/jido/agent/strategy.ex` - Strategy pattern (FSM, HTN, Direct)
- `lib/jido/agent/directive.ex` - Directive definitions (Emit, Spawn, Schedule, Stop, Error)

**State & Schema:**
- `lib/jido/agent/state.ex` - Agent state management
- `lib/jido/agent/schema.ex` - Schema validation via Zoi
- `lib/jido/agent/internal.ex` - Internal agent operations

**Directives:**
- `lib/jido/agent/directive/cron.ex` - Cron scheduling
- `lib/jido/agent/directive/cron_cancel.ex` - Cron cancellation
- `lib/jido/agent/effects.ex` - Effect processing

**Strategies:**
- `lib/jido/agent/strategy/direct.ex` - Direct execution strategy
- `lib/jido/agent/strategy/fsm.ex` - FSM-based strategy
- `lib/jido/agent/strategy/state.ex` - Strategy state management

**AgentServer Components:**
- `lib/jido/agent_server/state.ex` - Server state
- `lib/jido/agent_server/options.ex` - Configuration options
- `lib/jido/agent_server/parent_ref.ex` - Parent tracking
- `lib/jido/agent_server/child_info.ex` - Child process tracking
- `lib/jido/agent_server/directive_exec.ex` - Directive execution
- `lib/jido/agent_server/directive_executors.ex` - Execution orchestration
- `lib/jido/agent_server/signal_router.ex` - Signal routing
- `lib/jido/agent_server/error_policy.ex` - Error handling policies

**Built-in Actions:**
- `lib/jido/actions/control.ex` - Control flow actions
- `lib/jido/actions/status.ex` - Status queries
- `lib/jido/actions/lifecycle.ex` - Lifecycle management
- `lib/jido/actions/scheduling.ex` - Scheduling actions

**Observability:**
- `lib/jido/telemetry.ex` - Telemetry events
- `lib/jido/observe.ex` - Tracing interface
- `lib/jido/observe/tracer.ex` - Tracer behavior
- `lib/jido/observe/span_ctx.ex` - Span context
- `lib/jido/observe/log.ex` - Log tracer
- `lib/jido/observe/noop_tracer.ex` - No-op tracer

**Error Handling:**
- `lib/jido/error.ex` - Unified error handling with Splode

**Utilities:**
- `lib/jido/util.ex` - Utility functions
- `lib/jido/discovery.ex` - Module discovery
- `lib/jido/scheduler.ex` - Scheduling utilities
- `lib/jido/await.ex` - Async await helpers

**Skill System:**
- `lib/jido/skill/spec.ex` - Skill specifications

**Signals:**
- `lib/jido/agent_server/signal/*.ex` - Server signal types

---

## 3. Existing Patterns Found

### 3.1 Error Handling Pattern (Splode-based)

**Pattern**: Unified error handling across all Jido packages using Splode error classes.

**Error Class Hierarchy** (from `lib/jido/error.ex`):
```elixir
:invalid > :execution > :planning > :routing > :timeout > :internal
```

**Example Implementation**:
```elixir
defmodule Jido.Error do
  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      planning: Planning,
      routing: Routing,
      timeout: Timeout,
      internal: Internal
    ]

  def validation_error(message, details \\ %{}) do
    InvalidInputError.exception(message: message, details: details)
  end
end
```

**Integration with Dependencies**:
- `Jido.Error.*` - Core framework errors
- `Jido.Action.Error.*` - Action execution errors from jido_action (uses same classes)
- `Jido.Signal.Error.*` - Signal processing errors from jido_signal (uses same classes)

**Audit Checklist**:
- [ ] All errors use Splode error classes consistently
- [ ] Error messages are descriptive and actionable
- [ ] Error details include relevant context (field, value, stacktrace)
- [ ] Error class precedence is correctly applied

### 3.2 Agent Pattern (Immutable + Pure Functions)

**Pattern**: Agents are immutable data structures with pure `cmd/2` function.

**Core Invariants** (from `lib/jido/agent.ex`):
1. `cmd/2` always returns complete agent state (no "apply directives" step)
2. Directives are external effects only (never modify agent state)
3. `cmd/2` is a pure function (same inputs → same outputs)

**Example**:
```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [
      status: [type: :atom, default: :idle],
      counter: [type: :integer, default: 0]
    ]
end

# Usage
{agent, directives} = MyAgent.cmd(agent, MyAction)
```

**Audit Checklist**:
- [ ] Agent modules use `use Jido.Agent` macro
- [ ] Schema validation uses Zoi schemas
- [ ] `cmd/2` returns `{agent, directives}` tuple
- [ ] No direct state mutation in actions
- [ ] Directives are bare structs (no tuple wrappers)

### 3.3 Action Pattern (Zoi Schema + Behavior)

**Pattern**: Actions use Zoi schemas for validated input/output.

**Example** (from `lib/jido_action.ex`):
```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    description: "Performs my action",
    schema: [
      input: [type: :string, required: true]
    ],
    output_schema: [
      result: [type: :string, required: true]
    ]

  def run(params, _context) do
    {:ok, %{result: String.upcase(params.input)}}
  end
end
```

**Audit Checklist**:
- [ ] Actions use `use Jido.Action` macro
- [ ] `schema` is defined for input validation
- [ ] `output_schema` is defined for output validation
- [ ] `run/2` returns `{:ok, map()}` or `{:error, term()}`
- [ ] Error handling uses `Jido.Action.Error`

### 3.4 Directive Pattern (Effect Descriptions)

**Pattern**: Directives describe effects for the runtime to interpret.

**Built-in Directives** (from `lib/jido/agent/directive.ex`):
- `%Directive.Emit{}` - Dispatch a signal
- `%Directive.Error{}` - Signal an error
- `%Directive.Spawn{}` - Spawn a child process
- `%Directive.Schedule{}` - Schedule a delayed message
- `%Directive.Stop{}` - Stop the agent process
- `%Directive.Cron{}` - Schedule recurring actions

**Example**:
```elixir
%Directive.Emit{
  signal: %Jido.Signal{
    type: "status.changed",
    data: %{status: :running}
  },
  dispatch: {:pubsub, topic: "events"}
}
```

**Audit Checklist**:
- [ ] Directives are bare structs (no tuples)
- [ ] Directives don't modify agent state directly
- [ ] Signal dispatches use proper routing
- [ ] Spawn directives include proper supervision

### 3.5 Testing Pattern (Custom Test Cases)

**Pattern**: Custom test case modules with isolated Jido instances.

**Test Helpers**:
- `JidoTest.Case` - Isolated Jido instances per test
- `Jido.Action.Test.Case` - Isolated action execution
- Custom test agents in `test/support/test_agents.ex`
- Custom test actions in `test/support/test_actions.ex`

**Example**:
```elixir
defmodule Jido.AgentTest do
  use JidoTest.Case, async: true

  test "agent executes action" do
    agent = TestAgent.new()
    {agent, _directives} = TestAgent.cmd(agent, TestAction)
    assert agent.status == :completed
  end
end
```

**Audit Checklist**:
- [ ] Tests use `JidoTest.Case` for isolation
- [ ] Tests cover happy paths
- [ ] Tests cover error paths
- [ ] Tests cover edge cases (nil, empty, invalid input)
- [ ] Async tests don't share state

### 3.6 Strategy Pattern (Pluggable Execution)

**Pattern**: Strategies define how agents execute actions.

**Built-in Strategies**:
- `Jido.Agent.Strategy.Direct` - Execute actions directly
- `Jido.Agent.Strategy.FSM` - FSM-based execution

**Example**:
```elixir
defmodule MyAgent do
  use Jido.Agent,
    strategy: Jido.Agent.Strategy.FSM,
    schema: [...]
end
```

**Audit Checklist**:
- [ ] Strategy implements `init/2` callback
- [ ] Strategy state is properly initialized
- [ ] Strategy handles errors gracefully
- [ ] Strategy cleanup is properly implemented

---

## 4. Integration Points

### 4.1 Cross-Package Dependencies

**Dependency Graph**:
```
jido (v2.0) - TARGET OF AUDIT
  └── depends on: jido_action (audited ✅), jido_signal (audited ✅)

jido_ai
  └── depends on: jido (v2.0), req_llm
  └── Managed separately by Pascal 🔄
```

**Audit Implications**:
- `jido` depends on already-audited `jido_action` and `jido_signal`
- Focus on verifying correct integration with these dependencies
- No version coordination needed for dependencies (already complete)

### 4.2 Signal Dispatch Integration

**Integration**: `Jido.Agent.Directive.Emit` → `Jido.Signal.Dispatch`

**Flow**:
```elixir
# Agent emits directive
%Directive.Emit{signal: signal, dispatch: {:pubsub, topic: "events"}}
# ↓
# AgentServer executes directive
Jido.Signal.Dispatch.dispatch(signal, [pubsub: "events"])
# ↓
# Signal routed to subscribers
```

**Audit Checklist**:
- [ ] Signal dispatch handles errors gracefully
- [ ] Dispatch failures don't crash agents
- [ ] Signal routing is correctly configured
- [ ] PubSub topics are properly managed

### 4.3 Action Integration (via jido_action)

**Integration**: `Jido.Agent` → `Jido.Action` (from jido_action)

**Flow**:
```elixir
# Agent executes action
{agent, directives} = MyAgent.cmd(agent, MyAction, params)
# ↓
# Action validates via Zoi schema
# ↓
# Action executes via Jido.Action.Exec
# ↓
# Results returned to agent
```

**Audit Checklist**:
- [ ] Action execution properly handles errors
- [ ] Action results are properly formatted
- [ ] Action timeouts are properly configured
- [ ] Action schemas match agent expectations

### 4.4 Testing Integration

**Integration**: `JidoTest.Case` → jido

**Flow**:
```elixir
# Test case starts
JidoTest.Case.start_agent(agent_module)
# ↓
# Isolated Jido instance created
# ↓
# Test runs with isolated instance
# ↓
# Test case stops agent
JidoTest.Case.stop_agent(agent_pid)
```

**Audit Checklist**:
- [ ] Test isolation is properly implemented
- [ ] Test cleanup is reliable
- [ ] Test helpers don't leak state
- [ ] Async tests don't interfere

---

## 5. Test Impact & Patterns

### 5.1 Test Coverage Analysis

**Current Test Files**:
- `jido`: ~50 test files

**Coverage Targets**: 80-90% (configured in jido)

**Audit Tasks**:
1. Run coverage report: `mix test --cover`
2. Identify modules below 80% coverage
3. Add tests for uncovered paths
4. Verify edge case coverage

### 5.2 Edge Cases to Verify

**Common Edge Cases**:
- `nil` values in required fields
- Empty lists/maps
- Invalid types (e.g., string instead of integer)
- Concurrent access to shared state
- Timeout scenarios
- Process crashes during execution
- Memory exhaustion
- Large payloads

**Specific Edge Cases by Module**:

**Agent Modules**:
- Agent with empty state
- Agent with no strategy
- Agent with no skills
- Agent with duplicate skill names
- Agent with invalid directive
- Agent with malformed signal

**AgentServer Modules**:
- Server with no parent
- Server with crashed child
- Server with timeout during directive execution
- Server with concurrent signal dispatch
- Server with invalid state transition

**Directive Modules**:
- Emit with nil signal
- Spawn with invalid module
- Schedule with invalid cron expression
- Stop with no cleanup
- Error with no error details

**Strategy Modules**:
- Strategy with no init
- Strategy with invalid state
- Strategy with timeout
- Strategy with crash during execution

### 5.3 Concurrency Testing

**Scenarios**:
- Multiple agents executing concurrently
- Concurrent signal dispatch
- Race conditions in agent state updates
- Concurrent directive execution
- Concurrent child process spawning

**Testing Tools**:
- StreamData for property-based testing
- Concurrent test execution (ExUnit `async: true`)
- Manual race condition injection

---

## 6. Configuration & Environment

### 6.1 Configuration Files to Review

**Per-Project Config**:
- `config/config.exs` - Base configuration
- `config/dev.exs` - Development config
- `config/test.exs` - Test config
- `config/runtime.exs` - Runtime config

**Workspace Config**:
- `config/workspace.exs` - Workspace project management

**Audit Checklist**:
- [ ] All configs use schema validation
- [ ] Sensitive values use environment variables
- [ ] Default values are safe
- [ ] Config changes are backwards compatible

### 6.2 Environment Variables

**Common Variables**:
- `MIX_ENV` - Environment (dev, test, prod)
- `JIDO_LOG_LEVEL` - Logging level
- LLM API keys (for `req_llm`)

**Audit Checklist**:
- [ ] Required variables are documented
- [ ] Default values are provided
- [ ] Variable validation is implemented
- [ ] Secrets are not hardcoded

---

## 7. Required New Dependencies/Patterns

**None identified** - The codebase uses established patterns and dependencies.

**Recommendations**:
1. Continue using Zoi for schema validation
2. Continue using Splode for error handling
3. Continue using TypedStruct for type safety
4. Consider adding `benchee` for benchmarking if performance issues found

---

## 8. Risk Assessment

### 8.1 Breaking Changes

**High Risk Areas**:
- Agent `cmd/2` API signature changes
- Directive structure changes
- Signal routing changes
- Action `run/2` return value changes

**Mitigation**:
- Semantic versioning (MAJOR for breaking changes)
- Deprecation warnings for minor breaking changes
- Migration guides for major version updates

### 8.2 Performance Implications

**Potential Bottlenecks**:
- Signal dispatch in high-throughput scenarios
- Agent state copying (immutable design)
- Action execution overhead
- Serialization/deserialization

**Mitigation**:
- Benchmark critical paths
- Optimize hot paths if needed
- Document performance characteristics

### 8.3 Security Touchpoints

**Areas Requiring Review**:
- LLM tool execution (sandboxing)
- Signal routing (authorization)
- File system operations (path traversal)
- HTTP requests (SSRF, injection)
- Lua code execution (code injection)

**Mitigation**:
- Validate all inputs
- Sandboxing for untrusted code
- Rate limiting for external requests
- Audit logging for security events

### 8.4 Migration Complexity

**Data Migrations**:
- Signal journal format changes
- Agent state serialization changes

**Code Migrations**:
- Action module updates
- Agent module updates
- Directive updates

**Mitigation**:
- Version compatibility layers
- Automated migration scripts
- Comprehensive migration documentation

---

## 9. Third-Party Integrations & External Services

**Note**: Jido core has minimal external integrations. Most external service integrations are handled by:
- `jido_action` - Already audited ✅
- `jido_ai` - Managed separately by Pascal 🔄

**Core Dependencies** (already audited in dependencies):
- `jido_signal` - Signal routing and dispatch
- `jido_action` - Action execution framework

**Audit Focus**: Verify proper integration with already-audited dependencies.

---

## 10. Unclear Areas Requiring Clarification

### 10.1 Release Scope

**Status**: ✅ **CLARIFIED**

**Scope**: Jido Core 2.0 audit focuses exclusively on the `jido` module.

**Dependencies**:
- `jido_action` - Already audited and complete ✅
- `jido_signal` - Already audited and complete ✅
- `jido_ai` - Being managed separately by Pascal 🔄

### 10.2 Version Bumping Strategy

**Status**: ✅ **CLARIFIED**

**Strategy**: Bump `jido` to 2.0.0 independently based on audit findings.

**Dependencies**:
- `jido_action` and `jido_signal` are already at stable versions
- No coordinated release needed across all packages

### 10.3 Backward Compatibility

**Question**: What level of backward compatibility is required for 2.0?

**Clarification Needed**:
- Are breaking changes acceptable?
- Should migration paths be provided?
- Is a deprecation period needed?

**Recommendation**: Clarify in planning phase. Generally, major versions allow breaking changes with migration guides.

### 10.4 Audit Depth

**Question**: How thorough should the audit be?

**Levels**:
1. **Light**: Review public APIs only (1-2 days)
2. **Medium**: Review public APIs + key internals (3-5 days)
3. **Comprehensive**: Review all modules + edge cases (1-2 weeks)

**Recommendation**: Start with Medium audit, escalate to Comprehensive if critical issues found.

---

## 11. Documentation Links

### 11.1 Core Framework Documentation

**Jido Patterns**:
- Agent Pattern: 📖 [Agent Documentation](https://hexdocs.pm/jido/Jido.Agent.html)
- Directive Pattern: 📖 [Directive Documentation](https://hexdocs.pm/jido/Jido.Agent.Directive.html)
- Strategy Pattern: 📖 [Strategy Documentation](https://hexdocs.pm/jido/Jido.Agent.Strategy.html)

**Error Handling**:
- 📖 [Splode Documentation](https://hexdocs.pm/splode)
- 📖 [Jido.Error Documentation](https://hexdocs.pm/jido/Jido.Error.html)

**Validation**:
- 📖 [Zoi Documentation](https://hexdocs.pm/zoi)
- 📖 [NimbleOptions Documentation](https://hexdocs.pm/nimble_options)

### 11.2 Action System Documentation

**Actions**:
- 📖 [Jido.Action Documentation](https://hexdocs.pm/jido_action/Jido.Action.html)
- 📖 [Action Execution](https://hexdocs.pm/jido_action/Jido.Action.Exec.html)

**Planning**:
- 📖 [Instruction Plans](https://hexdocs.pm/jido_action/JidoInstruction.html)
- 📖 [Action Plans](https://hexdocs.pm/jido_action/JidoPlan.html)

### 11.3 Signal System Documentation

**Signals**:
- 📖 [Jido.Signal Documentation](https://hexdocs.pm/jido_signal/Jido.Signal.html)
- 📖 [Signal Bus](https://hexdocs.pm/jido_signal/Jido.Signal.Bus.html)
- 📖 [Signal Dispatch](https://hexdocs.pm/jido_signal/Jido.Signal.Dispatch.html)

**Routing**:
- 📖 [Signal Router](https://hexdocs.pm/jido_signal/Jido.Signal.Router.html)

**Serialization**:
- 📖 [Serialization](https://hexdocs.pm/jido_signal/Jido.Signal.Serialization.html)

### 11.4 AI Integration Documentation

**Jido AI**:
- 📖 [Jido.AI Documentation](https://hexdocs.pm/jido_ai/Jido.AI.html)
- 📖 [ReAct Pattern](https://hexdocs.pm/jido_ai/Jido.AI.Strategy.React.html)
- 📖 [Tool Adapter](https://hexdocs.pm/jido_ai/JidoAi.ToolAdapter.html)

**LLM Client**:
- 📖 [ReqLLM Documentation](https://hexdocs.pm/req_llm)

### 11.3 Documentation Links

**Jido Core**:
- 📖 [Jido.Agent Documentation](https://hexdocs.pm/jido/Jido.Agent.html)
- 📖 [Jido.AgentServer Documentation](https://hexdocs.pm/jido/Jido.AgentServer.html)
- 📖 [Jido.Directive Documentation](https://hexdocs.pm/jido/Jido.Agent.Directive.html)
- 📖 [Jido.Strategy Documentation](https://hexdocs.pm/jido/Jido.Agent.Strategy.html)

**Dependencies**:
- 📖 [Jido.Action Documentation](https://hexdocs.pm/jido_action/Jido.Action.html)
- 📖 [Jido.Signal Documentation](https://hexdocs.pm/jido_signal/Jido.Signal.html)

**Quality Tools**:
- 📖 [Credo Documentation](https://hexdocs.pm/credo)
- 📖 [Dialyxir Documentation](https://hexdocs.pm/dialyxir)

---

## 12. Audit Checklist Template

### 12.1 Module-Level Checklist

For each module, verify:

**API Design**:
- [ ] Public functions are documented
- [ ] Function signatures are consistent
- [ ] Parameter types are specified
- [ ] Return types are specified
- [ ] @spec attributes are complete

**Error Handling**:
- [ ] Errors use Splode error classes
- [ ] Error messages are descriptive
- [ ] Error details include context
- [ ] Error handling is complete

**Concurrency**:
- [ ] State is properly isolated
- [ ] Race conditions are handled
- [ ] GenServer calls/casts are correct
- [ ] Timeout handling is implemented

**Edge Cases**:
- [ ] nil values are handled
- [ ] Empty collections are handled
- [ ] Invalid types are rejected
- [ ] Boundary conditions are tested

**Documentation**:
- [ ] @moduledoc is present
- [ ] @doc is present for public functions
- [ ] Examples are provided
- [ ] Usage notes are clear

### 12.2 Cross-Cutting Concerns

**Logging**:
- [ ] Logger statements are appropriate
- [ ] Log levels are correct
- [ ] Sensitive data is not logged

**Telemetry**:
- [ ] Telemetry events are attached
- [ ] Event names follow convention
- [ ] Event metadata is complete

**Configuration**:
- [ ] Configuration is validated
- [ ] Defaults are safe
- [ ] Required values are documented

**Security**:
- [ ] Inputs are validated
- [ ] Outputs are sanitized
- [ ] Secrets are protected
- [ ] Access control is implemented

---

## 13. Next Steps

### 13.1 Immediate Actions

1. **Define Audit Scope**: Confirm which projects are in "Jido Core 2.0"
2. **Set Up Tracking**: Create issue tracker for audit findings
3. **Establish Baseline**: Run test coverage and quality tools
4. **Create Review Template**: Standardize audit process

### 13.2 Audit Execution

1. **Phase 1**: Review public APIs (1-2 days)
2. **Phase 2**: Review internal abstractions (2-3 days)
3. **Phase 3**: Review concurrency and error handling (2-3 days)
4. **Phase 4**: Review edge cases and boundary conditions (2-3 days)
5. **Phase 5**: Document findings and create issue list (1 day)

### 13.3 Deliverables

1. **Audit Report**: Summary of findings organized by project
2. **Issue Tracker**: List of issues with priorities
3. **Pull Requests**: Targeted PRs for critical fixes
4. **Migration Guide**: If breaking changes are identified

---

## 14. Summary

**Files Identified**: ~45 modules in the `jido` core framework

**Key Patterns**:
- Splode-based error handling
- Immutable agents with pure `cmd/2`
- Zoi schema validation
- Directive-based effects
- Strategy pattern for execution

**Integration Points**:
- Signal dispatch via `jido_signal` (already audited ✅)
- Action execution via `jido_action` (already audited ✅)
- Cross-package error handling
- Test isolation utilities

**Risk Areas**:
- Breaking changes in public APIs
- Performance in high-throughput scenarios
- Concurrency in agent execution
- Migration complexity

**Estimated Audit Effort**: 3-5 days for comprehensive audit of jido core modules.

---

**End of Research Document**
