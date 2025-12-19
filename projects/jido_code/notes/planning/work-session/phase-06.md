# Phase 6: Session Persistence

This phase implements session persistence, allowing sessions to be saved to disk and restored via the `/resume` command. Sessions are not automatically restored on startup—users must explicitly request restoration.

---

## 6.1 Persistence Data Structure

Define the data structures and file formats for persisted sessions.

### 6.1.1 Persisted Session Schema
- [ ] **Task 6.1.1**

Define the schema for persisted session data.

- [ ] 6.1.1.1 Create `lib/jido_code/session/persistence.ex` module
- [ ] 6.1.1.2 Define `@type persisted_session()`:
  ```elixir
  @type persisted_session :: %{
    version: pos_integer(),        # Schema version for migrations
    id: String.t(),
    name: String.t(),
    project_path: String.t(),
    config: config(),
    created_at: String.t(),        # ISO 8601
    updated_at: String.t(),        # ISO 8601
    closed_at: String.t(),         # ISO 8601
    conversation: [persisted_message()],
    todos: [persisted_todo()]
  }
  ```
- [ ] 6.1.1.3 Define `@type persisted_message()`:
  ```elixir
  @type persisted_message :: %{
    id: String.t(),
    role: String.t(),
    content: String.t(),
    timestamp: String.t()
  }
  ```
- [ ] 6.1.1.4 Define `@type persisted_todo()`:
  ```elixir
  @type persisted_todo :: %{
    content: String.t(),
    status: String.t(),
    active_form: String.t()
  }
  ```
- [ ] 6.1.1.5 Document schema version for future migrations
- [ ] 6.1.1.6 Write unit tests for schema types

### 6.1.2 Storage Location
- [ ] **Task 6.1.2**

Define storage locations for persisted sessions.

- [ ] 6.1.2.1 Define sessions directory: `~/.jido_code/sessions/`
- [ ] 6.1.2.2 Define session file pattern: `{session_id}.json`
- [ ] 6.1.2.3 Implement `sessions_dir/0` returning expanded path
- [ ] 6.1.2.4 Implement `session_file/1` returning file path for session ID
- [ ] 6.1.2.5 Implement `ensure_sessions_dir/0` creating directory if missing
- [ ] 6.1.2.6 Write unit tests for path functions

**Unit Tests for Section 6.1:**
- Test persisted_session schema matches expected format
- Test persisted_message schema matches expected format
- Test `sessions_dir/0` returns correct path
- Test `session_file/1` returns correct file path
- Test `ensure_sessions_dir/0` creates directory

---

## 6.2 Session Saving

Implement saving sessions to disk.

### 6.2.1 Save Session State
- [ ] **Task 6.2.1**

Implement saving session to JSON file.

- [ ] 6.2.1.1 Implement `save/1` accepting session_id:
  ```elixir
  def save(session_id) do
    with {:ok, session} <- SessionRegistry.lookup(session_id),
         {:ok, state} <- get_session_state(session_id),
         persisted = build_persisted_session(session, state),
         :ok <- write_session_file(persisted) do
      {:ok, session_file(session_id)}
    end
  end
  ```
- [ ] 6.2.1.2 Implement `build_persisted_session/2`:
  ```elixir
  defp build_persisted_session(session, state) do
    %{
      version: 1,
      id: session.id,
      name: session.name,
      project_path: session.project_path,
      config: session.config,
      created_at: DateTime.to_iso8601(session.created_at),
      updated_at: DateTime.to_iso8601(session.updated_at),
      closed_at: DateTime.to_iso8601(DateTime.utc_now()),
      conversation: Enum.map(state.messages, &serialize_message/1),
      todos: Enum.map(state.todos, &serialize_todo/1)
    }
  end
  ```
- [ ] 6.2.1.3 Write JSON atomically (temp file then rename)
- [ ] 6.2.1.4 Handle write errors gracefully
- [ ] 6.2.1.5 Write unit tests for save function

### 6.2.2 Auto-Save on Close
- [ ] **Task 6.2.2**

Integrate save with session close flow.

- [ ] 6.2.2.1 Update `SessionSupervisor.stop_session/1` to save first:
  ```elixir
  def stop_session(session_id) do
    # Save before stopping
    Persistence.save(session_id)
    # Then stop processes
    terminate_session_processes(session_id)
  end
  ```
- [ ] 6.2.2.2 Log save success/failure
- [ ] 6.2.2.3 Continue with stop even if save fails
- [ ] 6.2.2.4 Write integration tests for auto-save

### 6.2.3 Manual Save Command
- [ ] **Task 6.2.3**

Implement `/session save` command (optional).

- [ ] 6.2.3.1 Add `save` subcommand to session commands
- [ ] 6.2.3.2 Implement `execute_session({:save, target}, model)`:
  ```elixir
  def execute_session({:save, target}, model) do
    session_id = target || model.active_session_id
    case Persistence.save(session_id) do
      {:ok, path} -> {:ok, "Session saved to: #{path}", :no_change}
      {:error, reason} -> {:error, "Failed to save: #{reason}"}
    end
  end
  ```
- [ ] 6.2.3.3 Write unit tests for save command

**Unit Tests for Section 6.2:**
- Test `save/1` creates JSON file
- Test save includes all session data
- Test save includes conversation history
- Test save includes todo list
- Test save writes atomically
- Test session close triggers auto-save
- Test `/session save` command works

---

## 6.3 Session Listing (Persisted)

Implement listing persisted sessions for resume.

### 6.3.1 List Persisted Sessions
- [ ] **Task 6.3.1**

Implement listing all persisted sessions.

- [ ] 6.3.1.1 Implement `list_persisted/0`:
  ```elixir
  def list_persisted do
    sessions_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&load_session_metadata/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.closed_at, {:desc, DateTime})
  end
  ```
- [ ] 6.3.1.2 Implement `load_session_metadata/1` (load minimal info):
  ```elixir
  defp load_session_metadata(filename) do
    path = Path.join(sessions_dir(), filename)
    case File.read(path) do
      {:ok, content} ->
        Jason.decode!(content)
        |> Map.take([:id, :name, :project_path, :closed_at])
      {:error, _} -> nil
    end
  end
  ```
- [ ] 6.3.1.3 Sort by closed_at (most recent first)
- [ ] 6.3.1.4 Handle corrupted files gracefully
- [ ] 6.3.1.5 Write unit tests for listing

### 6.3.2 Filter Active Sessions
- [ ] **Task 6.3.2**

Exclude already-active sessions from persisted list.

- [ ] 6.3.2.1 Implement `list_resumable/0`:
  ```elixir
  def list_resumable do
    active_ids = SessionRegistry.list_ids()
    list_persisted()
    |> Enum.reject(& &1.id in active_ids)
  end
  ```
- [ ] 6.3.2.2 Also exclude sessions with same project_path as active
- [ ] 6.3.2.3 Write unit tests for filtering

**Unit Tests for Section 6.3:**
- Test `list_persisted/0` finds all JSON files
- Test listing handles corrupted files
- Test listing sorted by closed_at descending
- Test `list_resumable/0` excludes active sessions
- Test filtering excludes duplicate project paths

---

## 6.4 Session Restoration

Implement restoring sessions from persisted state.

### 6.4.1 Load Persisted Session
- [ ] **Task 6.4.1**

Implement loading full session data from file.

- [ ] 6.4.1.1 Implement `load/1` accepting session_id:
  ```elixir
  def load(session_id) do
    path = session_file(session_id)
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content),
         {:ok, session} <- deserialize_session(data) do
      {:ok, session}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, {:invalid_file, reason}}
    end
  end
  ```
- [ ] 6.4.1.2 Implement `deserialize_session/1` converting JSON to structs
- [ ] 6.4.1.3 Handle schema version migrations
- [ ] 6.4.1.4 Validate loaded data
- [ ] 6.4.1.5 Write unit tests for load function

### 6.4.2 Resume Session
- [ ] **Task 6.4.2**

Implement full session restoration.

- [ ] 6.4.2.1 Implement `resume/1` accepting session_id:
  ```elixir
  def resume(session_id) do
    with {:ok, persisted} <- load(session_id),
         :ok <- validate_project_path(persisted.project_path),
         session = rebuild_session(persisted),
         {:ok, _pid} <- SessionSupervisor.start_session(session) do
      # Restore conversation history
      restore_conversation(session.id, persisted.conversation)
      # Restore todos
      restore_todos(session.id, persisted.todos)
      # Delete persisted file (session is now active)
      delete_persisted(session_id)
      {:ok, session}
    end
  end
  ```
- [ ] 6.4.2.2 Implement `rebuild_session/1` creating Session from persisted:
  ```elixir
  defp rebuild_session(persisted) do
    %Session{
      id: persisted.id,
      name: persisted.name,
      project_path: persisted.project_path,
      config: persisted.config,
      created_at: DateTime.from_iso8601!(persisted.created_at),
      updated_at: DateTime.utc_now()
    }
  end
  ```
- [ ] 6.4.2.3 Restore messages to Session.State
- [ ] 6.4.2.4 Restore todos to Session.State
- [ ] 6.4.2.5 Delete persisted file after successful resume
- [ ] 6.4.2.6 Write unit tests for resume function

### 6.4.3 Project Path Validation
- [ ] **Task 6.4.3**

Validate project path still exists before resuming.

- [ ] 6.4.3.1 Implement `validate_project_path/1`:
  ```elixir
  defp validate_project_path(path) do
    cond do
      not File.exists?(path) ->
        {:error, :path_not_found}
      not File.dir?(path) ->
        {:error, :path_not_directory}
      SessionRegistry.lookup_by_path(path) != {:error, :not_found} ->
        {:error, :project_already_open}
      true ->
        :ok
    end
  end
  ```
- [ ] 6.4.3.2 Return clear error if path doesn't exist
- [ ] 6.4.3.3 Return error if project already open
- [ ] 6.4.3.4 Write unit tests for validation

**Unit Tests for Section 6.4:**
- Test `load/1` parses JSON correctly
- Test `load/1` handles missing file
- Test `load/1` handles corrupted JSON
- Test `resume/1` creates active session
- Test `resume/1` restores conversation history
- Test `resume/1` restores todos
- Test `resume/1` deletes persisted file
- Test resume fails if project path missing
- Test resume fails if project already open

---

## 6.5 Resume Command

Implement the `/resume` command.

### 6.5.1 Resume Command Handler
- [ ] **Task 6.5.1**

Implement the `/resume` command.

- [ ] 6.5.1.1 Add `/resume` to command parser:
  ```elixir
  def parse("/resume"), do: {:resume, :list}
  def parse("/resume " <> target), do: {:resume, {:restore, target}}
  ```
- [ ] 6.5.1.2 Implement `execute({:resume, :list}, model)`:
  ```elixir
  def execute({:resume, :list}, model) do
    sessions = Persistence.list_resumable()
    output = format_resumable_list(sessions)
    {:ok, output, :no_change}
  end
  ```
- [ ] 6.5.1.3 Implement `format_resumable_list/1`:
  ```elixir
  defp format_resumable_list([]) do
    "No sessions to resume."
  end
  defp format_resumable_list(sessions) do
    header = "Resumable sessions:\n"
    list = sessions
    |> Enum.with_index(1)
    |> Enum.map(fn {s, idx} ->
      "  #{idx}. #{s.name} (#{s.project_path}) - closed #{format_ago(s.closed_at)}"
    end)
    |> Enum.join("\n")
    header <> list <> "\n\nUse /resume <number> to restore."
  end
  ```
- [ ] 6.5.1.4 Write unit tests for resume list

### 6.5.2 Resume by Index or ID
- [ ] **Task 6.5.2**

Implement restoring specific session.

- [ ] 6.5.2.1 Implement `execute({:resume, {:restore, target}}, model)`:
  ```elixir
  def execute({:resume, {:restore, target}}, model) do
    sessions = Persistence.list_resumable()

    session_id = resolve_resume_target(target, sessions)

    case Persistence.resume(session_id) do
      {:ok, session} ->
        {:ok, "Resumed session: #{session.name}", {:add_session, session}}
      {:error, :path_not_found} ->
        {:error, "Project path no longer exists."}
      {:error, :project_already_open} ->
        {:error, "Project already open in another session."}
      {:error, :session_limit_reached} ->
        {:error, "Maximum 10 sessions reached."}
    end
  end
  ```
- [ ] 6.5.2.2 Implement `resolve_resume_target/2` supporting index or ID
- [ ] 6.5.2.3 Handle invalid target
- [ ] 6.5.2.4 Write unit tests for resume restore

### 6.5.3 Time Formatting
- [ ] **Task 6.5.3**

Format "closed X ago" for display.

- [ ] 6.5.3.1 Implement `format_ago/1`:
  ```elixir
  defp format_ago(iso_timestamp) do
    {:ok, dt, _} = DateTime.from_iso8601(iso_timestamp)
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604800 -> "#{div(diff, 86400)} days ago"
      true -> DateTime.to_date(dt) |> Date.to_string()
    end
  end
  ```
- [ ] 6.5.3.2 Write unit tests for time formatting

**Unit Tests for Section 6.5:**
- Test `/resume` lists resumable sessions
- Test `/resume` shows empty message when none
- Test `/resume 1` restores first session
- Test `/resume abc123` restores by ID
- Test resume adds session to TUI
- Test resume fails gracefully with clear errors
- Test `format_ago/1` formats times correctly

---

## 6.6 Cleanup and Maintenance

Implement cleanup of old persisted sessions.

### 6.6.1 Session Cleanup
- [ ] **Task 6.6.1**

Implement cleanup of old persisted sessions.

- [ ] 6.6.1.1 Implement `cleanup/1` accepting max_age in days:
  ```elixir
  def cleanup(max_age_days \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days * 86400, :second)

    list_persisted()
    |> Enum.filter(fn s ->
      {:ok, closed_at, _} = DateTime.from_iso8601(s.closed_at)
      DateTime.compare(closed_at, cutoff) == :lt
    end)
    |> Enum.each(&delete_persisted(&1.id))
  end
  ```
- [ ] 6.6.1.2 Default to 30 days max age
- [ ] 6.6.1.3 Delete sessions older than cutoff
- [ ] 6.6.1.4 Write unit tests for cleanup

### 6.6.2 Delete Command
- [ ] **Task 6.6.2**

Implement deleting persisted sessions without restoring.

- [ ] 6.6.2.1 Add `/resume delete <target>` subcommand
- [ ] 6.6.2.2 Implement handler:
  ```elixir
  def execute({:resume, {:delete, target}}, model) do
    sessions = Persistence.list_resumable()
    session_id = resolve_resume_target(target, sessions)
    Persistence.delete_persisted(session_id)
    {:ok, "Deleted saved session.", :no_change}
  end
  ```
- [ ] 6.6.2.3 Write unit tests for delete

### 6.6.3 Clear All Command
- [ ] **Task 6.6.3**

Implement clearing all persisted sessions.

- [ ] 6.6.3.1 Add `/resume clear` subcommand
- [ ] 6.6.3.2 Require confirmation (y/n) before clearing
- [ ] 6.6.3.3 Implement handler:
  ```elixir
  def execute({:resume, :clear}, model) do
    count = Persistence.list_persisted() |> length()
    if count > 0 do
      Persistence.clear_all()
      {:ok, "Cleared #{count} saved session(s).", :no_change}
    else
      {:ok, "No saved sessions to clear.", :no_change}
    end
  end
  ```
- [ ] 6.6.3.4 Write unit tests for clear all

**Unit Tests for Section 6.6:**
- Test `cleanup/1` removes old sessions
- Test cleanup keeps recent sessions
- Test `/resume delete 1` deletes session
- Test `/resume clear` removes all persisted
- Test clear reports correct count

---

## Success Criteria

1. **Save on Close**: Sessions auto-save when closed
2. **Persistence Format**: JSON files with version for migrations
3. **Resume List**: `/resume` shows all resumable sessions
4. **Resume Restore**: `/resume <target>` restores session fully
5. **Conversation Restored**: Messages appear after resume
6. **Todos Restored**: Task list appears after resume
7. **Path Validation**: Clear error if project path missing
8. **File Cleanup**: Delete persisted file after resume
9. **Old Session Cleanup**: Sessions older than 30 days cleaned
10. **Test Coverage**: Minimum 80% coverage for phase 6 code

---

## Critical Files

**New Files:**
- `lib/jido_code/session/persistence.ex`
- `test/jido_code/session/persistence_test.exs`

**Modified Files:**
- `lib/jido_code/session_supervisor.ex` - Auto-save on stop
- `lib/jido_code/commands.ex` - Add /resume command

---

## Dependencies

- **Depends on Phase 1**: Session struct, SessionRegistry
- **Depends on Phase 2**: Session.State for conversation data
- **Depends on Phase 5**: Command system for /resume
