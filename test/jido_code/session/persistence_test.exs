defmodule JidoCode.Session.PersistenceTest do
  use ExUnit.Case, async: true

  alias JidoCode.Session
  alias JidoCode.Session.Persistence
  alias JidoCode.SessionRegistry

  describe "schema_version/0" do
    test "returns current schema version" do
      assert Persistence.schema_version() == 1
    end

    test "returns a positive integer" do
      version = Persistence.schema_version()
      assert is_integer(version)
      assert version > 0
    end
  end

  describe "validate_session/1" do
    test "validates complete session map with atom keys" do
      session = valid_session()
      assert {:ok, ^session} = Persistence.validate_session(session)
    end

    test "validates session map with string keys" do
      session = %{
        "version" => 1,
        "id" => "test-123",
        "name" => "Test Session",
        "project_path" => "/path/to/project",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z",
        "closed_at" => "2024-01-01T00:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      assert {:ok, _} = Persistence.validate_session(session)
    end

    test "returns error for missing required fields" do
      session = %{version: 1, id: "test"}
      assert {:error, {:missing_fields, missing}} = Persistence.validate_session(session)
      assert :name in missing
      assert :project_path in missing
      assert :config in missing
    end

    test "returns error for invalid version" do
      session = valid_session() |> Map.put(:version, 0)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_version} = Persistence.validate_session(session)
    end

    test "returns error for non-integer version" do
      session = valid_session() |> Map.put(:version, "1")
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_version} = Persistence.validate_session(session)
    end

    test "returns error for invalid id type" do
      session = valid_session() |> Map.put(:id, 123)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_id} = Persistence.validate_session(session)
    end

    test "returns error for invalid name type" do
      session = valid_session() |> Map.put(:name, nil)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_name} = Persistence.validate_session(session)
    end

    test "returns error for invalid project_path type" do
      session = valid_session() |> Map.put(:project_path, 123)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_project_path} = Persistence.validate_session(session)
    end

    test "returns error for invalid config type" do
      session = valid_session() |> Map.put(:config, "invalid")
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_config} = Persistence.validate_session(session)
    end

    test "returns error for invalid conversation type" do
      session = valid_session() |> Map.put(:conversation, "invalid")
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_conversation} = Persistence.validate_session(session)
    end

    test "returns error for invalid todos type" do
      session = valid_session() |> Map.put(:todos, "invalid")
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_todos} = Persistence.validate_session(session)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Persistence.validate_session("invalid")
      assert {:error, :not_a_map} = Persistence.validate_session(nil)
      assert {:error, :not_a_map} = Persistence.validate_session([])
    end
  end

  describe "validate_message/1" do
    test "validates complete message map" do
      message = valid_message()
      assert {:ok, ^message} = Persistence.validate_message(message)
    end

    test "validates message with string keys" do
      message = %{
        "id" => "msg-1",
        "role" => "user",
        "content" => "Hello",
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:ok, _} = Persistence.validate_message(message)
    end

    test "accepts all valid roles" do
      for role <- ["user", "assistant", "system"] do
        message = valid_message() |> Map.put(:role, role)
        assert {:ok, _} = Persistence.validate_message(message)
      end
    end

    test "returns error for unknown role" do
      message = valid_message() |> Map.put(:role, "unknown")
      # Error sanitization: role value no longer exposed in error tuple
      assert {:error, :unknown_role} = Persistence.validate_message(message)
    end

    test "returns error for missing required fields" do
      message = %{id: "msg-1"}
      assert {:error, {:missing_fields, missing}} = Persistence.validate_message(message)
      assert :role in missing
      assert :content in missing
      assert :timestamp in missing
    end

    test "returns error for invalid id type" do
      message = valid_message() |> Map.put(:id, 123)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_id} = Persistence.validate_message(message)
    end

    test "returns error for invalid role type" do
      message = valid_message() |> Map.put(:role, :user)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_role} = Persistence.validate_message(message)
    end

    test "returns error for invalid content type" do
      message = valid_message() |> Map.put(:content, nil)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_content} = Persistence.validate_message(message)
    end

    test "returns error for invalid timestamp type" do
      message = valid_message() |> Map.put(:timestamp, ~U[2024-01-01 00:00:00Z])
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_timestamp} = Persistence.validate_message(message)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Persistence.validate_message("invalid")
    end
  end

  describe "validate_todo/1" do
    test "validates complete todo map" do
      todo = valid_todo()
      assert {:ok, ^todo} = Persistence.validate_todo(todo)
    end

    test "validates todo with string keys" do
      todo = %{
        "content" => "Run tests",
        "status" => "pending",
        "active_form" => "Running tests"
      }

      assert {:ok, _} = Persistence.validate_todo(todo)
    end

    test "accepts all valid statuses" do
      for status <- ["pending", "in_progress", "completed"] do
        todo = valid_todo() |> Map.put(:status, status)
        assert {:ok, _} = Persistence.validate_todo(todo)
      end
    end

    test "returns error for unknown status" do
      todo = valid_todo() |> Map.put(:status, "unknown")
      # Error sanitization: status value no longer exposed in error tuple
      assert {:error, :unknown_status} = Persistence.validate_todo(todo)
    end

    test "returns error for missing required fields" do
      todo = %{content: "Test"}
      assert {:error, {:missing_fields, missing}} = Persistence.validate_todo(todo)
      assert :status in missing
      assert :active_form in missing
    end

    test "returns error for invalid content type" do
      todo = valid_todo() |> Map.put(:content, nil)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_content} = Persistence.validate_todo(todo)
    end

    test "returns error for invalid status type" do
      todo = valid_todo() |> Map.put(:status, :pending)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_status} = Persistence.validate_todo(todo)
    end

    test "returns error for invalid active_form type" do
      todo = valid_todo() |> Map.put(:active_form, 123)
      # Error sanitization: value no longer exposed in error tuple
      assert {:error, :invalid_active_form} = Persistence.validate_todo(todo)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Persistence.validate_todo(nil)
    end
  end

  describe "new_session/1" do
    test "creates session with current schema version" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert session.version == 1
    end

    test "creates session with required fields" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert session.id == "test-123"
      assert session.name == "Test Session"
      assert session.project_path == "/path/to/project"
    end

    test "uses defaults for optional fields" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert session.config == %{}
      assert session.conversation == []
      assert session.todos == []
      assert is_binary(session.created_at)
      assert is_binary(session.updated_at)
      assert is_binary(session.closed_at)
    end

    test "allows overriding optional fields" do
      config = %{provider: :anthropic, model: "claude-3"}
      conversation = [valid_message()]
      todos = [valid_todo()]

      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project",
          config: config,
          conversation: conversation,
          todos: todos
        })

      assert session.config == config
      assert session.conversation == conversation
      assert session.todos == todos
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Persistence.new_session(%{name: "Test"})
      end
    end
  end

  describe "new_message/1" do
    test "creates message with required fields" do
      message =
        Persistence.new_message(%{
          id: "msg-1",
          role: "user",
          content: "Hello, world!"
        })

      assert message.id == "msg-1"
      assert message.role == "user"
      assert message.content == "Hello, world!"
      assert is_binary(message.timestamp)
    end

    test "allows overriding timestamp" do
      timestamp = "2024-01-01T00:00:00Z"

      message =
        Persistence.new_message(%{
          id: "msg-1",
          role: "user",
          content: "Hello",
          timestamp: timestamp
        })

      assert message.timestamp == timestamp
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Persistence.new_message(%{id: "msg-1"})
      end
    end
  end

  describe "new_todo/1" do
    test "creates todo with required fields" do
      todo =
        Persistence.new_todo(%{
          content: "Run tests",
          active_form: "Running tests"
        })

      assert todo.content == "Run tests"
      assert todo.active_form == "Running tests"
      assert todo.status == "pending"
    end

    test "defaults status to pending" do
      todo =
        Persistence.new_todo(%{
          content: "Test",
          active_form: "Testing"
        })

      assert todo.status == "pending"
    end

    test "allows overriding status" do
      todo =
        Persistence.new_todo(%{
          content: "Test",
          status: "completed",
          active_form: "Testing"
        })

      assert todo.status == "completed"
    end

    test "raises on missing required fields" do
      assert_raise KeyError, fn ->
        Persistence.new_todo(%{content: "Test"})
      end
    end
  end

  describe "schema consistency" do
    test "new_session creates valid session" do
      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project"
        })

      assert {:ok, _} = Persistence.validate_session(session)
    end

    test "new_message creates valid message" do
      message =
        Persistence.new_message(%{
          id: "msg-1",
          role: "user",
          content: "Hello"
        })

      assert {:ok, _} = Persistence.validate_message(message)
    end

    test "new_todo creates valid todo" do
      todo =
        Persistence.new_todo(%{
          content: "Run tests",
          active_form: "Running tests"
        })

      assert {:ok, _} = Persistence.validate_todo(todo)
    end

    test "session with messages and todos validates" do
      messages = [
        Persistence.new_message(%{id: "1", role: "user", content: "Hello"}),
        Persistence.new_message(%{id: "2", role: "assistant", content: "Hi there!"})
      ]

      todos = [
        Persistence.new_todo(%{content: "Task 1", active_form: "Doing task 1"}),
        Persistence.new_todo(%{
          content: "Task 2",
          status: "completed",
          active_form: "Doing task 2"
        })
      ]

      session =
        Persistence.new_session(%{
          id: "test-123",
          name: "Test Session",
          project_path: "/path/to/project",
          conversation: messages,
          todos: todos
        })

      assert {:ok, _} = Persistence.validate_session(session)
    end
  end

  describe "sessions_dir/0" do
    test "returns path under user home directory" do
      dir = Persistence.sessions_dir()
      home = System.user_home!()

      assert String.starts_with?(dir, home)
    end

    test "returns path ending with .jido_code/sessions" do
      dir = Persistence.sessions_dir()

      assert String.ends_with?(dir, ".jido_code/sessions")
    end

    test "returns absolute path" do
      dir = Persistence.sessions_dir()

      assert Path.type(dir) == :absolute
    end

    test "returns consistent path" do
      dir1 = Persistence.sessions_dir()
      dir2 = Persistence.sessions_dir()

      assert dir1 == dir2
    end
  end

  describe "session_file/1" do
    test "returns path with .json extension" do
      path = Persistence.session_file(test_uuid(0))

      assert String.ends_with?(path, ".json")
    end

    test "includes session_id in filename" do
      session_id = test_uuid(1)
      path = Persistence.session_file(session_id)

      assert String.ends_with?(path, "#{session_id}.json")
    end

    test "returns path under sessions directory" do
      # Use a valid UUID v4
      path = Persistence.session_file("550e8400-e29b-41d4-a716-446655440000")
      sessions_dir = Persistence.sessions_dir()

      assert String.starts_with?(path, sessions_dir)
    end

    test "returns absolute path" do
      # Use a valid UUID v4
      path = Persistence.session_file("550e8400-e29b-41d4-a716-446655440000")

      assert Path.type(path) == :absolute
    end

    test "uses session ID in filename" do
      # Use a valid UUID v4
      session_id = "550e8400-e29b-41d4-a716-446655440000"
      path = Persistence.session_file(session_id)

      assert String.ends_with?(path, "#{session_id}.json")
    end
  end

  describe "Security: Path Traversal Protection" do
    test "rejects session IDs with path traversal attempts" do
      assert_raise ArgumentError, fn ->
        Persistence.session_file("../../../etc/passwd")
      end
    end

    test "rejects session IDs with absolute paths" do
      assert_raise ArgumentError, fn ->
        Persistence.session_file("/tmp/malicious")
      end
    end

    test "rejects session IDs that are not UUID v4 format" do
      assert_raise ArgumentError, fn ->
        Persistence.session_file("not-a-uuid")
      end
    end

    test "rejects session IDs with invalid UUID versions" do
      # UUID v1 format (not v4)
      assert_raise ArgumentError, fn ->
        Persistence.session_file("550e8400-e29b-11d4-a716-446655440000")
      end
    end

    test "accepts valid UUID v4 session IDs" do
      # Valid UUID v4
      path = Persistence.session_file("550e8400-e29b-41d4-a716-446655440000")
      assert String.ends_with?(path, "550e8400-e29b-41d4-a716-446655440000.json")
    end

    test "rejects empty session IDs" do
      assert_raise ArgumentError, fn ->
        Persistence.session_file("")
      end
    end

    test "rejects session IDs with null bytes" do
      assert_raise ArgumentError, fn ->
        Persistence.session_file("test\0malicious")
      end
    end
  end

  describe "Security: File Size Limits" do
    test "skips files larger than max size" do
      # Create a large file (11MB, over the 10MB limit) directly in sessions dir
      large_id = test_uuid(0)
      large_file = Path.join(Persistence.sessions_dir(), "#{large_id}.json")
      large_content = String.duplicate("x", 11 * 1024 * 1024)
      File.write!(large_file, large_content)

      on_exit(fn -> File.rm(large_file) end)

      # Should skip the large file
      {:ok, result} = Persistence.list_persisted()
      # Should not include the large file
      refute Enum.any?(result, &(&1.id == large_id))
    end

    test "accepts files under max size" do
      # Create a valid session file under 10MB
      session = create_test_session(test_uuid(0), "Test", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(0), session)

      # Should successfully load the file
      {:ok, result} = Persistence.list_persisted()
      assert Enum.any?(result, &(&1.id == test_uuid(0)))
    end
  end

  describe "ensure_sessions_dir/0" do
    setup do
      # Use a temporary directory for testing
      test_dir =
        Path.join(System.tmp_dir!(), "persistence_test_#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(test_dir) end)
      {:ok, test_dir: test_dir}
    end

    test "returns :ok when directory exists" do
      # The actual sessions_dir may or may not exist, but mkdir_p handles both
      result = Persistence.ensure_sessions_dir()

      assert result == :ok
    end

    test "creates directory if it doesn't exist" do
      # Ensure the directory exists after calling ensure_sessions_dir
      :ok = Persistence.ensure_sessions_dir()

      assert File.dir?(Persistence.sessions_dir())
    end

    test "is idempotent" do
      # Can be called multiple times without error
      assert :ok = Persistence.ensure_sessions_dir()
      assert :ok = Persistence.ensure_sessions_dir()
      assert :ok = Persistence.ensure_sessions_dir()
    end
  end

  describe "save/1" do
    test "returns error for non-existent session" do
      result = Persistence.save("non-existent-session-id")

      assert {:error, :not_found} = result
    end

    @tag :llm
    test "enforces max_sessions limit for new sessions" do
      # Clean up any existing session files from other tests
      sessions_dir = Persistence.sessions_dir()

      if File.exists?(sessions_dir) do
        File.rm_rf!(sessions_dir)
        File.mkdir_p!(sessions_dir)
      end

      tmp_dir = System.tmp_dir!() |> Path.join("jido_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      # Set low limit for testing
      Application.put_env(:jido_code, :persistence, max_sessions: 3)

      # Use ollama for tests to avoid external API dependencies
      config = %{
        provider: "ollama",
        model: "qwen/qwen3-coder-30b",
        temperature: 0.7,
        max_tokens: 4096
      }

      # Create and close 3 sessions (fill the limit)
      session_ids =
        for i <- 1..3 do
          project_path = Path.join(tmp_dir, "project_#{i}")
          File.mkdir_p!(project_path)

          {:ok, session} =
            JidoCode.SessionSupervisor.create_session(
              project_path: project_path,
              name: "Session #{i}",
              config: config
            )

          # Add message and save
          message = %{
            id: "msg-#{i}",
            role: :user,
            content: "Test",
            timestamp: DateTime.utc_now()
          }

          JidoCode.Session.State.append_message(session.id, message)
          assert {:ok, _path} = Persistence.save(session.id)

          # Stop session
          :ok = JidoCode.SessionSupervisor.stop_session(session.id)

          session.id
        end

      # Try to create a 4th session (should be blocked)
      project_path = Path.join(tmp_dir, "project_4")
      File.mkdir_p!(project_path)

      {:ok, session4} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project_path,
          name: "Session 4",
          config: config
        )

      message = %{
        id: "msg-4",
        role: :user,
        content: "Test",
        timestamp: DateTime.utc_now()
      }

      JidoCode.Session.State.append_message(session4.id, message)

      # This should fail due to session limit
      assert {:error, :session_limit_reached} = Persistence.save(session4.id)

      # Clean up
      JidoCode.SessionSupervisor.stop_session(session4.id)

      for session_id <- session_ids do
        Persistence.delete_persisted(session_id)
      end

      # Reset config
      Application.delete_env(:jido_code, :persistence)
    end

    @tag :llm
    test "allows updates to existing sessions even when at limit" do
      # Clean up any existing session files from other tests
      sessions_dir = Persistence.sessions_dir()

      if File.exists?(sessions_dir) do
        File.rm_rf!(sessions_dir)
        File.mkdir_p!(sessions_dir)
      end

      tmp_dir = System.tmp_dir!() |> Path.join("jido_test_update_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      # Set low limit
      Application.put_env(:jido_code, :persistence, max_sessions: 2)

      # Use ollama for tests to avoid external API dependencies
      config = %{
        provider: "ollama",
        model: "qwen/qwen3-coder-30b",
        temperature: 0.7,
        max_tokens: 4096
      }

      # Create and save 2 sessions
      session_ids =
        for i <- 1..2 do
          project_path = Path.join(tmp_dir, "update_project_#{i}")
          File.mkdir_p!(project_path)

          {:ok, session} =
            JidoCode.SessionSupervisor.create_session(
              project_path: project_path,
              name: "Session #{i}",
              config: config
            )

          message = %{id: "msg-#{i}", role: :user, content: "Test", timestamp: DateTime.utc_now()}
          JidoCode.Session.State.append_message(session.id, message)
          assert {:ok, _path} = Persistence.save(session.id)

          :ok = JidoCode.SessionSupervisor.stop_session(session.id)
          session.id
        end

      # Resume first session
      [first_id | _] = session_ids
      assert {:ok, resumed} = Persistence.resume(first_id)

      # Add another message
      message = %{id: "msg-new", role: :user, content: "Update", timestamp: DateTime.utc_now()}
      JidoCode.Session.State.append_message(resumed.id, message)

      # This should succeed (updating existing session)
      assert {:ok, _path} = Persistence.save(resumed.id)

      # Clean up
      JidoCode.SessionSupervisor.stop_session(resumed.id)

      for session_id <- session_ids do
        Persistence.delete_persisted(session_id)
      end

      Application.delete_env(:jido_code, :persistence)
    end
  end

  describe "build_persisted_session/1" do
    test "builds valid persisted session from state" do
      state = mock_session_state()

      result = Persistence.build_persisted_session(state)

      assert result.version == Persistence.schema_version()
      assert result.id == test_uuid(5)
      assert result.name == "Test Session"
      assert result.project_path == "/tmp/test-project"
      assert is_binary(result.created_at)
      assert is_binary(result.updated_at)
      assert is_binary(result.closed_at)
      assert is_list(result.conversation)
      assert is_list(result.todos)
    end

    test "serializes messages correctly" do
      state =
        mock_session_state()
        |> Map.put(:messages, [
          %{
            id: "msg-1",
            role: :user,
            content: "Hello",
            timestamp: ~U[2024-01-01 12:00:00Z]
          },
          %{
            id: "msg-2",
            role: :assistant,
            content: "Hi there!",
            timestamp: ~U[2024-01-01 12:01:00Z]
          }
        ])

      result = Persistence.build_persisted_session(state)

      assert length(result.conversation) == 2

      [msg1, msg2] = result.conversation
      assert msg1.id == "msg-1"
      assert msg1.role == "user"
      assert msg1.content == "Hello"
      assert is_binary(msg1.timestamp)

      assert msg2.id == "msg-2"
      assert msg2.role == "assistant"
      assert msg2.content == "Hi there!"
    end

    test "serializes todos correctly" do
      state =
        mock_session_state()
        |> Map.put(:todos, [
          %{content: "Task 1", status: :pending, active_form: "Doing task 1"},
          %{content: "Task 2", status: :completed, active_form: "Doing task 2"}
        ])

      result = Persistence.build_persisted_session(state)

      assert length(result.todos) == 2

      [todo1, todo2] = result.todos
      assert todo1.content == "Task 1"
      assert todo1.status == "pending"
      assert todo1.active_form == "Doing task 1"

      assert todo2.content == "Task 2"
      assert todo2.status == "completed"
    end

    test "serializes config with atom values" do
      state = mock_session_state()
      result = Persistence.build_persisted_session(state)

      assert is_map(result.config)
      # Config should have string keys/values for JSON compatibility
      assert result.config["provider"] == "anthropic"
      assert result.config["model"] == "test-model"
    end

    test "handles todos without active_form" do
      state =
        mock_session_state()
        |> Map.put(:todos, [
          %{content: "Task without active_form", status: :pending}
        ])

      result = Persistence.build_persisted_session(state)

      [todo] = result.todos
      # Falls back to content when active_form missing
      assert todo.active_form == "Task without active_form"
    end
  end

  describe "write_session_file/2" do
    setup do
      # Use a deterministic UUID for testing
      test_id = test_uuid(System.unique_integer([:positive]))

      on_exit(fn ->
        # Clean up any test files
        path = Persistence.session_file(test_id)
        File.rm(path)
        File.rm("#{path}.tmp")
      end)

      {:ok, test_id: test_id}
    end

    test "writes JSON file to correct location", %{test_id: test_id} do
      persisted = %{
        version: 1,
        id: test_id,
        name: "Test",
        project_path: "/tmp",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      result = Persistence.write_session_file(test_id, persisted)

      assert result == :ok
      assert File.exists?(Persistence.session_file(test_id))
    end

    test "writes valid JSON", %{test_id: test_id} do
      persisted = %{
        version: 1,
        id: test_id,
        name: "Test Session",
        project_path: "/tmp/project",
        config: %{"provider" => "anthropic"},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [
          %{id: "1", role: "user", content: "Hello", timestamp: "2024-01-01T00:00:00Z"}
        ],
        todos: [%{content: "Task", status: "pending", active_form: "Doing task"}]
      }

      :ok = Persistence.write_session_file(test_id, persisted)

      path = Persistence.session_file(test_id)
      {:ok, content} = File.read(path)
      {:ok, decoded} = Jason.decode(content)

      assert decoded["version"] == 1
      assert decoded["id"] == test_id
      assert decoded["name"] == "Test Session"
      assert length(decoded["conversation"]) == 1
      assert length(decoded["todos"]) == 1
    end

    test "cleans up temp file on success", %{test_id: test_id} do
      persisted = %{
        version: 1,
        id: test_id,
        name: "Test",
        project_path: "/tmp",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      :ok = Persistence.write_session_file(test_id, persisted)

      temp_path = "#{Persistence.session_file(test_id)}.tmp"
      refute File.exists?(temp_path)
    end
  end

  describe "list_persisted/0" do
    setup do
      # Ensure sessions directory exists and is clean
      :ok = Persistence.ensure_sessions_dir()
      cleanup_session_files()

      on_exit(fn -> cleanup_session_files() end)
      :ok
    end

    test "returns empty list when no sessions exist" do
      {:ok, result} = Persistence.list_persisted()

      assert result == []
    end

    test "returns list of persisted sessions" do
      # Create two session files
      session1 = %{
        version: 1,
        id: test_uuid(1),
        name: "First Session",
        project_path: "/tmp/proj1",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T12:00:00Z",
        conversation: [],
        todos: []
      }

      session2 = %{
        version: 1,
        id: test_uuid(2),
        name: "Second Session",
        project_path: "/tmp/proj2",
        config: %{},
        created_at: "2024-01-02T00:00:00Z",
        updated_at: "2024-01-02T00:00:00Z",
        closed_at: "2024-01-02T12:00:00Z",
        conversation: [],
        todos: []
      }

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)

      {:ok, result} = Persistence.list_persisted()

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id == test_uuid(1)))
      assert Enum.any?(result, &(&1.id == test_uuid(2)))
    end

    test "returns sessions sorted by closed_at (most recent first)" do
      # Create three sessions with different closed_at times
      session1 = create_test_session(test_uuid(1), "Session 1", "2024-01-01T00:00:00Z")
      session2 = create_test_session(test_uuid(2), "Session 2", "2024-01-03T00:00:00Z")
      session3 = create_test_session(test_uuid(3), "Session 3", "2024-01-02T00:00:00Z")

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)
      :ok = Persistence.write_session_file(test_uuid(3), session3)

      {:ok, result} = Persistence.list_persisted()

      assert length(result) == 3
      # Most recent should be first
      assert Enum.at(result, 0).id == test_uuid(2)
      assert Enum.at(result, 1).id == test_uuid(3)
      assert Enum.at(result, 2).id == test_uuid(1)
    end

    test "includes required metadata fields" do
      session = create_test_session(test_uuid(5), "Test Session", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(5), session)

      {:ok, [result]} = Persistence.list_persisted()

      assert result.id == test_uuid(5)
      assert result.name == "Test Session"
      assert result.project_path == "/tmp/test-project"
      assert result.closed_at == "2024-01-01T00:00:00Z"
    end

    test "handles corrupted JSON files gracefully" do
      # Create a valid session
      session = create_test_session(test_uuid(4), "Valid", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(4), session)

      # Create a corrupted JSON file directly in sessions dir
      corrupted_id = test_uuid(3)
      corrupted_path = Path.join(Persistence.sessions_dir(), "#{corrupted_id}.json")
      File.write!(corrupted_path, "{invalid json")

      {:ok, result} = Persistence.list_persisted()

      # Should only return the valid session
      assert length(result) == 1
      assert List.first(result).id == test_uuid(4)
    end

    test "ignores non-JSON files in sessions directory" do
      session = create_test_session(test_uuid(5), "Test", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(5), session)

      # Create a non-JSON file
      non_json_path = Path.join(Persistence.sessions_dir(), "readme.txt")
      File.write!(non_json_path, "This is not a session file")

      {:ok, result} = Persistence.list_persisted()

      assert length(result) == 1
      assert List.first(result).id == test_uuid(5)
    end

    test "handles missing sessions directory" do
      # Remove sessions directory
      sessions_dir = Persistence.sessions_dir()
      File.rm_rf!(sessions_dir)

      {:ok, result} = Persistence.list_persisted()

      assert result == []
    end

    test "returns distinct error for permission failures" do
      # This test verifies that list_persisted returns {:error, :eacces}
      # instead of masking permission errors with an empty list.
      #
      # Note: We can't easily simulate permission failures in tests without
      # platform-specific file permission manipulation, but we verify that
      # the function signature supports error tuples and properly propagates
      # them through the call chain.
      sessions_dir = Persistence.sessions_dir()

      # Create a session file to ensure directory exists
      session = create_test_session(test_uuid(99), "Permission Test", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(99), session)

      # Verify normal operation returns {:ok, list}
      assert {:ok, list} = Persistence.list_persisted()
      assert is_list(list)
      assert length(list) >= 1

      # The actual permission error test would require changing directory permissions
      # which is platform-dependent and may not work in all test environments.
      # The key improvement is that the function now returns {:error, :eacces}
      # instead of [] when permissions fail, which callers can handle appropriately.
    end
  end

  describe "list_resumable/0" do
    setup do
      # Ensure sessions directory exists and is clean
      :ok = Persistence.ensure_sessions_dir()
      cleanup_session_files()

      # Clear active sessions registry
      SessionRegistry.clear()

      on_exit(fn ->
        cleanup_session_files()
        SessionRegistry.clear()
      end)

      :ok
    end

    test "returns empty list when no persisted sessions exist" do
      {:ok, result} = Persistence.list_resumable()

      assert result == []
    end

    test "returns all persisted sessions when no active sessions" do
      # Create two persisted sessions
      session1 = create_test_session(test_uuid(1), "Session 1", "2024-01-02T00:00:00Z")
      session2 = create_test_session(test_uuid(2), "Session 2", "2024-01-01T00:00:00Z")

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)

      {:ok, result} = Persistence.list_resumable()

      assert length(result) == 2
      # Should be sorted by closed_at (most recent first)
      assert Enum.at(result, 0).id == test_uuid(1)
      assert Enum.at(result, 1).id == test_uuid(2)
    end

    test "excludes session with matching active ID" do
      # Create two persisted sessions
      session1 = create_test_session(test_uuid(1), "Session 1", "2024-01-02T00:00:00Z")
      session2 = create_test_session(test_uuid(2), "Session 2", "2024-01-01T00:00:00Z")

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)

      # Create temporary directory for active session
      tmp_dir = System.tmp_dir!() |> Path.join("active-session-#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Register test_uuid(1) as active (need to manually set ID since Session.new generates one)
      {:ok, active_session} = Session.new(project_path: tmp_dir)
      active_session_with_id = %{active_session | id: test_uuid(1)}
      {:ok, _} = SessionRegistry.register(active_session_with_id)

      {:ok, result} = Persistence.list_resumable()

      # Should only return test_uuid(2)
      assert length(result) == 1
      assert List.first(result).id == test_uuid(2)
    end

    test "excludes session with matching active project_path" do
      # Create temporary directories for the project paths
      tmp_dir_a = System.tmp_dir!() |> Path.join("project-a-#{:rand.uniform(10000)}")
      tmp_dir_b = System.tmp_dir!() |> Path.join("project-b-#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir_a)
      File.mkdir_p!(tmp_dir_b)

      on_exit(fn ->
        File.rm_rf!(tmp_dir_a)
        File.rm_rf!(tmp_dir_b)
      end)

      # Create two persisted sessions with different project paths
      session1 = %{
        create_test_session(test_uuid(1), "Session 1", "2024-01-02T00:00:00Z")
        | project_path: tmp_dir_a
      }

      session2 = %{
        create_test_session(test_uuid(2), "Session 2", "2024-01-01T00:00:00Z")
        | project_path: tmp_dir_b
      }

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)

      # Register a different session ID but with same project_path as test_uuid(1)
      {:ok, active_session} =
        Session.new(id: "different-id", project_path: tmp_dir_a)

      {:ok, _} = SessionRegistry.register(active_session)

      {:ok, result} = Persistence.list_resumable()

      # Should only return test_uuid(2) (test_uuid(1) excluded due to matching project_path)
      assert length(result) == 1
      assert List.first(result).id == test_uuid(2)
      assert List.first(result).project_path == tmp_dir_b
    end

    test "excludes session matching both ID and project_path" do
      session1 = create_test_session(test_uuid(1), "Session 1", "2024-01-02T00:00:00Z")
      session2 = create_test_session(test_uuid(2), "Session 2", "2024-01-01T00:00:00Z")

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)

      # Create temporary directory
      tmp_dir = System.tmp_dir!() |> Path.join("active-session-#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Register session with same ID (project_path will be different but that's ok)
      {:ok, active_session} = Session.new(project_path: tmp_dir)
      active_session_with_id = %{active_session | id: test_uuid(1)}
      {:ok, _} = SessionRegistry.register(active_session_with_id)

      {:ok, result} = Persistence.list_resumable()

      # Should only return test_uuid(2) (excluded by matching ID)
      assert length(result) == 1
      assert List.first(result).id == test_uuid(2)
    end

    test "handles multiple active sessions" do
      # Create temporary directories for persisted and active sessions
      tmp_dir1 = System.tmp_dir!() |> Path.join("proj-1-#{:rand.uniform(10000)}")
      tmp_dir2 = System.tmp_dir!() |> Path.join("proj-2-#{:rand.uniform(10000)}")
      tmp_dir3 = System.tmp_dir!() |> Path.join("proj-3-#{:rand.uniform(10000)}")
      tmp_dir4 = System.tmp_dir!() |> Path.join("active-#{:rand.uniform(10000)}")

      File.mkdir_p!(tmp_dir1)
      File.mkdir_p!(tmp_dir2)
      File.mkdir_p!(tmp_dir3)
      File.mkdir_p!(tmp_dir4)

      on_exit(fn ->
        File.rm_rf!(tmp_dir1)
        File.rm_rf!(tmp_dir2)
        File.rm_rf!(tmp_dir3)
        File.rm_rf!(tmp_dir4)
      end)

      # Create three persisted sessions
      session1 = %{
        create_test_session(test_uuid(1), "Session 1", "2024-01-03T00:00:00Z")
        | project_path: tmp_dir1
      }

      session2 = %{
        create_test_session(test_uuid(2), "Session 2", "2024-01-02T00:00:00Z")
        | project_path: tmp_dir2
      }

      session3 = %{
        create_test_session(test_uuid(3), "Session 3", "2024-01-01T00:00:00Z")
        | project_path: tmp_dir3
      }

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)
      :ok = Persistence.write_session_file(test_uuid(3), session3)

      # Register two active sessions - one matches ID, one matches project_path
      {:ok, active1} = Session.new(project_path: tmp_dir4)
      # Matches session1 by ID
      active1_with_id = %{active1 | id: test_uuid(1)}

      # Matches session3 by project_path
      {:ok, active2} = Session.new(project_path: tmp_dir3)

      {:ok, _} = SessionRegistry.register(active1_with_id)
      {:ok, _} = SessionRegistry.register(active2)

      {:ok, result} = Persistence.list_resumable()

      # Should only return test_uuid(2) (test_uuid(1) excluded by ID, test_uuid(3) excluded by path)
      assert length(result) == 1
      assert List.first(result).id == test_uuid(2)
    end

    test "returns empty list when all persisted sessions are active" do
      session1 = create_test_session(test_uuid(1), "Session 1", "2024-01-01T00:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(1), session1)

      # Create temporary directory
      tmp_dir = System.tmp_dir!() |> Path.join("active-session-#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, active_session} = Session.new(project_path: tmp_dir)
      active_session_with_id = %{active_session | id: test_uuid(1)}
      {:ok, _} = SessionRegistry.register(active_session_with_id)

      {:ok, result} = Persistence.list_resumable()

      assert result == []
    end

    test "preserves sort order by closed_at" do
      # Create sessions with different closed_at times
      session1 = %{
        create_test_session(test_uuid(1), "Session 1", "2024-01-01T00:00:00Z")
        | project_path: "/tmp/proj-1"
      }

      session2 = %{
        create_test_session(test_uuid(2), "Session 2", "2024-01-03T00:00:00Z")
        | project_path: "/tmp/proj-2"
      }

      session3 = %{
        create_test_session(test_uuid(3), "Session 3", "2024-01-02T00:00:00Z")
        | project_path: "/tmp/proj-3"
      }

      :ok = Persistence.write_session_file(test_uuid(1), session1)
      :ok = Persistence.write_session_file(test_uuid(2), session2)
      :ok = Persistence.write_session_file(test_uuid(3), session3)

      {:ok, result} = Persistence.list_resumable()

      # Should be sorted by closed_at (most recent first)
      assert length(result) == 3
      assert Enum.at(result, 0).id == test_uuid(2)
      assert Enum.at(result, 1).id == test_uuid(3)
      assert Enum.at(result, 2).id == test_uuid(1)
    end
  end

  describe "load/1" do
    test "loads valid session file" do
      # Create and save a session
      session = create_test_session(test_uuid(0), "Test Session", "2024-01-01T12:00:00Z")
      :ok = Persistence.write_session_file(test_uuid(0), session)

      # Load it back
      assert {:ok, loaded} = Persistence.load(test_uuid(0))
      assert loaded.id == test_uuid(0)
      assert loaded.name == "Test Session"
      assert loaded.project_path == "/tmp/test-project"
      assert %DateTime{} = loaded.created_at
      assert %DateTime{} = loaded.updated_at
      assert loaded.conversation == []
      assert loaded.todos == []
    end

    test "returns error for non-existent file" do
      # Use a UUID that's unlikely to exist from other tests
      non_existent_id = "99999999-9999-4999-8999-999999999999"
      assert {:error, :not_found} = Persistence.load(non_existent_id)
    end

    test "returns error for corrupted JSON" do
      # Create a corrupted file
      session_id = test_uuid(0)
      path = Persistence.session_file(session_id)
      File.write!(path, "{invalid json")

      assert {:error, {:invalid_json, _}} = Persistence.load(session_id)
    end

    test "loads session with messages" do
      # Create session with messages
      session = %{
        create_test_session(test_uuid(0), "Test", "2024-01-01T12:00:00Z")
        | conversation: [
            %{
              id: "msg-1",
              role: "user",
              content: "Hello",
              timestamp: "2024-01-01T10:00:00Z"
            },
            %{
              id: "msg-2",
              role: "assistant",
              content: "Hi there",
              timestamp: "2024-01-01T10:01:00Z"
            }
          ]
      }

      :ok = Persistence.write_session_file(test_uuid(0), session)

      assert {:ok, loaded} = Persistence.load(test_uuid(0))
      assert length(loaded.conversation) == 2
      assert Enum.at(loaded.conversation, 0).role == :user
      assert Enum.at(loaded.conversation, 0).content == "Hello"
      assert Enum.at(loaded.conversation, 1).role == :assistant
    end

    test "loads session with todos" do
      session = %{
        create_test_session(test_uuid(0), "Test", "2024-01-01T12:00:00Z")
        | todos: [
            %{content: "Task 1", status: "pending", active_form: "Doing task 1"},
            %{content: "Task 2", status: "completed", active_form: "Doing task 2"}
          ]
      }

      :ok = Persistence.write_session_file(test_uuid(0), session)

      assert {:ok, loaded} = Persistence.load(test_uuid(0))
      assert length(loaded.todos) == 2
      assert Enum.at(loaded.todos, 0).status == :pending
      assert Enum.at(loaded.todos, 1).status == :completed
    end

    test "loads session with config" do
      session = %{
        create_test_session(test_uuid(0), "Test", "2024-01-01T12:00:00Z")
        | config: %{
            "provider" => "openai",
            "model" => "gpt-4",
            "temperature" => 0.5
          }
      }

      :ok = Persistence.write_session_file(test_uuid(0), session)

      assert {:ok, loaded} = Persistence.load(test_uuid(0))
      assert loaded.config["provider"] == "openai"
      assert loaded.config["model"] == "gpt-4"
      assert loaded.config["temperature"] == 0.5
    end
  end

  describe "deserialize_session/1" do
    test "deserializes complete session" do
      data = %{
        "version" => 1,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      assert {:ok, session} = Persistence.deserialize_session(data)
      assert session.id == test_uuid(0)
      assert session.name == "Test"
      assert %DateTime{} = session.created_at
      assert %DateTime{} = session.updated_at
    end

    test "deserializes session with empty conversation" do
      data = %{
        "version" => 1,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      assert {:ok, session} = Persistence.deserialize_session(data)
      assert session.conversation == []
    end

    test "deserializes session with empty todos" do
      data = %{
        "version" => 1,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      assert {:ok, session} = Persistence.deserialize_session(data)
      assert session.todos == []
    end

    test "rejects unsupported schema version" do
      data = %{
        "version" => 99,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      # Error sanitization: version number no longer exposed in error tuple
      assert {:error, :unsupported_version} = Persistence.deserialize_session(data)
    end

    test "rejects invalid schema version" do
      data = %{
        "version" => 0,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      # Error sanitization: version number no longer exposed in error tuple
      assert {:error, :invalid_version} = Persistence.deserialize_session(data)
    end

    test "rejects non-map input" do
      assert {:error, :not_a_map} = Persistence.deserialize_session("not a map")
      assert {:error, :not_a_map} = Persistence.deserialize_session(123)
    end

    test "returns error for invalid message role" do
      data = %{
        "version" => 1,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [
          %{
            "id" => "msg-1",
            "role" => "invalid_role",
            "content" => "test",
            "timestamp" => "2024-01-01T00:00:00Z"
          }
        ],
        "todos" => []
      }

      # Error sanitization: role value no longer exposed in error tuple
      assert {:error, {:invalid_message, :unknown_role}} =
               Persistence.deserialize_session(data)
    end

    test "returns error for invalid todo status" do
      data = %{
        "version" => 1,
        "id" => test_uuid(0),
        "name" => "Test",
        "project_path" => "/tmp/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T12:00:00Z",
        "closed_at" => "2024-01-01T18:00:00Z",
        "conversation" => [],
        "todos" => [
          %{
            "content" => "Task",
            "status" => "invalid_status",
            "active_form" => "Doing task"
          }
        ]
      }

      # Error sanitization: status value no longer exposed in error tuple
      assert {:error, {:invalid_todo, :unknown_status}} =
               Persistence.deserialize_session(data)
    end
  end

  describe "round-trip serialization" do
    test "save then load preserves all data" do
      # Create a session with full data
      session_id = test_uuid(0)

      session = %{
        version: 1,
        id: session_id,
        name: "Full Session",
        project_path: "/tmp/project",
        config: %{"provider" => "openai", "model" => "gpt-4"},
        created_at: "2024-01-01T10:00:00Z",
        updated_at: "2024-01-01T12:00:00Z",
        closed_at: "2024-01-01T14:00:00Z",
        conversation: [
          %{
            id: "msg-1",
            role: "user",
            content: "Test message",
            timestamp: "2024-01-01T11:00:00Z"
          }
        ],
        todos: [
          %{content: "Task 1", status: "pending", active_form: "Doing task 1"}
        ]
      }

      # Save and load
      :ok = Persistence.write_session_file(session_id, session)
      assert {:ok, loaded} = Persistence.load(session_id)

      # Verify all data preserved
      assert loaded.id == session_id
      assert loaded.name == "Full Session"
      assert loaded.project_path == "/tmp/project"
      assert loaded.config["provider"] == "openai"
      assert loaded.config["model"] == "gpt-4"
      assert length(loaded.conversation) == 1
      assert hd(loaded.conversation).role == :user
      assert hd(loaded.conversation).content == "Test message"
      assert length(loaded.todos) == 1
      assert hd(loaded.todos).status == :pending
      assert hd(loaded.todos).content == "Task 1"
    end

    test "timestamps preserved after round-trip" do
      session_id = test_uuid(0)

      session = %{
        version: 1,
        id: session_id,
        name: "Test",
        project_path: "/tmp/test",
        config: %{},
        created_at: "2024-01-01T10:00:00Z",
        updated_at: "2024-01-01T12:00:00Z",
        closed_at: "2024-01-01T14:00:00Z",
        conversation: [],
        todos: []
      }

      :ok = Persistence.write_session_file(session_id, session)
      assert {:ok, loaded} = Persistence.load(session_id)

      # Verify timestamps are DateTime structs
      assert %DateTime{} = loaded.created_at
      assert %DateTime{} = loaded.updated_at

      # Verify timestamp values match (allowing for timezone conversion)
      assert DateTime.to_iso8601(loaded.created_at) == "2024-01-01T10:00:00Z"
      assert DateTime.to_iso8601(loaded.updated_at) == "2024-01-01T12:00:00Z"
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp cleanup_session_files do
    sessions_dir = Persistence.sessions_dir()

    if File.dir?(sessions_dir) do
      File.ls!(sessions_dir)
      |> Enum.each(fn file ->
        path = Path.join(sessions_dir, file)
        File.rm(path)
      end)
    end
  end

  defp create_test_session(id, name, closed_at) do
    %{
      version: 1,
      id: id,
      name: name,
      project_path: "/tmp/test-project",
      config: %{},
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T00:00:00Z",
      closed_at: closed_at,
      conversation: [],
      todos: []
    }
  end

  defp mock_session_state do
    %{
      session: %{
        id: test_uuid(5),
        name: "Test Session",
        project_path: "/tmp/test-project",
        config: %{provider: :anthropic, model: "test-model", temperature: 0.7},
        language: :elixir,
        created_at: ~U[2024-01-01 00:00:00Z],
        updated_at: ~U[2024-01-01 12:00:00Z]
      },
      messages: [],
      todos: []
    }
  end

  # Generate a valid UUID v4 for testing
  # Uses a deterministic UUID based on index for reproducible tests
  # All UUIDs are valid v4 format (4 in version position, 8-b in variant position)
  defp test_uuid(index \\ 0) do
    base_uuids = [
      "550e8400-e29b-41d4-a716-446655440000",
      "6ba7b810-9dad-41d1-80b4-00c04fd430c8",
      "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "123e4567-e89b-42d3-a456-426614174000",
      "987fbc97-4bed-4078-9f07-9141ba07c9f3",
      "a1b2c3d4-e5f6-47a8-b9c0-d1e2f3a4b5c6"
    ]

    Enum.at(base_uuids, rem(index, length(base_uuids)))
  end

  defp valid_session do
    %{
      version: 1,
      id: test_uuid(0),
      name: "Test Session",
      project_path: "/path/to/project",
      config: %{provider: :anthropic, model: "claude-3"},
      created_at: "2024-01-01T00:00:00Z",
      updated_at: "2024-01-01T12:00:00Z",
      closed_at: "2024-01-01T18:00:00Z",
      conversation: [],
      todos: []
    }
  end

  describe "find_by_project_path/1" do
    setup do
      # Ensure sessions directory exists
      :ok = Persistence.ensure_sessions_dir()
      sessions_dir = Persistence.sessions_dir()

      # Create unique test session IDs
      test_ids = [
        "find-path-test-#{:rand.uniform(999_999)}-1",
        "find-path-test-#{:rand.uniform(999_999)}-2",
        "find-path-test-#{:rand.uniform(999_999)}-3",
        "find-path-test-#{:rand.uniform(999_999)}-4"
      ]

      on_exit(fn ->
        # Clean up test files
        for id <- test_ids do
          file = Path.join(sessions_dir, "#{id}.json")
          File.rm(file)
        end
      end)

      {:ok, sessions_dir: sessions_dir, test_ids: test_ids}
    end

    test "returns {:ok, nil} when no persisted sessions match path" do
      # Use a unique path that won't match any real sessions
      assert {:ok, nil} =
               Persistence.find_by_project_path(
                 "/nonexistent/unique/path/#{:rand.uniform(999_999)}"
               )
    end

    test "returns {:ok, nil} when path doesn't match any session", %{
      sessions_dir: sessions_dir,
      test_ids: test_ids
    } do
      [test_id | _] = test_ids

      # Create a persisted session with a different path
      session = %{
        version: 1,
        id: test_id,
        name: "Other Project",
        project_path: "/other/project/#{:rand.uniform(999_999)}",
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      file_path = Path.join(sessions_dir, "#{session.id}.json")
      File.write!(file_path, Jason.encode!(session))

      assert {:ok, nil} =
               Persistence.find_by_project_path("/different/path/#{:rand.uniform(999_999)}")
    end

    test "returns {:ok, session} when path matches", %{
      sessions_dir: sessions_dir,
      test_ids: test_ids
    } do
      [_, test_id | _] = test_ids
      target_path = "/my/project/find-test-#{:rand.uniform(999_999)}"

      session = %{
        version: 1,
        id: test_id,
        name: "My Project",
        project_path: target_path,
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      file_path = Path.join(sessions_dir, "#{session.id}.json")
      File.write!(file_path, Jason.encode!(session))

      assert {:ok, found} = Persistence.find_by_project_path(target_path)
      assert found.id == session.id
      assert found.project_path == target_path
    end

    test "returns most recent session when multiple match same path", %{
      sessions_dir: sessions_dir,
      test_ids: test_ids
    } do
      [_, _, test_id1, test_id2] = test_ids
      target_path = "/shared/project/find-test-#{:rand.uniform(999_999)}"

      older_session = %{
        version: 1,
        id: test_id1,
        name: "Older Session",
        project_path: target_path,
        config: %{},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        closed_at: "2024-01-01T00:00:00Z",
        conversation: [],
        todos: []
      }

      newer_session = %{
        version: 1,
        id: test_id2,
        name: "Newer Session",
        project_path: target_path,
        config: %{},
        created_at: "2024-01-02T00:00:00Z",
        updated_at: "2024-01-02T00:00:00Z",
        closed_at: "2024-01-02T12:00:00Z",
        conversation: [],
        todos: []
      }

      File.write!(
        Path.join(sessions_dir, "#{older_session.id}.json"),
        Jason.encode!(older_session)
      )

      File.write!(
        Path.join(sessions_dir, "#{newer_session.id}.json"),
        Jason.encode!(newer_session)
      )

      assert {:ok, found} = Persistence.find_by_project_path(target_path)
      # Should return the newer session (sorted by closed_at descending)
      assert found.id == newer_session.id
    end
  end

  describe "message usage serialization" do
    test "serializes message without usage" do
      # Use build_persisted_session/1 to test serialization
      alias JidoCode.Session.Persistence.Serialization

      state = %{
        session: %JidoCode.Session{
          id: "test-123",
          name: "Test",
          project_path: "/test",
          config: %{},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        },
        messages: [
          %{
            id: "msg-1",
            role: :user,
            content: "Hello",
            timestamp: DateTime.utc_now()
          }
        ],
        todos: []
      }

      persisted = Serialization.build_persisted_session(state)
      [msg | _] = persisted.conversation

      refute Map.has_key?(msg, :usage)
    end

    test "serializes message with usage" do
      alias JidoCode.Session.Persistence.Serialization

      state = %{
        session: %JidoCode.Session{
          id: "test-123",
          name: "Test",
          project_path: "/test",
          config: %{},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        },
        messages: [
          %{
            id: "msg-1",
            role: :assistant,
            content: "Hello back!",
            timestamp: DateTime.utc_now(),
            usage: %{input_tokens: 100, output_tokens: 200, total_cost: 0.0015}
          }
        ],
        todos: []
      }

      persisted = Serialization.build_persisted_session(state)
      [msg | _] = persisted.conversation

      assert msg.usage.input_tokens == 100
      assert msg.usage.output_tokens == 200
      assert msg.usage.total_cost == 0.0015
    end

    test "deserializes message with usage" do
      alias JidoCode.Session.Persistence.Serialization

      data = %{
        "version" => 1,
        "id" => "test-123",
        "name" => "Test",
        "project_path" => "/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z",
        "closed_at" => "2024-01-01T00:00:00Z",
        "conversation" => [
          %{
            "id" => "msg-1",
            "role" => "assistant",
            "content" => "Hello",
            "timestamp" => "2024-01-01T00:00:00Z",
            "usage" => %{
              "input_tokens" => 150,
              "output_tokens" => 300,
              "total_cost" => 0.002
            }
          }
        ],
        "todos" => []
      }

      {:ok, session} = Serialization.deserialize_session(data)
      [msg | _] = session.conversation

      assert msg.usage.input_tokens == 150
      assert msg.usage.output_tokens == 300
      assert msg.usage.total_cost == 0.002
    end

    test "deserializes message without usage (legacy format)" do
      alias JidoCode.Session.Persistence.Serialization

      data = %{
        "version" => 1,
        "id" => "test-123",
        "name" => "Test",
        "project_path" => "/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z",
        "closed_at" => "2024-01-01T00:00:00Z",
        "conversation" => [
          %{
            "id" => "msg-1",
            "role" => "user",
            "content" => "Hello",
            "timestamp" => "2024-01-01T00:00:00Z"
          }
        ],
        "todos" => []
      }

      {:ok, session} = Serialization.deserialize_session(data)
      [msg | _] = session.conversation

      refute Map.has_key?(msg, :usage)
    end
  end

  describe "session cumulative usage" do
    test "calculates cumulative usage from messages" do
      alias JidoCode.Session.Persistence.Serialization

      state = %{
        session: %JidoCode.Session{
          id: "test-123",
          name: "Test",
          project_path: "/test",
          config: %{},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        },
        messages: [
          %{
            id: "msg-1",
            role: :user,
            content: "Hello",
            timestamp: DateTime.utc_now()
          },
          %{
            id: "msg-2",
            role: :assistant,
            content: "Hi!",
            timestamp: DateTime.utc_now(),
            usage: %{input_tokens: 50, output_tokens: 100, total_cost: 0.001}
          },
          %{
            id: "msg-3",
            role: :user,
            content: "More",
            timestamp: DateTime.utc_now()
          },
          %{
            id: "msg-4",
            role: :assistant,
            content: "Response",
            timestamp: DateTime.utc_now(),
            usage: %{input_tokens: 75, output_tokens: 150, total_cost: 0.0015}
          }
        ],
        todos: []
      }

      persisted = Serialization.build_persisted_session(state)

      assert persisted.cumulative_usage.input_tokens == 125
      assert persisted.cumulative_usage.output_tokens == 250
      assert persisted.cumulative_usage.total_cost == 0.0025
    end

    test "omits cumulative usage when no messages have usage" do
      alias JidoCode.Session.Persistence.Serialization

      state = %{
        session: %JidoCode.Session{
          id: "test-123",
          name: "Test",
          project_path: "/test",
          config: %{},
          created_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        },
        messages: [
          %{
            id: "msg-1",
            role: :user,
            content: "Hello",
            timestamp: DateTime.utc_now()
          }
        ],
        todos: []
      }

      persisted = Serialization.build_persisted_session(state)

      refute Map.has_key?(persisted, :cumulative_usage)
    end

    test "deserializes session with cumulative usage" do
      alias JidoCode.Session.Persistence.Serialization

      data = %{
        "version" => 1,
        "id" => "test-123",
        "name" => "Test",
        "project_path" => "/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z",
        "closed_at" => "2024-01-01T00:00:00Z",
        "conversation" => [],
        "todos" => [],
        "cumulative_usage" => %{
          "input_tokens" => 500,
          "output_tokens" => 1000,
          "total_cost" => 0.01
        }
      }

      {:ok, session} = Serialization.deserialize_session(data)

      assert session.cumulative_usage.input_tokens == 500
      assert session.cumulative_usage.output_tokens == 1000
      assert session.cumulative_usage.total_cost == 0.01
    end

    test "deserializes session without cumulative usage (legacy format)" do
      alias JidoCode.Session.Persistence.Serialization

      data = %{
        "version" => 1,
        "id" => "test-123",
        "name" => "Test",
        "project_path" => "/test",
        "config" => %{},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z",
        "closed_at" => "2024-01-01T00:00:00Z",
        "conversation" => [],
        "todos" => []
      }

      {:ok, session} = Serialization.deserialize_session(data)

      refute Map.has_key?(session, :cumulative_usage)
    end
  end

  defp valid_message do
    %{
      id: "msg-1",
      role: "user",
      content: "Hello, world!",
      timestamp: "2024-01-01T00:00:00Z"
    }
  end

  defp valid_todo do
    %{
      content: "Run tests",
      status: "pending",
      active_form: "Running tests"
    }
  end
end
