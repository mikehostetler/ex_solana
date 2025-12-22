# WS-6.2.2: Auto-Save on Close

**Branch:** `feature/ws-6.2.2-auto-save-on-close`
**Phase:** 6 - Session Persistence
**Task:** 6.2.2 - Auto-Save on Close

---

## Objective

Integrate session saving with the session close flow so sessions are automatically persisted when closed.

---

## Implementation Plan

### 1. Update stop_session/1 (6.2.2.1)

Modify `SessionSupervisor.stop_session/1` to save before stopping:

```elixir
def stop_session(session_id) do
  # Save session before stopping (best effort)
  save_session_before_close(session_id)

  # Then stop processes
  with {:ok, pid} <- find_session_pid(session_id),
       :ok <- DynamicSupervisor.terminate_child(__MODULE__, pid) do
    SessionRegistry.unregister(session_id)
    :ok
  end
end

defp save_session_before_close(session_id) do
  case Persistence.save(session_id) do
    {:ok, path} ->
      Logger.info("Session #{session_id} saved to #{path}")
      :ok
    {:error, reason} ->
      Logger.warning("Failed to save session #{session_id}: #{inspect(reason)}")
      :error
  end
end
```

### 2. Log save success/failure (6.2.2.2)
- Log info on successful save with file path
- Log warning on save failure with reason

### 3. Continue with stop even if save fails (6.2.2.3)
- Save is best-effort, never blocks session close
- Use separate function to isolate save errors

### 4. Write integration tests (6.2.2.4)
- Test session close triggers save
- Test save failure doesn't block close
- Test saved file contains session data

---

## Files to Modify

**Modified Files:**
- `lib/jido_code/session_supervisor.ex` - Add save before stop
- `test/jido_code/session_supervisor_test.exs` - Add auto-save tests

---

## Success Criteria

1. Session close triggers automatic save
2. Save success/failure is logged appropriately
3. Close completes even if save fails
4. All tests passing
5. No credo issues
