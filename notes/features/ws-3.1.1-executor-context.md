# Feature: WS-3.1.1 Executor Context Enhancement

## Problem Statement

The Tools.Executor currently accepts an optional session_id for PubSub routing, but it doesn't enforce session context for tool execution. Tool handlers need session_id in the context to use Session.Manager for path validation and security boundaries.

Task 3.1.1 requires:
1. Update context type to include session_id
2. Validate session_id presence in execute/2
3. Return error for missing session_id
4. Fetch project_root from Session.Manager if not in context
5. Document context requirements

## Solution Overview

Enhance the Executor to:
1. Define a proper context type that includes session_id
2. Add a `build_context/2` helper function to create context from session_id
3. Auto-populate project_root from Session.Manager when session_id is provided
4. Maintain backwards compatibility by allowing legacy context without session_id (with deprecation warning)

## Technical Details

### Files to Modify

- `lib/jido_code/tools/executor.ex` - Add context type, build_context helper, validation
- `test/jido_code/tools/executor_test.exs` - Add tests for context handling

### New/Updated Types

```elixir
@typedoc """
Execution context passed to tool handlers.

## Required Fields

- `:session_id` - Session identifier for security boundaries

## Optional Fields

- `:project_root` - Project root path (auto-populated from Session.Manager if not provided)
- `:timeout` - Execution timeout override
"""
@type context :: %{
  required(:session_id) => String.t(),
  optional(:project_root) => String.t(),
  optional(:timeout) => pos_integer()
}
```

### New Function

```elixir
@doc """
Builds an execution context from a session ID.

Fetches project_root from Session.Manager and constructs a complete
context map suitable for tool execution.
"""
@spec build_context(String.t(), keyword()) :: {:ok, context()} | {:error, :not_found}
def build_context(session_id, opts \\ []) do
  with {:ok, project_root} <- Session.Manager.project_root(session_id) do
    {:ok, %{
      session_id: session_id,
      project_root: project_root,
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }}
  end
end
```

## Implementation Plan

### Step 1: Update context type definition
- [x] Add @type context with session_id as required field
- [x] Update @typedoc with field descriptions

### Step 2: Add build_context/2 helper
- [x] Implement build_context/2 function
- [x] Fetch project_root from Session.Manager
- [x] Allow timeout override via opts
- [x] Handle missing session gracefully

### Step 3: Update execute/2 to use context
- [x] Extract session_id from context (not opts)
- [x] Auto-populate project_root if session_id provided but project_root missing
- [x] Log deprecation warning if session_id not in context

### Step 4: Update documentation
- [x] Update @moduledoc with context requirements
- [x] Add examples showing build_context usage

### Step 5: Write tests
- [x] Test build_context/2 with valid session
- [x] Test build_context/2 with invalid session
- [x] Test execute/2 uses session_id from context
- [x] Test execute/2 auto-populates project_root

## Success Criteria

- [x] `build_context/2` creates valid context from session_id
- [x] `build_context/2` returns error for invalid session_id
- [x] Context includes project_root from Session.Manager
- [x] Backwards compatibility maintained
- [x] All existing tests pass
- [x] New tests cover context handling

## Current Status

**Status**: Complete
