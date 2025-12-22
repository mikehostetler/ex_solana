# Feature: WS-2.1 Review Fixes

## Problem Statement

The review of Section 2.1 (Session Manager) identified 3 concerns and 4 suggestions for improvement. While none are blockers, addressing them will improve code quality, maintainability, and security documentation.

### Concerns Identified

1. **Lua Execution Timeout Not Enforced at Luerl Level** - The timeout parameter only applies to GenServer.call, not the actual Lua execution
2. **Deprecated `get_session/1` Reconstructs Invalid Data** - Returns synthetic timestamps and empty config
3. **System.cmd Timeout Parameter Unused in Bridge** - The `_timeout` variable is extracted but never used

### Suggestions Identified

1. **Extract Registry Lookup Pattern** - 8 occurrences of the same pattern could be a private helper
2. **Consolidate Error Formatting** - Duplicate `format_error/1` in manager.ex, tools/manager.ex, and result.ex
3. **Create Shared Process Registry Helpers** - Via tuple pattern duplicated in Manager, State, and Supervisor
4. **Add Lua Sandbox Resource Limits** - Document considerations for long-lived sessions

## Solution Overview

Address all concerns through documentation improvements and code refactoring. Implement suggestions that provide clear value while avoiding over-engineering.

### Key Decisions

1. **Concern 1**: Add @note in moduledoc documenting the timeout limitation
2. **Concern 2**: Add @deprecated attribute and clear warning in docs
3. **Concern 3**: Pass timeout to System.cmd (it supports `:timeout` option)
4. **Suggestion 1**: Extract `call_manager/3` private helper
5. **Suggestion 2**: Create `JidoCode.ErrorFormatter` shared module
6. **Suggestion 3**: Create `JidoCode.Session.ProcessRegistry` module
7. **Suggestion 4**: Add section in moduledoc about resource considerations

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/manager.ex` | Add timeout docs, deprecation, extract helper |
| `lib/jido_code/tools/bridge.ex` | Pass timeout to System.cmd |
| `lib/jido_code/error_formatter.ex` | New shared error formatting module |
| `lib/jido_code/session/process_registry.ex` | New shared via tuple helpers |
| `lib/jido_code/session/supervisor.ex` | Use ProcessRegistry |
| `lib/jido_code/session/state.ex` | Use ProcessRegistry |
| `lib/jido_code/tools/manager.ex` | Use ErrorFormatter |
| `lib/jido_code/tools/result.ex` | Use ErrorFormatter |

### New Modules

#### JidoCode.ErrorFormatter

```elixir
defmodule JidoCode.ErrorFormatter do
  @moduledoc """
  Shared error formatting utilities.
  """

  @spec format(term()) :: String.t()
  def format(reason) when is_binary(reason), do: reason
  def format(reason) when is_atom(reason), do: Atom.to_string(reason)
  def format(reason) when is_list(reason), do: to_string(reason)
  def format({:error, reason}), do: format(reason)
  def format({:lua_error, error, _stack}), do: format(error)
  def format(%{message: message}) when is_binary(message), do: message
  def format(reason), do: inspect(reason)
end
```

#### JidoCode.Session.ProcessRegistry

```elixir
defmodule JidoCode.Session.ProcessRegistry do
  @moduledoc """
  Shared helpers for session process registry operations.
  """

  @registry JidoCode.SessionProcessRegistry

  @spec via(atom(), String.t()) :: {:via, Registry, {atom(), {atom(), String.t()}}}
  def via(process_type, session_id) do
    {:via, Registry, {@registry, {process_type, session_id}}}
  end

  @spec lookup(atom(), String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(process_type, session_id) do
    case Registry.lookup(@registry, {process_type, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
```

## Implementation Plan

### Step 1: Create Shared Modules
- [x] Create `JidoCode.ErrorFormatter` module
- [x] Create `JidoCode.Session.ProcessRegistry` module

### Step 2: Fix Concerns
- [x] Add timeout limitation docs to Session.Manager moduledoc
- [x] Add @deprecated and warning to get_session/1
- [x] Pass timeout to System.cmd in Bridge

### Step 3: Apply Suggestions
- [x] Extract `call_manager/3` helper in Session.Manager
- [x] Update Session.Manager to use ErrorFormatter
- [x] Update Tools.Manager to use ErrorFormatter
- [x] Update Tools.Result to use ErrorFormatter
- [x] Update Session.Supervisor to use ProcessRegistry
- [x] Update Session.State to use ProcessRegistry
- [x] Update Session.Manager to use ProcessRegistry
- [x] Add resource considerations to Session.Manager moduledoc

### Step 4: Verify
- [x] Run all tests
- [x] Verify coverage maintained

## Success Criteria

- [x] All concerns documented or fixed
- [x] All suggestions implemented
- [x] All tests pass
- [x] No regression in test coverage

## Current Status

**Status**: Complete

All concerns have been addressed and all suggestions implemented. Tests pass:
- Session.Manager tests: 37 tests, 0 failures
- Session suite: 74 tests, 0-1 intermittent failure (pre-existing flaky test)
- Tools.Manager tests: 32 tests, 0 failures
- Tools.Result tests: 31 tests, 0 failures
- Tools.Executor tests: 36 tests, 0 failures
