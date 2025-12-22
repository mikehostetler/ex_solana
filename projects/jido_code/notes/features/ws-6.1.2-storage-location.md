# WS-6.1.2: Storage Location

**Branch:** `feature/ws-6.1.2-storage-location`
**Phase:** 6 - Session Persistence
**Task:** 6.1.2 - Storage Location

---

## Objective

Define storage locations for persisted sessions, including directory path functions and file naming conventions.

---

## Implementation Plan

### 1. Define Sessions Directory (6.1.2.1)
- Location: `~/.jido_code/sessions/`
- Expand `~` to user's home directory

### 2. Define Session File Pattern (6.1.2.2)
- Pattern: `{session_id}.json`
- Example: `abc123.json`

### 3. Implement sessions_dir/0 (6.1.2.3)
```elixir
@spec sessions_dir() :: String.t()
def sessions_dir do
  Path.join([System.user_home!(), ".jido_code", "sessions"])
end
```

### 4. Implement session_file/1 (6.1.2.4)
```elixir
@spec session_file(String.t()) :: String.t()
def session_file(session_id) when is_binary(session_id) do
  Path.join(sessions_dir(), "#{session_id}.json")
end
```

### 5. Implement ensure_sessions_dir/0 (6.1.2.5)
```elixir
@spec ensure_sessions_dir() :: :ok | {:error, term()}
def ensure_sessions_dir do
  dir = sessions_dir()
  case File.mkdir_p(dir) do
    :ok -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

### 6. Write Unit Tests (6.1.2.6)
- Test `sessions_dir/0` returns correct path
- Test `session_file/1` returns correct file path
- Test `ensure_sessions_dir/0` creates directory

---

## Files to Modify

**Modified Files:**
- `lib/jido_code/session/persistence.ex` - Add path functions
- `test/jido_code/session/persistence_test.exs` - Add path tests

---

## Success Criteria

1. `sessions_dir/0` returns expanded path to sessions directory
2. `session_file/1` returns full path for session JSON file
3. `ensure_sessions_dir/0` creates directory if missing
4. All unit tests passing
5. No credo issues
