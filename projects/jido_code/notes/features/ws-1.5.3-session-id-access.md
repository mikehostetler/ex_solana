# Feature: WS-1.5.3 Session ID Access

## Problem Statement

After Task 1.5.2, a default session is automatically created on startup. Users and other modules need an easy way to access the default/active session ID without having to list all sessions and pick the first one.

## Implementation Plan

### Step 1: Implement get_default_session_id/0
- [x] Add `get_default_session_id/0` to SessionRegistry module
- [x] Use existing `list_ids/0` and take first element
- [x] Handle empty registry case (return `{:error, :no_sessions}`)

### Step 2: Write Unit Tests
- [x] Test returns first session ID when sessions exist
- [x] Test returns error when registry is empty
- [x] Test returns correct ID after default session created
- [x] Test returns oldest session ID when multiple exist
- [x] Test returns string ID
- [x] Test returns error after clear

## Technical Details

### Location
`lib/jido_code/session_registry.ex`

### API
```elixir
@doc """
Returns the ID of the default (first) session.

The default session is the oldest session in the registry (first by created_at).
This is typically the session created automatically on application startup.

## Returns

- `{:ok, session_id}` - The default session ID
- `{:error, :no_sessions}` - No sessions registered

## Examples

    iex> {:ok, session_id} = SessionRegistry.get_default_session_id()
    iex> is_binary(session_id)
    true

    iex> SessionRegistry.clear()
    iex> SessionRegistry.get_default_session_id()
    {:error, :no_sessions}
"""
@spec get_default_session_id() :: {:ok, String.t()} | {:error, :no_sessions}
def get_default_session_id do
  case list_ids() do
    [first | _] -> {:ok, first}
    [] -> {:error, :no_sessions}
  end
end
```

## Success Criteria

- [x] `get_default_session_id/0` returns first session ID
- [x] Empty registry returns `{:error, :no_sessions}`
- [x] Unit tests pass (6 tests)

## Current Status

**Status**: Complete
