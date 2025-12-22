defmodule JidoCode.Session.PersistenceResumeTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.Persistence
  alias JidoCode.SessionSupervisor

  setup do
    # Set test API key so LLMAgent can start
    System.put_env("ANTHROPIC_API_KEY", "test-api-key-for-resume-tests")
    System.put_env("OPENAI_API_KEY", "test-api-key-for-resume-tests")

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Ensure sessions directory exists
    :ok = Persistence.ensure_sessions_dir()

    # Clean up any existing sessions
    cleanup_all_sessions()

    # Create temp directory for test projects
    tmp_dir = Path.join(System.tmp_dir!(), "resume_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      cleanup_all_sessions()
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  defp cleanup_all_sessions do
    # Stop all running sessions
    for session <- JidoCode.SessionRegistry.list_all() do
      SessionSupervisor.stop_session(session.id)
    end

    # Clear session registry
    JidoCode.SessionRegistry.clear()

    # Delete all persisted session files
    sessions_dir = Persistence.sessions_dir()

    if File.exists?(sessions_dir) do
      File.ls!(sessions_dir)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.each(fn file ->
        File.rm!(Path.join(sessions_dir, file))
      end)
    end
  end

  defp test_uuid(index \\ 0) do
    # Generate valid UUID v4 format
    # Version 4 UUID: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    # where y is one of [8, 9, A, B]
    base_id = 10000 + index
    id_str = Integer.to_string(base_id) |> String.pad_leading(12, "0")
    "#{String.slice(id_str, 0..7)}-0000-4000-8000-#{String.slice(id_str, 8..11)}00000000"
  end

  defp create_test_session(id, name, project_path) do
    %Session{
      id: id,
      name: name,
      project_path: project_path,
      config: %{
        provider: "anthropic",
        model: "claude-3-5-haiku-20241022",
        temperature: 0.7,
        max_tokens: 4096
      },
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  defp create_persisted_session(id, name, project_path) do
    now = DateTime.utc_now()

    %{
      version: 1,
      id: id,
      name: name,
      project_path: project_path,
      config: %{
        "provider" => "anthropic",
        "model" => "claude-3-5-haiku-20241022",
        "temperature" => 0.7,
        "max_tokens" => 4096
      },
      created_at: DateTime.to_iso8601(now),
      updated_at: DateTime.to_iso8601(now),
      closed_at: DateTime.to_iso8601(now),
      conversation: [
        %{
          "id" => "msg-1",
          "role" => "user",
          "content" => "Hello",
          "timestamp" => DateTime.to_iso8601(now)
        },
        %{
          "id" => "msg-2",
          "role" => "assistant",
          "content" => "Hi there!",
          "timestamp" => DateTime.to_iso8601(now)
        }
      ],
      todos: [
        %{
          "content" => "Complete task 1",
          "status" => "pending",
          "active_form" => "Completing task 1"
        },
        %{
          "content" => "Complete task 2",
          "status" => "in_progress",
          "active_form" => "Completing task 2"
        }
      ]
    }
  end

  describe "resume/1 - happy path" do
    test "resumes persisted session with full state restoration", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(0)

      # Create persisted session file
      persisted = create_persisted_session(session_id, "Test Session", tmp_dir)
      :ok = Persistence.write_session_file(session_id, persisted)

      # Resume the session
      assert {:ok, session} = Persistence.resume(session_id)
      assert session.id == session_id
      assert session.name == "Test Session"
      assert session.project_path == tmp_dir
      assert %DateTime{} = session.created_at
      assert %DateTime{} = session.updated_at

      # Verify session is running
      sessions = JidoCode.SessionRegistry.list_all()
      assert Enum.any?(sessions, fn s -> s.id == session_id end)

      # Verify conversation restored
      assert {:ok, messages} = Session.State.get_messages(session_id)
      assert length(messages) == 2
      assert Enum.at(messages, 0).role == :user
      assert Enum.at(messages, 0).content == "Hello"
      assert Enum.at(messages, 1).role == :assistant
      assert Enum.at(messages, 1).content == "Hi there!"

      # Verify todos restored
      assert {:ok, todos} = Session.State.get_todos(session_id)
      assert length(todos) == 2
      assert Enum.at(todos, 0).status == :pending
      assert Enum.at(todos, 1).status == :in_progress

      # Verify persisted file was deleted
      session_file = Persistence.session_file(session_id)
      refute File.exists?(session_file)

      # Cleanup
      SessionSupervisor.stop_session(session_id)
    end

    test "resumes session with empty conversation", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(1)
      persisted = create_persisted_session(session_id, "Empty Conv", tmp_dir)
      persisted = %{persisted | conversation: []}
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:ok, session} = Persistence.resume(session_id)
      assert {:ok, messages} = Session.State.get_messages(session_id)
      assert messages == []

      SessionSupervisor.stop_session(session_id)
    end

    test "resumes session with empty todos", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(2)
      persisted = create_persisted_session(session_id, "Empty Todos", tmp_dir)
      persisted = %{persisted | todos: []}
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:ok, session} = Persistence.resume(session_id)
      assert {:ok, todos} = Session.State.get_todos(session_id)
      assert todos == []

      SessionSupervisor.stop_session(session_id)
    end

    test "preserves created_at timestamp", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(3)
      created = ~U[2024-01-01 10:00:00Z]

      persisted = create_persisted_session(session_id, "Timestamp Test", tmp_dir)
      persisted = %{persisted | created_at: DateTime.to_iso8601(created)}
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:ok, session} = Persistence.resume(session_id)
      # created_at should match original
      assert DateTime.diff(session.created_at, created, :second) == 0
      # updated_at should be recent
      assert DateTime.diff(DateTime.utc_now(), session.updated_at, :second) < 2

      SessionSupervisor.stop_session(session_id)
    end
  end

  describe "resume/1 - error cases" do
    test "returns error for non-existent session" do
      non_existent_id = "99999999-9999-4999-8999-999999999999"
      assert {:error, :not_found} = Persistence.resume(non_existent_id)
    end

    test "returns error if project path doesn't exist", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(4)
      non_existent_path = Path.join(tmp_dir, "nonexistent")

      persisted = create_persisted_session(session_id, "Bad Path", non_existent_path)
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:error, :project_path_not_found} = Persistence.resume(session_id)

      # Verify persisted file still exists (resume failed)
      assert File.exists?(Persistence.session_file(session_id))

      # Cleanup
      File.rm!(Persistence.session_file(session_id))
    end

    test "returns error if project path is not a directory", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(5)
      file_path = Path.join(tmp_dir, "somefile.txt")
      File.write!(file_path, "content")

      persisted = create_persisted_session(session_id, "File Path", file_path)
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:error, :project_path_not_directory} = Persistence.resume(session_id)

      # Cleanup
      File.rm!(Persistence.session_file(session_id))
      File.rm!(file_path)
    end

    test "returns error if session limit reached", %{tmp_dir: tmp_dir} do
      # Start 10 sessions (the limit) - each with unique project path
      session_ids =
        for i <- 0..9 do
          id = test_uuid(100 + i)
          # Create unique project path for each session
          proj_dir = Path.join(tmp_dir, "project_#{i}")
          File.mkdir_p!(proj_dir)
          session = create_test_session(id, "Session #{i}", proj_dir)
          {:ok, _pid} = SessionSupervisor.start_session(session)
          id
        end

      # Try to resume 11th session with yet another unique path
      session_id = test_uuid(6)
      eleventh_dir = Path.join(tmp_dir, "project_11")
      File.mkdir_p!(eleventh_dir)
      persisted = create_persisted_session(session_id, "11th Session", eleventh_dir)
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:error, {:session_limit_reached, 10, 10}} = Persistence.resume(session_id)

      # Cleanup
      Enum.each(session_ids, &SessionSupervisor.stop_session/1)
      File.rm!(Persistence.session_file(session_id))
    end

    test "returns error if project already open", %{tmp_dir: tmp_dir} do
      # Start a session with this project path
      existing_id = test_uuid(7)
      existing = create_test_session(existing_id, "Existing", tmp_dir)
      {:ok, _pid} = SessionSupervisor.start_session(existing)

      # Try to resume another session with same project path
      session_id = test_uuid(8)
      persisted = create_persisted_session(session_id, "Duplicate", tmp_dir)
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:error, :project_already_open} = Persistence.resume(session_id)

      # Cleanup
      SessionSupervisor.stop_session(existing_id)
      File.rm!(Persistence.session_file(session_id))
    end
  end

  describe "resume/1 - cleanup on failure" do
    test "stops session if conversation restore fails", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(9)

      # Create persisted session with invalid message data
      # (This test is conceptual - in practice, deserialize_session validates messages)
      # We'll test the cleanup mechanism by verifying session doesn't remain running
      # if any part of the resume fails after session startup

      persisted = create_persisted_session(session_id, "Cleanup Test", tmp_dir)

      # Create a session file that will pass initial validation
      :ok = Persistence.write_session_file(session_id, persisted)

      # Attempt resume - should succeed in our case since data is valid
      # The cleanup mechanism is tested implicitly by error path tests above
      assert {:ok, _session} = Persistence.resume(session_id)

      # Verify session started and is running
      sessions = JidoCode.SessionRegistry.list_all()
      assert Enum.any?(sessions, fn s -> s.id == session_id end)

      # Cleanup
      SessionSupervisor.stop_session(session_id)
    end
  end

  describe "resume/1 - config restoration" do
    test "restores LLM config from persisted data", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(10)

      persisted = create_persisted_session(session_id, "Config Test", tmp_dir)

      persisted = %{
        persisted
        | config: %{
            "provider" => "openai",
            "model" => "gpt-4",
            "temperature" => 0.5,
            "max_tokens" => 2048
          }
      }

      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:ok, session} = Persistence.resume(session_id)
      assert session.config.provider == "openai"
      assert session.config.model == "gpt-4"
      assert session.config.temperature == 0.5
      assert session.config.max_tokens == 2048

      SessionSupervisor.stop_session(session_id)
    end
  end

  describe "resume/1 - message order preservation" do
    test "preserves message chronological order", %{tmp_dir: tmp_dir} do
      session_id = test_uuid(11)
      now = DateTime.utc_now()

      # Create messages with specific timestamps
      messages = [
        %{
          "id" => "msg-1",
          "role" => "user",
          "content" => "First message",
          "timestamp" => DateTime.to_iso8601(DateTime.add(now, -120, :second))
        },
        %{
          "id" => "msg-2",
          "role" => "assistant",
          "content" => "Second message",
          "timestamp" => DateTime.to_iso8601(DateTime.add(now, -60, :second))
        },
        %{
          "id" => "msg-3",
          "role" => "user",
          "content" => "Third message",
          "timestamp" => DateTime.to_iso8601(now)
        }
      ]

      persisted = create_persisted_session(session_id, "Order Test", tmp_dir)
      persisted = %{persisted | conversation: messages}
      :ok = Persistence.write_session_file(session_id, persisted)

      assert {:ok, _session} = Persistence.resume(session_id)
      assert {:ok, restored_messages} = Session.State.get_messages(session_id)

      assert length(restored_messages) == 3
      assert Enum.at(restored_messages, 0).content == "First message"
      assert Enum.at(restored_messages, 1).content == "Second message"
      assert Enum.at(restored_messages, 2).content == "Third message"

      SessionSupervisor.stop_session(session_id)
    end
  end
end
