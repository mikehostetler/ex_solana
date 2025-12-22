# WS-6.1.1: Persisted Session Schema

**Branch:** `feature/ws-6.1.1-persisted-session-schema`
**Phase:** 6 - Session Persistence
**Task:** 6.1.1 - Persisted Session Schema

---

## Objective

Define the schema for persisted session data, including types for sessions, messages, and todos, with schema versioning for future migrations.

---

## Implementation Plan

### 1. Create Persistence Module (6.1.1.1)
- Create `lib/jido_code/session/persistence.ex`
- Add moduledoc explaining the purpose

### 2. Define persisted_session Type (6.1.1.2)
```elixir
@type persisted_session :: %{
  version: pos_integer(),        # Schema version for migrations
  id: String.t(),
  name: String.t(),
  project_path: String.t(),
  config: map(),
  created_at: String.t(),        # ISO 8601
  updated_at: String.t(),        # ISO 8601
  closed_at: String.t(),         # ISO 8601
  conversation: [persisted_message()],
  todos: [persisted_todo()]
}
```

### 3. Define persisted_message Type (6.1.1.3)
```elixir
@type persisted_message :: %{
  id: String.t(),
  role: String.t(),
  content: String.t(),
  timestamp: String.t()          # ISO 8601
}
```

### 4. Define persisted_todo Type (6.1.1.4)
```elixir
@type persisted_todo :: %{
  content: String.t(),
  status: String.t(),
  active_form: String.t()
}
```

### 5. Document Schema Version (6.1.1.5)
- Current version: 1
- Add @schema_version module attribute
- Document version history in moduledoc

### 6. Write Unit Tests (6.1.1.6)
- Create `test/jido_code/session/persistence_test.exs`
- Test schema validation functions
- Test type specifications match expected format

---

## Files to Create/Modify

**New Files:**
- `lib/jido_code/session/persistence.ex` - Schema definitions
- `test/jido_code/session/persistence_test.exs` - Unit tests

**Modified Files:**
- `notes/planning/work-session/phase-06.md` - Mark task complete

---

## Success Criteria

1. Persistence module created with proper documentation
2. All three types defined with correct specs
3. Schema version documented
4. Unit tests passing
5. No credo issues introduced
