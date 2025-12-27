# Jido 2.0 Runners Specification

> Runners are pluggable decision engines that implement the "thinking" step of agents.

---

## Overview

Runners are the **brain** of Jido agents. They implement `handle_signal/2` using various decision-making strategies, from simple pattern matching to complex AI planning systems.

**Core principle:** Runners are pure functions. They never perform I/O directly—all work is expressed as Effects.

```
Signal → Runner.handle/3 → {:ok, new_state, [Effect.t()]}
```

---

## Runner Contract

All runners implement a single behaviour:

```elixir
defmodule Jido.Agent.Runner do
  @moduledoc "Behaviour for all decision engines."

  @doc """
  Handle an incoming signal, producing new state and effects.
  
  ## Requirements
  - Must be pure (no I/O, no side effects)
  - Must be deterministic (same inputs → same outputs)
  - All external work expressed via Effects
  """
  @callback handle(
    agent_module :: module(),
    state :: struct(),
    signal :: Jido.Signal.t()
  ) ::
    {:ok, new_state :: struct(), effects :: [Jido.Agent.Effect.t()]}
    | {:error, term()}

  @doc "Optional: Return Spark DSL extension for this runner"
  @callback dsl_extension() :: module() | nil

  @optional_callbacks [dsl_extension: 0]
end
```

---

## Runner State Model

**All runner state lives in the agent's state struct.** Runners are stateless modules.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    runner: :react,
    schema: %{
      # Domain state
      user_id: Zoi.integer(),
      messages: Zoi.list(Zoi.any()),
      
      # Runner state (embedded)
      runner: Zoi.map() |> Zoi.default(%{
        mode: :idle,
        plan: nil,
        transcript: [],
        blackboard: %{}
      })
    }
end
```

This design enables:
- **Replay/time-travel**: All state captured in agent struct
- **Testing**: No hidden state to mock
- **Serialization**: Full state can be persisted

---

## Two-Phase Mental Model

Runners conceptually operate in two phases:

### 1. Planning Phase
Compute what work needs to be done. May produce a `Plan` (DAG of Instructions).

### 2. Compilation Phase  
Convert the plan into executable `[Effect.t()]` for AgentServer.

Simple runners combine these phases; complex runners (BT, HTN, ReAct) explicitly build Plans.

---

## Runner Spectrum

### 1. Simple Runner

**Purpose:** Direct delegation to agent's `handle_signal/2`. No abstraction.

```elixir
defmodule Jido.Agent.Runner.Simple do
  @behaviour Jido.Agent.Runner

  @impl true
  def handle(agent_module, state, signal) do
    agent_module.handle_signal(state, signal)
  end
end
```

**Configuration:**
```elixir
use Jido.Agent, name: "simple", runner: :simple
```

**Use when:** Logic is straightforward, you want full manual control.

**Plan behavior:** No explicit Plan; effects returned directly.

---

### 2. State Machine Runner

**Purpose:** Deterministic workflows with explicit states, transitions, and guards.

```elixir
defmodule Jido.Agent.Runner.StateMachine do
  @behaviour Jido.Agent.Runner

  @impl true
  def handle(agent_module, state, signal) do
    machine = agent_module.machine()
    
    case step(machine, state, signal) do
      {:ok, new_state, transition} ->
        effects = transition_to_effects(transition)
        {:ok, new_state, effects}
      {:error, :no_transition} ->
        {:ok, state, []}  # Signal doesn't trigger any transition
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**Configuration:**
```elixir
defmodule OrderAgent do
  use Jido.Agent,
    name: "order",
    runner: :state_machine,
    schema: %{
      status: Zoi.atom() |> Zoi.default(:pending),
      order_id: Zoi.string()
    }

  # Define state machine
  machine do
    state :pending
    state :processing
    state :completed
    state :cancelled

    on :start_processing, 
       from: :pending, 
       to: :processing,
       guard: &has_payment?/1,
       effects: [%Effect.Run{action: ValidateOrder}]

    on :complete,
       from: :processing,
       to: :completed,
       effects: [
         %Effect.Run{action: SendConfirmation},
         %Effect.Emit{type: "order.completed"}
       ]

    on :cancel,
       from: [:pending, :processing],
       to: :cancelled,
       effects: [%Effect.Run{action: RefundPayment}]
  end
end
```

**State machine data model:**
```elixir
defmodule Jido.Agent.Runner.StateMachine.Machine do
  @type state_name :: atom()
  
  @type transition :: %{
    event: atom(),
    from: state_name() | [state_name()],
    to: state_name(),
    guard: (struct() -> boolean()) | nil,
    effects: [Effect.t()]
  }

  @type t :: %__MODULE__{
    states: [state_name()],
    initial: state_name(),
    transitions: [transition()],
    state_key: atom()  # Path in agent state, default :status
  }
end
```

**Plan behavior:** Linear plan with one step per transition effect.

**Use when:** Deterministic domain workflows, order processing, approval flows.

---

### 3. Chain of Thought Runner

**Purpose:** LLM-driven step-by-step reasoning without tool calls.

```elixir
defmodule Jido.Agent.Runner.ChainOfThought do
  @behaviour Jido.Agent.Runner

  @impl true
  def handle(agent_module, state, signal) do
    case signal.type do
      :user_message ->
        handle_user_message(agent_module, state, signal)
      :llm_result ->
        handle_llm_result(agent_module, state, signal)
      _ ->
        {:ok, state, []}
    end
  end

  defp handle_user_message(_agent_module, state, signal) do
    transcript = append_message(state.runner.transcript, :user, signal.data.text)
    
    new_state = %{state | 
      runner: %{state.runner | 
        mode: :thinking,
        transcript: transcript
      }
    }
    
    effects = [
      %Effect.Run{
        action: LLMChat,
        params: %{
          messages: build_cot_prompt(transcript),
          response_format: :reasoning_steps
        },
        meta: %Effect.Meta{group: :llm}
      }
    ]
    
    {:ok, new_state, effects}
  end

  defp handle_llm_result(_agent_module, state, signal) do
    %{result: result} = signal.data
    
    case parse_cot_response(result) do
      {:thinking, thought} ->
        # Continue chain of thought
        transcript = append_message(state.runner.transcript, :assistant, thought)
        new_state = %{state | runner: %{state.runner | transcript: transcript}}
        effects = [continue_thinking_effect(transcript)]
        {:ok, new_state, effects}
        
      {:answer, answer} ->
        # Final answer reached
        transcript = append_message(state.runner.transcript, :assistant, answer)
        new_state = %{state | runner: %{state.runner | mode: :idle, transcript: transcript}}
        effects = [%Effect.Reply{signal: build_response(answer)}]
        {:ok, new_state, effects}
    end
  end
end
```

**Runner state:**
```elixir
%{
  mode: :idle | :thinking,
  transcript: [%{role: :user | :assistant, content: String.t()}],
  max_steps: 10,
  current_step: 0
}
```

**Plan behavior:** Each thinking step is an Instruction; linear chain.

**Use when:** Complex reasoning, math problems, analysis tasks without tools.

---

### 4. ReAct Runner

**Purpose:** LLM reasoning interleaved with tool/action execution.

The ReAct (Reasoning + Acting) pattern:
1. LLM reasons about the problem
2. LLM chooses a tool to call
3. Tool executes, result observed
4. LLM reasons about observation
5. Repeat until final answer

```elixir
defmodule Jido.Agent.Runner.ReAct do
  @behaviour Jido.Agent.Runner

  @impl true
  def handle(agent_module, state, signal) do
    case signal.type do
      :user_message -> start_react_loop(agent_module, state, signal)
      :llm_result -> handle_llm_decision(agent_module, state, signal)
      :action_result -> handle_tool_result(agent_module, state, signal)
      _ -> {:ok, state, []}
    end
  end

  defp start_react_loop(agent_module, state, signal) do
    tools = agent_module.tools()
    transcript = [%{role: :user, content: signal.data.text}]
    
    new_state = %{state |
      runner: %{
        mode: :waiting_llm,
        transcript: transcript,
        tools: tools,
        step: 0,
        max_steps: 10
      }
    }
    
    effects = [
      %Effect.Run{
        action: LLMChat,
        params: %{
          messages: build_react_prompt(transcript, tools),
          tools: tools_to_openai_format(tools)
        },
        meta: %Effect.Meta{group: :llm, priority: 10}
      }
    ]
    
    {:ok, new_state, effects}
  end

  defp handle_llm_decision(_agent_module, state, signal) do
    case parse_llm_response(signal.data.result) do
      {:tool_call, tool_name, args} ->
        # LLM wants to use a tool
        tool_action = Map.get(state.runner.tools, tool_name)
        transcript = append_tool_call(state.runner.transcript, tool_name, args)
        
        new_state = %{state |
          runner: %{state.runner |
            mode: :waiting_tool,
            transcript: transcript,
            step: state.runner.step + 1
          }
        }
        
        effects = [
          %Effect.Run{
            action: tool_action,
            params: args,
            meta: %Effect.Meta{group: :tool, tags: [:react_tool]}
          }
        ]
        
        {:ok, new_state, effects}

      {:final_answer, answer} ->
        # LLM has final answer
        transcript = append_answer(state.runner.transcript, answer)
        
        new_state = %{state |
          runner: %{state.runner | mode: :idle, transcript: transcript}
        }
        
        effects = [%Effect.Reply{signal: build_response(answer)}]
        
        {:ok, new_state, effects}
    end
  end

  defp handle_tool_result(_agent_module, state, signal) do
    observation = format_observation(signal.data.result)
    transcript = append_observation(state.runner.transcript, observation)
    
    if state.runner.step >= state.runner.max_steps do
      # Max steps reached, force conclusion
      new_state = %{state | runner: %{state.runner | mode: :idle}}
      effects = [%Effect.Reply{signal: build_timeout_response()}]
      {:ok, new_state, effects}
    else
      # Continue ReAct loop
      new_state = %{state |
        runner: %{state.runner | mode: :waiting_llm, transcript: transcript}
      }
      
      effects = [
        %Effect.Run{
          action: LLMChat,
          params: %{messages: transcript, tools: state.runner.tools},
          meta: %Effect.Meta{group: :llm}
        }
      ]
      
      {:ok, new_state, effects}
    end
  end
end
```

**Runner state:**
```elixir
%{
  mode: :idle | :waiting_llm | :waiting_tool,
  transcript: [%{role: :user | :assistant | :tool, content: term()}],
  tools: %{String.t() => module()},
  step: non_neg_integer(),
  max_steps: non_neg_integer()
}
```

**Plan behavior:** Each step (thought + tool call) becomes an Instruction.

**Use when:** Complex tasks requiring tool use, research, data retrieval.

---

### 5. Behavior Tree Runner

**Purpose:** Complex decision trees with control flow (sequences, selectors, decorators).

Integrates with `jido_behaviortree` package.

```elixir
defmodule Jido.Agent.Runner.BehaviorTree do
  @behaviour Jido.Agent.Runner
  alias Jido.BehaviorTree.{Node, Tick}

  @impl true
  def handle(agent_module, state, signal) do
    # Build tick context
    tick = %Tick{
      sequence: state.runner.sequence + 1,
      blackboard: state.runner.blackboard,
      timestamp: DateTime.utc_now()
    }
    
    # Inject signal data into blackboard
    tick = Tick.put(tick, :signal, signal)
    
    # Execute one tick of the tree
    {status, new_root} = Node.execute_tick(state.bt_root, tick)
    
    # Collect effects from blackboard
    effects = Tick.get(tick, :pending_effects, [])
    
    # Update state
    new_state = %{state |
      bt_root: new_root,
      runner: %{state.runner |
        sequence: tick.sequence,
        blackboard: tick.blackboard,
        last_status: status
      }
    }
    
    # Handle status
    case status do
      :success ->
        {:ok, new_state, effects ++ success_effects(state)}
      :failure ->
        {:ok, new_state, effects ++ failure_effects(state)}
      :running ->
        # Schedule next tick
        {:ok, new_state, effects ++ [schedule_next_tick()]}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_next_tick do
    %Effect.Timer{
      in: 100,  # ms until next tick
      signal: %Signal{type: :bt_tick},
      key: :bt_tick
    }
  end
end
```

**Agent configuration:**
```elixir
defmodule GuardAgent do
  use Jido.Agent,
    name: "guard",
    runner: :behavior_tree,
    schema: %{
      bt_root: Zoi.any(),  # Root node struct
      runner: Zoi.map()
    }

  def init_tree do
    # Build behavior tree
    Jido.BehaviorTree.new(
      Nodes.Selector.new([
        # Priority 1: Handle threats
        Nodes.Sequence.new([
          Nodes.Condition.new(&threat_detected?/1),
          Nodes.Action.new(AlertAction, %{})
        ]),
        # Priority 2: Patrol
        Nodes.Sequence.new([
          Nodes.Action.new(PatrolAction, %{}),
          Nodes.Wait.new(5000)
        ])
      ])
    )
  end
end
```

**Node types from jido_behaviortree:**

| Category | Nodes | Description |
|----------|-------|-------------|
| Composite | Sequence, Selector | Control flow over children |
| Decorator | Inverter, Repeat, Succeeder, Failer | Modify child behavior |
| Leaf | Action, Wait, SetBlackboard | Execute work |

**Tick semantics:**
- Each tick traverses the tree once
- Nodes return `:success`, `:failure`, or `:running`
- `:running` nodes resume on next tick
- Blackboard enables inter-node communication

**Plan behavior:** Each tick produces a partial Plan of executed nodes.

**Use when:** Game AI, robotics, complex reactive behaviors.

---

### 6. HTN Runner

**Purpose:** Hierarchical Task Network planning—decompose high-level goals into executable primitives.

Integrates with `jido_htn` package.

```elixir
defmodule Jido.Agent.Runner.HTN do
  @behaviour Jido.Agent.Runner
  alias Jido.HTN

  @impl true
  def handle(agent_module, state, signal) do
    case signal.type do
      :goal_request ->
        plan_for_goal(agent_module, state, signal)
      :action_result ->
        continue_plan(agent_module, state, signal)
      _ ->
        {:ok, state, []}
    end
  end

  defp plan_for_goal(agent_module, state, signal) do
    domain = agent_module.domain()
    world_state = build_world_state(state, signal)
    root_tasks = [signal.data.goal]
    
    case HTN.plan(domain, world_state, root_tasks: root_tasks) do
      {:ok, primitive_steps, mtr} ->
        plan = steps_to_plan(primitive_steps)
        ready = Plan.ready_steps(plan)
        effects = steps_to_effects(ready)
        
        new_state = %{state |
          runner: %{state.runner |
            mode: :executing,
            plan: plan,
            world_state: world_state,
            mtr: mtr  # Method traversal record for debugging
          }
        }
        
        {:ok, new_state, effects}
        
      {:error, reason} ->
        effects = [%Effect.Reply{signal: planning_failed_response(reason)}]
        {:ok, state, effects}
    end
  end

  defp continue_plan(_agent_module, state, signal) do
    %{instruction_id: completed_id, result: result} = signal.data
    
    # Update world state with action effects
    new_world = apply_action_effects(state.runner.world_state, result)
    
    # Mark instruction complete in plan
    plan = Plan.complete_step(state.runner.plan, completed_id, result)
    
    if Plan.completed?(plan) do
      # All done
      new_state = %{state | runner: %{state.runner | mode: :idle, plan: nil}}
      effects = [%Effect.Reply{signal: plan_completed_response(plan)}]
      {:ok, new_state, effects}
    else
      # Execute next ready steps
      ready = Plan.ready_steps(plan)
      effects = steps_to_effects(ready)
      
      new_state = %{state |
        runner: %{state.runner | plan: plan, world_state: new_world}
      }
      
      {:ok, new_state, effects}
    end
  end

  defp steps_to_plan(primitive_steps) do
    # Convert HTN primitives to Plan DAG
    # Dependencies come from HTN's ordering
    steps = Enum.with_index(primitive_steps)
    |> Enum.map(fn {{action, params}, idx} ->
      %{
        id: idx,
        instruction: %Instruction{action: action, params: Map.new(params)},
        deps: if(idx == 0, do: [], else: [idx - 1]),
        status: :pending
      }
    end)
    
    %Plan{id: generate_id(), steps: steps}
  end
end
```

**HTN domain configuration:**
```elixir
defmodule TravelDomain do
  use Jido.HTN.Domain

  # Compound task: travel from A to B
  compound "travel" do
    method "by_taxi", 
      precondition: &has_money?/1,
      subtasks: ["call_taxi", "ride_taxi", "pay_taxi"]
    
    method "by_walk",
      precondition: &is_close?/1,
      subtasks: ["walk_to_destination"]
  end

  # Primitive tasks (leaf actions)
  primitive "call_taxi", CallTaxiAction,
    preconditions: [&has_phone?/1],
    effects: [&set_taxi_called/1]

  primitive "ride_taxi", RideTaxiAction,
    preconditions: [&taxi_available?/1],
    effects: [&update_location/1]
end
```

**Key HTN concepts:**

| Concept | Description |
|---------|-------------|
| Domain | Collection of compound and primitive tasks |
| Compound Task | High-level goal decomposable via methods |
| Method | One way to decompose a compound task |
| Primitive Task | Executable action with preconditions/effects |
| World State | Current state of the environment |
| Planner | Finds valid decomposition path |

**Plan behavior:** HTN naturally produces a Plan (DAG) via task decomposition.

**Use when:** Goal-oriented AI, game planning, workflow automation.

---

## LLM Integration Pattern

LLMs are integrated via Actions, not built into runners.

```elixir
defmodule Jido.Actions.LLM.Chat do
  use Jido.Action,
    name: "llm_chat",
    description: "Send messages to an LLM"

  def schema do
    %{
      model: Zoi.string() |> Zoi.default("gpt-4"),
      messages: Zoi.list(Zoi.map()),
      tools: Zoi.list(Zoi.map()) |> Zoi.optional(),
      temperature: Zoi.float() |> Zoi.default(0.7)
    }
  end

  def run(params, context) do
    provider = context[:llm_provider] || Jido.LLM.OpenAI
    provider.chat(params)
  end
end
```

**Runners emit Effects targeting LLM Actions:**
```elixir
%Effect.Run{
  action: Jido.Actions.LLM.Chat,
  params: %{
    model: "gpt-4",
    messages: transcript,
    tools: tool_definitions
  },
  meta: %Effect.Meta{group: :llm}
}
```

**Benefits:**
- Runners are provider-agnostic
- LLM configuration lives in Actions/context
- Easy to mock for testing
- Swap providers without changing runners

---

## Multi-Turn Execution Pattern

All multi-turn logic follows this pattern:

```
1. Initial signal (user message, goal request)
   ↓
2. Runner decides, emits Effects
   ↓
3. AgentServer executes Effects
   ↓
4. Completion → new Signal (action_result, llm_result)
   ↓
5. Back to step 2 (runner handles continuation)
   ↓
6. Eventually: mode → :idle, emit Effect.Reply
```

**Key signals for multi-turn:**

| Signal Type | Data | Purpose |
|-------------|------|---------|
| `:action_result` | `%{instruction_id, result, directives}` | Action completed |
| `:action_error` | `%{instruction_id, error}` | Action failed |
| `:llm_result` | `%{result, tool_calls}` | LLM response |
| `:timer_fired` | `%{key, at}` | Scheduled signal |
| `:bt_tick` | `%{}` | Behavior tree tick |

---

## Testing Runners

Runners are pure functions—testing is straightforward.

### Unit Tests

```elixir
test "ReAct runner starts LLM call on user message" do
  state = %MyAgent{
    runner: %{mode: :idle, transcript: [], tools: %{"search" => SearchAction}}
  }
  signal = %Signal{type: :user_message, data: %{text: "Find info about Elixir"}}

  {:ok, new_state, effects} = ReAct.handle(MyAgent, state, signal)

  assert new_state.runner.mode == :waiting_llm
  assert [%Effect.Run{action: LLMChat}] = effects
end
```

### Multi-Turn Scenario Tests

```elixir
test "ReAct completes tool loop" do
  # Step 1: User message
  {:ok, state1, [effect1]} = ReAct.handle(Agent, initial_state(), user_message())
  assert %Effect.Run{action: LLMChat} = effect1

  # Step 2: LLM chooses tool
  llm_result = %Signal{type: :llm_result, data: %{tool_call: {"search", %{q: "elixir"}}}}
  {:ok, state2, [effect2]} = ReAct.handle(Agent, state1, llm_result)
  assert %Effect.Run{action: SearchAction} = effect2

  # Step 3: Tool result
  tool_result = %Signal{type: :action_result, data: %{result: "Elixir is..."}}
  {:ok, state3, [effect3]} = ReAct.handle(Agent, state2, tool_result)
  assert %Effect.Run{action: LLMChat} = effect3

  # Step 4: LLM final answer
  final = %Signal{type: :llm_result, data: %{final_answer: "Elixir is a functional language"}}
  {:ok, state4, [effect4]} = ReAct.handle(Agent, state3, final)
  assert state4.runner.mode == :idle
  assert %Effect.Reply{} = effect4
end
```

### Property Tests

```elixir
property "FSM never reaches invalid state" do
  check all signals <- list_of(signal_generator()) do
    final_state = Enum.reduce(signals, initial_state(), fn signal, state ->
      {:ok, new_state, _} = StateMachine.handle(Agent, state, signal)
      new_state
    end)
    
    assert final_state.status in [:pending, :processing, :completed, :cancelled]
  end
end
```

---

## Runner Selection Guide

| Runner | Best For | Complexity | LLM? |
|--------|----------|------------|------|
| Simple | Manual control, simple logic | Low | No |
| StateMachine | Deterministic workflows | Low-Med | No |
| ChainOfThought | Reasoning tasks, analysis | Med | Yes |
| ReAct | Tool-using AI assistants | Med-High | Yes |
| BehaviorTree | Reactive AI, game agents | High | Optional |
| HTN | Goal-oriented planning | High | Optional |

---

## Kernel vs Battery

**Kernel:**
- `Jido.Agent.Runner` behaviour
- `Jido.Agent.Runner.Simple`
- `Jido.Agent.Runner.StateMachine`

**Battery:**
- `Jido.Agent.Runner.ChainOfThought`
- `Jido.Agent.Runner.ReAct`
- `Jido.Agent.Runner.BehaviorTree` (via `jido_behaviortree`)
- `Jido.Agent.Runner.HTN` (via `jido_htn`)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | Dec 2024 | Initial runners specification |

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*
