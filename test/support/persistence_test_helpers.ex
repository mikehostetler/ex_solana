defmodule JidoCode.PersistenceTestHelpers do
  @moduledoc """
  Shared test helpers for session persistence testing.

  Consolidates common patterns used across persistence, commands, and integration tests.
  """

  @doc """
  Waits for a persisted session file to appear on disk.

  Polls for file existence with exponential backoff, up to `retries` attempts.
  Returns `:ok` if file appears, `{:error, :timeout}` if retries exhausted.

  ## Parameters
  - `file_path` - Absolute path to session file
  - `retries` - Number of retry attempts (default: 50, ~500ms total)

  ## Examples

      iex> wait_for_persisted_file("/path/to/session.json")
      :ok

      iex> wait_for_persisted_file("/nonexistent.json", 5)
      {:error, :timeout}
  """
  def wait_for_persisted_file(file_path, retries \\ 50) do
    if File.exists?(file_path) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_persisted_file(file_path, retries - 1)
      else
        {:error, :timeout}
      end
    end
  end

  @doc """
  Creates a session, adds content, closes it, and waits for persistence.

  This is a common pattern for testing persistence: create session, populate with
  test data, close (triggering auto-save), and wait for file to appear.

  ## Parameters
  - `name` - Session name
  - `project_path` - Project directory path

  ## Returns
  - Session struct (closed state)

  ## Examples

      session = create_and_close_session("Test Session", "/tmp/project")
      assert File.exists?("~/.jido_code/sessions/\#{session.id}.json")
  """
  def create_and_close_session(name, project_path) do
    # Use ollama for tests to avoid external API dependencies
    config = %{
      provider: "ollama",
      model: "qwen/qwen3-coder-30b",
      temperature: 0.7,
      max_tokens: 4096
    }

    # Create session
    {:ok, session} =
      JidoCode.SessionSupervisor.create_session(
        project_path: project_path,
        name: name,
        config: config
      )

    # Add a message so session has content
    message = %{
      id: "test-msg-#{System.unique_integer([:positive])}",
      role: :user,
      content: "Test message",
      timestamp: DateTime.utc_now()
    }

    JidoCode.Session.State.append_message(session.id, message)

    # Close session (triggers auto-save)
    :ok = JidoCode.SessionSupervisor.stop_session(session.id)

    # Wait for file creation
    session_file =
      Path.join(JidoCode.Session.Persistence.sessions_dir(), "#{session.id}.json")

    wait_for_persisted_file(session_file)

    session
  end

  @doc """
  Waits for SessionSupervisor to become available.

  Used at the start of tests to ensure supervisor is ready before creating sessions.

  ## Parameters
  - `retries` - Number of retry attempts (default: 50)

  ## Returns
  - `:ok` if supervisor ready
  - `{:error, :timeout}` if retries exhausted
  """
  def wait_for_supervisor(retries \\ 50) do
    case Process.whereis(JidoCode.SessionSupervisor) do
      nil ->
        if retries > 0 do
          Process.sleep(10)
          wait_for_supervisor(retries - 1)
        else
          {:error, :timeout}
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Creates a temporary directory for test isolation.

  ## Parameters
  - `base_path` - Base path for temp directory (default: System.tmp_dir!)
  - `prefix` - Prefix for directory name (default: "jido_code_test_")

  ## Returns
  - Absolute path to created directory
  """
  def create_test_directory(base_path \\ nil, prefix \\ "jido_code_test_") do
    base = base_path || System.tmp_dir!()
    unique_suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    dir_path = Path.join(base, "#{prefix}#{unique_suffix}")
    File.mkdir_p!(dir_path)
    dir_path
  end

  @doc """
  Cleans up test artifacts (sessions, directories).

  ## Parameters
  - `session_ids` - List of session IDs to delete
  - `directories` - List of directory paths to remove
  """
  def cleanup(session_ids \\ [], directories \\ []) do
    # Stop and delete sessions
    for session_id <- session_ids do
      # Try to stop if still running
      JidoCode.SessionSupervisor.stop_session(session_id)

      # Delete persisted file
      JidoCode.Session.Persistence.delete_persisted(session_id)
    end

    # Remove directories
    for dir <- directories do
      File.rm_rf(dir)
    end

    :ok
  end
end
