# Jido 2.0 Effect Batching & Organization Specification

> How to organize, prioritize, and execute large numbers of Effects efficiently.

---

## Overview

When `handle_signal/2` returns many Effects (20+), the system needs conventions for:
- **Grouping** related effects for atomic handling
- **Ordering** effects with dependencies
- **Parallelization** of independent effects
- **Prioritization** of urgent work
- **Cancellation** of obsolete effects
- **Deduplication** of redundant work

This specification defines `Effect.Meta`—metadata that enables intelligent effect orchestration.

---

## The Problem

Consider an HTN runner that decomposes a goal into 25 primitive actions:

```elixir
{:ok, new_state, [
  %Effect.Run{action: ValidateUser},
  %Effect.Run{action: CheckInventory},
  %Effect.Run{action: ReserveItem},
  %Effect.Run{action: ChargePayment},
  %Effect.Run{action: UpdateInventory},
  %Effect.Run{action: SendConfirmation},
  %Effect.Run{action: NotifyWarehouse},
  %Effect.Run{action: UpdateAnalytics},
  # ... 17 more effects
]}
```

**Questions:**
1. Which can run in parallel?
2. What order for sequential ones?
3. If `ChargePayment` fails, should we cancel downstream effects?
4. Are any duplicates?
5. Which are high-priority?

---

## Effect.Meta

All Effect structs gain an optional `meta` field:

```elixir
defmodule Jido.Agent.Effect.Meta do
  @moduledoc """
  Metadata for effect organization and execution hints.
  
  Meta is purely advisory—AgentServer uses it for intelligent
  scheduling but may adjust based on runtime conditions.
  """

  use TypedStruct

  typedstruct do
    # ─────────────────────────────────────────────────────────────
    # Grouping
    # ─────────────────────────────────────────────────────────────
    
    @typedoc "Logical group for batching related effects"
    field :group, term(), default: nil
    # Examples: :validation, :payment, {:phase, 1}, "user_123"
    
    @typedoc "Order within group (lower = earlier)"
    field :order, non_neg_integer(), default: 0

    # ─────────────────────────────────────────────────────────────
    # Execution Mode
    # ─────────────────────────────────────────────────────────────
    
    @typedoc "Execution strategy"
    field :mode, :sequential | :parallel, default: :sequential
    # :sequential - wait for previous effect before starting
    # :parallel - may run concurrently with other parallel effects
    
    @typedoc "Priority (higher = more urgent, 0 = normal)"
    field :priority, 0..100, default: 0
    # 100 = critical, run immediately
    # 50 = high priority
    # 0 = normal
    # AgentServer may process high-priority groups first

    # ─────────────────────────────────────────────────────────────
    # Dependencies & Cancellation
    # ─────────────────────────────────────────────────────────────
    
    @typedoc "Groups to cancel when this effect is queued"
    field :cancels, [term()], default: []
    # Example: cancels: [:previous_search] - cancel any pending search effects
    
    @typedoc "Groups this effect depends on (wait for completion)"
    field :depends_on, [term()], default: []
    # Example: depends_on: [:validation] - wait for validation group to complete
    
    @typedoc "Behavior on failure of dependency"
    field :on_dep_failure, :skip | :error | :continue, default: :error
    # :skip - silently skip this effect
    # :error - propagate error
    # :continue - run anyway

    # ─────────────────────────────────────────────────────────────
    # Deduplication
    # ─────────────────────────────────────────────────────────────
    
    @typedoc "Idempotency key for deduplication"
    field :idempotency_key, term(), default: nil
    # Effects with same key are deduplicated
    # nil = no deduplication
    
    @typedoc "Deduplication strategy"
    field :dedup_strategy, :first | :last | :merge, default: :first
    # :first - keep first occurrence, drop later ones
    # :last - replace with last occurrence
    # :merge - merge params (Action-specific)

    # ─────────────────────────────────────────────────────────────
    # Tagging & Debugging
    # ─────────────────────────────────────────────────────────────
    
    @typedoc "Tags for filtering and debugging"
    field :tags, [atom()], default: []
    # Examples: [:io_bound, :llm, :critical, :cleanup]
    
    @typedoc "Human-readable description"
    field :description, String.t() | nil, default: nil
  end
end
```

---

## Updated Effect Structs

All Effect types include `meta`:

```elixir
defmodule Jido.Agent.Effect.Run do
  use TypedStruct

  typedstruct do
    field :action, module(), enforce: true
    field :params, map(), default: %{}
    field :context, map(), default: %{}
    field :opts, keyword(), default: []
    field :meta, Effect.Meta.t() | nil, default: nil  # NEW
  end
end

defmodule Jido.Agent.Effect.Emit do
  use TypedStruct

  typedstruct do
    field :type, String.t(), enforce: true
    field :data, map(), default: %{}
    field :source, String.t() | nil
    field :bus, atom(), default: :default
    field :meta, Effect.Meta.t() | nil, default: nil  # NEW
  end
end

# Similar for all Effect types...
```

---

## Grouping Patterns

### Phase-Based Grouping

Organize effects into logical phases:

```elixir
[
  # Phase 1: Validation (parallel)
  %Effect.Run{
    action: ValidateUser,
    meta: %Meta{group: {:phase, 1}, mode: :parallel}
  },
  %Effect.Run{
    action: ValidateInventory,
    meta: %Meta{group: {:phase, 1}, mode: :parallel}
  },
  
  # Phase 2: Core Transaction (sequential, depends on phase 1)
  %Effect.Run{
    action: ReserveItem,
    meta: %Meta{group: {:phase, 2}, order: 1, depends_on: [{:phase, 1}]}
  },
  %Effect.Run{
    action: ChargePayment,
    meta: %Meta{group: {:phase, 2}, order: 2}
  },
  
  # Phase 3: Notifications (parallel, lower priority)
  %Effect.Run{
    action: SendEmail,
    meta: %Meta{group: {:phase, 3}, mode: :parallel, priority: 0, depends_on: [{:phase, 2}]}
  },
  %Effect.Run{
    action: NotifySlack,
    meta: %Meta{group: {:phase, 3}, mode: :parallel, priority: 0}
  }
]
```

### Channel-Based Grouping

Group by resource type:

```elixir
[
  # Database operations (sequential to avoid conflicts)
  %Effect.Run{
    action: UpdateUser,
    meta: %Meta{group: :database, order: 1}
  },
  %Effect.Run{
    action: UpdateOrder,
    meta: %Meta{group: :database, order: 2}
  },
  
  # External APIs (parallel, they're independent)
  %Effect.Run{
    action: CallStripe,
    meta: %Meta{group: :external_api, mode: :parallel}
  },
  %Effect.Run{
    action: CallShippo,
    meta: %Meta{group: :external_api, mode: :parallel}
  },
  
  # LLM calls (sequential to manage costs/rate limits)
  %Effect.Run{
    action: LLMChat,
    meta: %Meta{group: :llm, priority: 10}
  }
]
```

---

## Dependency Patterns

### Linear Dependencies

```elixir
[
  %Effect.Run{action: Step1, meta: %Meta{group: :a}},
  %Effect.Run{action: Step2, meta: %Meta{group: :b, depends_on: [:a]}},
  %Effect.Run{action: Step3, meta: %Meta{group: :c, depends_on: [:b]}}
]
```

### Fan-Out / Fan-In

```elixir
[
  # Start: single action
  %Effect.Run{action: Initialize, meta: %Meta{group: :init}},
  
  # Fan-out: parallel work
  %Effect.Run{action: WorkerA, meta: %Meta{group: :workers, mode: :parallel, depends_on: [:init]}},
  %Effect.Run{action: WorkerB, meta: %Meta{group: :workers, mode: :parallel, depends_on: [:init]}},
  %Effect.Run{action: WorkerC, meta: %Meta{group: :workers, mode: :parallel, depends_on: [:init]}},
  
  # Fan-in: aggregate results
  %Effect.Run{action: Aggregate, meta: %Meta{group: :final, depends_on: [:workers]}}
]
```

---

## Cancellation Patterns

### Cancel on New Request

When a new search starts, cancel any pending search:

```elixir
# User types "elixir" then quickly types "elixir lang"
# Second search should cancel first

%Effect.Run{
  action: SearchAction,
  params: %{query: "elixir lang"},
  meta: %Meta{
    group: {:search, "user_123"},
    cancels: [{:search, "user_123"}]  # Cancel previous search for this user
  }
}
```

### Cancel Downstream on Failure

HTN runner can mark effects to skip if upstream fails:

```elixir
[
  %Effect.Run{
    action: ChargePayment,
    meta: %Meta{group: :payment}
  },
  %Effect.Run{
    action: SendReceipt,
    meta: %Meta{
      group: :notification,
      depends_on: [:payment],
      on_dep_failure: :skip  # Don't send receipt if payment failed
    }
  }
]
```

---

## Deduplication Patterns

### Idempotency Keys

Prevent duplicate effects during retries or race conditions:

```elixir
%Effect.Run{
  action: ChargePayment,
  params: %{order_id: "order_123", amount: 99.99},
  meta: %Meta{
    idempotency_key: {"charge", "order_123"},
    dedup_strategy: :first  # Only charge once
  }
}

%Effect.Emit{
  type: "order.created",
  data: %{order_id: "order_123"},
  meta: %Meta{
    idempotency_key: {"event", "order_created", "order_123"},
    dedup_strategy: :first
  }
}
```

### Last-Wins Deduplication

For state updates, use last value:

```elixir
# Multiple status updates, only apply last one
[
  %Effect.StateModification{path: [:status], value: :processing, 
    meta: %Meta{idempotency_key: :status_update, dedup_strategy: :last}},
  %Effect.StateModification{path: [:status], value: :validating,
    meta: %Meta{idempotency_key: :status_update, dedup_strategy: :last}},
  %Effect.StateModification{path: [:status], value: :complete,
    meta: %Meta{idempotency_key: :status_update, dedup_strategy: :last}}
]
# Result: only {:status, :complete} is applied
```

---

## Priority Patterns

### Critical Path Optimization

Prioritize effects on the critical path:

```elixir
[
  # Critical: user is waiting for response
  %Effect.Run{
    action: GenerateResponse,
    meta: %Meta{priority: 100, tags: [:critical, :user_facing]}
  },
  
  # High: affects business logic
  %Effect.Run{
    action: UpdateInventory,
    meta: %Meta{priority: 50, tags: [:business_logic]}
  },
  
  # Normal: analytics, logging
  %Effect.Run{
    action: LogAnalytics,
    meta: %Meta{priority: 0, tags: [:analytics]}
  },
  
  # Low: cleanup, can be deferred
  %Effect.Run{
    action: CleanupTempFiles,
    meta: %Meta{priority: 0, tags: [:cleanup]}
  }
]
```

---

## AgentServer Execution Algorithm

AgentServer processes effects using meta information:

```elixir
defmodule Jido.AgentServer.EffectExecutor do
  @moduledoc "Executes effects respecting Meta constraints."

  def execute_effects(effects, state) do
    effects
    |> deduplicate()
    |> apply_cancellations(state)
    |> build_dependency_graph()
    |> topological_sort_with_groups()
    |> execute_groups(state)
  end

  defp deduplicate(effects) do
    effects
    |> Enum.group_by(& &1.meta && &1.meta.idempotency_key)
    |> Enum.flat_map(fn
      {nil, effects} -> effects  # No key, keep all
      {_key, [single]} -> [single]  # Single occurrence
      {_key, duplicates} -> resolve_duplicates(duplicates)
    end)
  end

  defp resolve_duplicates(effects) do
    strategy = hd(effects).meta.dedup_strategy
    case strategy do
      :first -> [hd(effects)]
      :last -> [List.last(effects)]
      :merge -> [merge_effects(effects)]
    end
  end

  defp build_dependency_graph(effects) do
    # Build DAG from group dependencies
    # Returns {effects, graph}
  end

  defp topological_sort_with_groups({effects, graph}) do
    # Sort respecting:
    # 1. Group dependencies (depends_on)
    # 2. Within-group order
    # 3. Priority (higher priority groups first)
  end

  defp execute_groups(sorted_groups, state) do
    Enum.reduce(sorted_groups, state, fn group, acc_state ->
      mode = group_mode(group)
      case mode do
        :parallel -> execute_parallel(group.effects, acc_state)
        :sequential -> execute_sequential(group.effects, acc_state)
      end
    end)
  end
end
```

---

## Execution Result Signals

AgentServer reports effect completion via signals:

```elixir
# Individual effect completed
%Signal{
  type: :effect_completed,
  data: %{
    effect_id: "eff_123",
    group: {:phase, 1},
    result: %{...},
    duration_ms: 150
  }
}

# Group completed
%Signal{
  type: :group_completed,
  data: %{
    group: {:phase, 1},
    results: %{
      "eff_123" => {:ok, result1},
      "eff_124" => {:ok, result2}
    }
  }
}

# Effect cancelled
%Signal{
  type: :effect_cancelled,
  data: %{
    effect_id: "eff_125",
    reason: :superseded,
    cancelled_by: "eff_126"
  }
}
```

---

## Helper Functions

### Building Meta

```elixir
defmodule Jido.Agent.Effect.Meta do
  @doc "Create meta for sequential group"
  def sequential(group, opts \\ []) do
    %__MODULE__{
      group: group,
      mode: :sequential,
      order: Keyword.get(opts, :order, 0),
      priority: Keyword.get(opts, :priority, 0)
    }
  end

  @doc "Create meta for parallel group"
  def parallel(group, opts \\ []) do
    %__MODULE__{
      group: group,
      mode: :parallel,
      priority: Keyword.get(opts, :priority, 0)
    }
  end

  @doc "Create meta with dependencies"
  def after_group(group, depends_on, opts \\ []) do
    %__MODULE__{
      group: group,
      depends_on: List.wrap(depends_on),
      on_dep_failure: Keyword.get(opts, :on_failure, :error)
    }
  end
end
```

### Effect Batching DSL

```elixir
defmodule Jido.Agent.Effect.Batch do
  @doc "Group effects into phases"
  def phases(effect_lists) do
    effect_lists
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {effects, phase_num} ->
      prev_phase = if phase_num > 1, do: [{:phase, phase_num - 1}], else: []
      
      Enum.map(effects, fn effect ->
        meta = (effect.meta || %Meta{})
        |> Map.put(:group, {:phase, phase_num})
        |> Map.put(:depends_on, prev_phase)
        
        %{effect | meta: meta}
      end)
    end)
  end

  @doc "Mark effects as parallel within their group"
  def parallel(effects) do
    Enum.map(effects, fn effect ->
      meta = (effect.meta || %Meta{}) |> Map.put(:mode, :parallel)
      %{effect | meta: meta}
    end)
  end
end

# Usage:
effects = Batch.phases([
  # Phase 1: Validation (parallel)
  Batch.parallel([
    %Effect.Run{action: ValidateA},
    %Effect.Run{action: ValidateB}
  ]),
  
  # Phase 2: Core (sequential)
  [
    %Effect.Run{action: Process},
    %Effect.Run{action: Save}
  ],
  
  # Phase 3: Notifications (parallel)
  Batch.parallel([
    %Effect.Run{action: NotifyA},
    %Effect.Run{action: NotifyB}
  ])
])
```

---

## Best Practices

### 1. Use Groups Sparingly
Don't over-engineer. For <5 effects, flat list is fine.

### 2. Prefer Coarse Groups
Use 2-5 groups (phases/channels), not one per effect.

### 3. Explicit Dependencies > Implicit Ordering
Use `depends_on` rather than relying on list order.

### 4. Idempotency for Side Effects
Always set `idempotency_key` for payments, notifications, external APIs.

### 5. Tags for Observability
Use tags liberally—they help with debugging and filtering.

### 6. Reasonable Defaults
When meta is nil, AgentServer uses safe defaults:
- `mode: :sequential`
- `priority: 0`
- No cancellation or deduplication

---

## Kernel vs Battery

**Kernel:**
- `Effect.Meta` struct definition
- Basic deduplication in AgentServer
- Sequential execution by default

**Battery:**
- Advanced parallel execution
- Group-based scheduling
- Cancellation tracking
- Dependency graph resolution

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | Dec 2024 | Initial effect batching specification |

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*
