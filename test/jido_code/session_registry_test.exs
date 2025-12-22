defmodule JidoCode.SessionRegistryTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry

  # Note: async: false because ETS tables are shared state

  setup do
    # Clean up any existing table before each test
    if SessionRegistry.table_exists?() do
      :ets.delete(JidoCode.SessionRegistry)
    end

    on_exit(fn ->
      # Clean up after test
      if SessionRegistry.table_exists?() do
        :ets.delete(JidoCode.SessionRegistry)
      end
    end)

    :ok
  end

  # Helper to create a valid session for testing
  defp create_test_session(opts \\ []) do
    now = DateTime.utc_now()
    id = Keyword.get(opts, :id, Session.generate_id())
    name = Keyword.get(opts, :name, "test-project")
    project_path = Keyword.get(opts, :project_path, "/tmp/test-project-#{:rand.uniform(100_000)}")

    %Session{
      id: id,
      name: name,
      project_path: project_path,
      config: %{
        provider: "anthropic",
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      },
      created_at: now,
      updated_at: now
    }
  end

  describe "table_exists?/0" do
    test "returns false when table does not exist" do
      refute SessionRegistry.table_exists?()
    end

    test "returns true when table exists" do
      SessionRegistry.create_table()
      assert SessionRegistry.table_exists?()
    end
  end

  describe "create_table/0" do
    test "creates ETS table successfully" do
      refute SessionRegistry.table_exists?()

      assert :ok = SessionRegistry.create_table()
      assert SessionRegistry.table_exists?()
    end

    test "is idempotent - can be called multiple times" do
      assert :ok = SessionRegistry.create_table()
      assert :ok = SessionRegistry.create_table()
      assert :ok = SessionRegistry.create_table()

      assert SessionRegistry.table_exists?()
    end

    test "creates table with correct name" do
      SessionRegistry.create_table()

      # Table should be named JidoCode.SessionRegistry
      assert :ets.whereis(JidoCode.SessionRegistry) != :undefined
    end

    test "creates table as :set type" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :type) == :set
    end

    test "creates table as :named_table" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :named_table) == true
    end

    test "creates table with :public protection" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :protection) == :public
    end

    test "creates table with read_concurrency enabled" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :read_concurrency) == true
    end

    test "creates table with write_concurrency enabled" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :write_concurrency) == true
    end
  end

  describe "max_sessions/0" do
    test "returns default of 10" do
      assert SessionRegistry.max_sessions() == 10
    end

    test "returns configured value when set" do
      # Store original value
      original = Application.get_env(:jido_code, :max_sessions)

      try do
        Application.put_env(:jido_code, :max_sessions, 25)
        assert SessionRegistry.max_sessions() == 25
      after
        # Restore original value
        if original do
          Application.put_env(:jido_code, :max_sessions, original)
        else
          Application.delete_env(:jido_code, :max_sessions)
        end
      end
    end

    test "register/1 respects configured max_sessions" do
      SessionRegistry.create_table()

      # Store original value
      original = Application.get_env(:jido_code, :max_sessions)

      try do
        # Set limit to 2
        Application.put_env(:jido_code, :max_sessions, 2)

        session1 = create_test_session(project_path: "/tmp/project1")
        session2 = create_test_session(project_path: "/tmp/project2")
        session3 = create_test_session(project_path: "/tmp/project3")

        assert {:ok, _} = SessionRegistry.register(session1)
        assert {:ok, _} = SessionRegistry.register(session2)
        assert {:error, {:session_limit_reached, 2, 2}} = SessionRegistry.register(session3)

        assert SessionRegistry.count() == 2
      after
        # Restore original value
        if original do
          Application.put_env(:jido_code, :max_sessions, original)
        else
          Application.delete_env(:jido_code, :max_sessions)
        end
      end
    end
  end

  describe "table is empty after creation" do
    test "table starts empty" do
      SessionRegistry.create_table()

      entries = :ets.tab2list(JidoCode.SessionRegistry)
      assert entries == []
    end

    test "table size is 0 after creation" do
      SessionRegistry.create_table()

      info = :ets.info(JidoCode.SessionRegistry)
      assert Keyword.get(info, :size) == 0
    end
  end

  describe "count/0" do
    test "returns 0 when table is empty" do
      SessionRegistry.create_table()
      assert SessionRegistry.count() == 0
    end

    test "returns 0 when table does not exist" do
      assert SessionRegistry.count() == 0
    end

    test "returns correct count after registrations" do
      SessionRegistry.create_table()

      {:ok, _} = SessionRegistry.register(create_test_session())
      assert SessionRegistry.count() == 1

      {:ok, _} = SessionRegistry.register(create_test_session())
      assert SessionRegistry.count() == 2

      {:ok, _} = SessionRegistry.register(create_test_session())
      assert SessionRegistry.count() == 3
    end
  end

  describe "register/1" do
    setup do
      SessionRegistry.create_table()
      :ok
    end

    test "registers a valid session successfully" do
      session = create_test_session()

      assert {:ok, registered} = SessionRegistry.register(session)
      assert registered.id == session.id
      assert registered.name == session.name
      assert registered.project_path == session.project_path
    end

    test "returns the same session struct on success" do
      session = create_test_session()

      {:ok, registered} = SessionRegistry.register(session)
      assert registered == session
    end

    test "increments count after successful registration" do
      session = create_test_session()

      assert SessionRegistry.count() == 0
      {:ok, _} = SessionRegistry.register(session)
      assert SessionRegistry.count() == 1
    end

    test "session can be found in ETS table after registration" do
      session = create_test_session()

      {:ok, _} = SessionRegistry.register(session)

      [{id, stored}] = :ets.lookup(JidoCode.SessionRegistry, session.id)
      assert id == session.id
      assert stored == session
    end

    test "returns error for duplicate session ID" do
      session1 = create_test_session(id: "same-id", project_path: "/tmp/project1")
      session2 = create_test_session(id: "same-id", project_path: "/tmp/project2")

      {:ok, _} = SessionRegistry.register(session1)
      assert {:error, :session_exists} = SessionRegistry.register(session2)
    end

    test "returns error for duplicate project_path" do
      session1 = create_test_session(project_path: "/tmp/same-project")
      session2 = create_test_session(project_path: "/tmp/same-project")

      {:ok, _} = SessionRegistry.register(session1)
      assert {:error, :project_already_open} = SessionRegistry.register(session2)
    end

    test "returns error when session limit (10) is reached" do
      # Register 10 sessions
      for i <- 1..10 do
        session = create_test_session(project_path: "/tmp/project-#{i}")
        {:ok, _} = SessionRegistry.register(session)
      end

      assert SessionRegistry.count() == 10

      # 11th session should fail
      session11 = create_test_session(project_path: "/tmp/project-11")
      assert {:error, {:session_limit_reached, 10, 10}} = SessionRegistry.register(session11)
    end

    test "does not increment count when registration fails" do
      session1 = create_test_session(id: "same-id", project_path: "/tmp/project1")
      session2 = create_test_session(id: "same-id", project_path: "/tmp/project2")

      {:ok, _} = SessionRegistry.register(session1)
      assert SessionRegistry.count() == 1

      {:error, :session_exists} = SessionRegistry.register(session2)
      assert SessionRegistry.count() == 1
    end

    test "allows different sessions with same name" do
      session1 = create_test_session(name: "same-name", project_path: "/tmp/project1")
      session2 = create_test_session(name: "same-name", project_path: "/tmp/project2")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)

      assert SessionRegistry.count() == 2
    end

    test "can register up to exactly 10 sessions" do
      sessions =
        for i <- 1..10 do
          session = create_test_session(project_path: "/tmp/project-#{i}")
          {:ok, registered} = SessionRegistry.register(session)
          registered
        end

      assert length(sessions) == 10
      assert SessionRegistry.count() == 10
    end

    test "checks session limit before duplicate ID" do
      # Fill up to limit
      for i <- 1..10 do
        session = create_test_session(project_path: "/tmp/project-#{i}")
        {:ok, _} = SessionRegistry.register(session)
      end

      # Get the ID of an existing session
      [{existing_id, _}] =
        :ets.lookup(JidoCode.SessionRegistry, :ets.first(JidoCode.SessionRegistry))

      # Try to register with same ID - should hit limit first
      session = create_test_session(id: existing_id, project_path: "/tmp/project-11")
      assert {:error, {:session_limit_reached, 10, 10}} = SessionRegistry.register(session)
    end

    test "checks duplicate ID before duplicate path" do
      session1 = create_test_session(id: "same-id", project_path: "/tmp/same-path")

      {:ok, _} = SessionRegistry.register(session1)

      # Same ID and same path - should report ID error first
      session2 = create_test_session(id: "same-id", project_path: "/tmp/same-path")
      assert {:error, :session_exists} = SessionRegistry.register(session2)
    end
  end

  describe "lookup/1" do
    setup do
      SessionRegistry.create_table()
      :ok
    end

    test "finds registered session by ID" do
      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      assert {:ok, found} = SessionRegistry.lookup(session.id)
      assert found.id == session.id
      assert found.name == session.name
      assert found.project_path == session.project_path
    end

    test "returns the complete session struct" do
      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      {:ok, found} = SessionRegistry.lookup(session.id)
      assert found == session
    end

    test "returns error for unknown ID" do
      assert {:error, :not_found} = SessionRegistry.lookup("nonexistent-id")
    end

    test "returns error for unknown ID when table has sessions" do
      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      assert {:error, :not_found} = SessionRegistry.lookup("different-id")
    end

    test "finds correct session among multiple sessions" do
      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      session3 = create_test_session(project_path: "/tmp/project3")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      {:ok, found} = SessionRegistry.lookup(session2.id)
      assert found.id == session2.id
      assert found.project_path == "/tmp/project2"
    end
  end

  describe "lookup_by_path/1" do
    setup do
      SessionRegistry.create_table()
      :ok
    end

    test "finds session by project path" do
      session = create_test_session(project_path: "/tmp/my-project")
      {:ok, _} = SessionRegistry.register(session)

      assert {:ok, found} = SessionRegistry.lookup_by_path("/tmp/my-project")
      assert found.project_path == "/tmp/my-project"
      assert found.id == session.id
    end

    test "returns error for unknown path" do
      assert {:error, :not_found} = SessionRegistry.lookup_by_path("/tmp/nonexistent")
    end

    test "returns error for unknown path when table has sessions" do
      session = create_test_session(project_path: "/tmp/existing")
      {:ok, _} = SessionRegistry.register(session)

      assert {:error, :not_found} = SessionRegistry.lookup_by_path("/tmp/different")
    end

    test "finds correct session among multiple sessions" do
      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      session3 = create_test_session(project_path: "/tmp/project3")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      {:ok, found} = SessionRegistry.lookup_by_path("/tmp/project2")
      assert found.project_path == "/tmp/project2"
      assert found.id == session2.id
    end

    test "path lookup is exact match" do
      session = create_test_session(project_path: "/tmp/project")
      {:ok, _} = SessionRegistry.register(session)

      # Similar but not exact paths should not match
      assert {:error, :not_found} = SessionRegistry.lookup_by_path("/tmp/project/")
      assert {:error, :not_found} = SessionRegistry.lookup_by_path("/tmp/project/subdir")
      assert {:error, :not_found} = SessionRegistry.lookup_by_path("/tmp/proj")
    end
  end

  describe "lookup_by_name/1" do
    setup do
      SessionRegistry.create_table()
      :ok
    end

    test "finds session by name" do
      session = create_test_session(name: "my-project", project_path: "/tmp/my-project")
      {:ok, _} = SessionRegistry.register(session)

      assert {:ok, found} = SessionRegistry.lookup_by_name("my-project")
      assert found.name == "my-project"
      assert found.id == session.id
    end

    test "returns error for unknown name" do
      assert {:error, :not_found} = SessionRegistry.lookup_by_name("nonexistent")
    end

    test "returns error for unknown name when table has sessions" do
      session = create_test_session(name: "existing", project_path: "/tmp/existing")
      {:ok, _} = SessionRegistry.register(session)

      assert {:error, :not_found} = SessionRegistry.lookup_by_name("different")
    end

    test "returns first session when multiple have same name (oldest first)" do
      # Create sessions with same name but different paths
      # Use explicit timestamps to control ordering
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)
      later = DateTime.add(now, 60, :second)

      session1 = %Session{
        id: Session.generate_id(),
        name: "same-name",
        project_path: "/tmp/project1",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: later,
        updated_at: later
      }

      session2 = %Session{
        id: Session.generate_id(),
        name: "same-name",
        project_path: "/tmp/project2",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: earlier,
        updated_at: earlier
      }

      session3 = %Session{
        id: Session.generate_id(),
        name: "same-name",
        project_path: "/tmp/project3",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: now,
        updated_at: now
      }

      # Register in random order
      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      # Should return the oldest (session2)
      {:ok, found} = SessionRegistry.lookup_by_name("same-name")
      assert found.id == session2.id
      assert found.project_path == "/tmp/project2"
    end

    test "finds correct session among multiple with different names" do
      session1 = create_test_session(name: "project-a", project_path: "/tmp/project-a")
      session2 = create_test_session(name: "project-b", project_path: "/tmp/project-b")
      session3 = create_test_session(name: "project-c", project_path: "/tmp/project-c")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      {:ok, found} = SessionRegistry.lookup_by_name("project-b")
      assert found.name == "project-b"
      assert found.id == session2.id
    end

    test "name lookup is exact match" do
      session = create_test_session(name: "my-project", project_path: "/tmp/project")
      {:ok, _} = SessionRegistry.register(session)

      # Similar but not exact names should not match
      assert {:error, :not_found} = SessionRegistry.lookup_by_name("my-proj")
      assert {:error, :not_found} = SessionRegistry.lookup_by_name("My-Project")
      assert {:error, :not_found} = SessionRegistry.lookup_by_name("my-project ")
    end
  end

  describe "list_all/0" do
    test "returns empty list when table does not exist" do
      assert SessionRegistry.list_all() == []
    end

    test "returns empty list when table is empty" do
      SessionRegistry.create_table()
      assert SessionRegistry.list_all() == []
    end

    test "returns all registered sessions" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      session3 = create_test_session(project_path: "/tmp/project3")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      sessions = SessionRegistry.list_all()
      assert length(sessions) == 3

      ids = Enum.map(sessions, & &1.id)
      assert session1.id in ids
      assert session2.id in ids
      assert session3.id in ids
    end

    test "returns sessions sorted by created_at (oldest first)" do
      SessionRegistry.create_table()

      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)
      later = DateTime.add(now, 60, :second)

      session1 = %Session{
        id: Session.generate_id(),
        name: "project1",
        project_path: "/tmp/project1",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: later,
        updated_at: later
      }

      session2 = %Session{
        id: Session.generate_id(),
        name: "project2",
        project_path: "/tmp/project2",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: earlier,
        updated_at: earlier
      }

      session3 = %Session{
        id: Session.generate_id(),
        name: "project3",
        project_path: "/tmp/project3",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: now,
        updated_at: now
      }

      # Register in random order
      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      sessions = SessionRegistry.list_all()

      # Should be sorted: session2 (earliest), session3 (now), session1 (later)
      assert Enum.at(sessions, 0).id == session2.id
      assert Enum.at(sessions, 1).id == session3.id
      assert Enum.at(sessions, 2).id == session1.id
    end

    test "returns complete session structs" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      [returned] = SessionRegistry.list_all()
      assert returned == session
    end
  end

  describe "list_ids/0" do
    test "returns empty list when table does not exist" do
      assert SessionRegistry.list_ids() == []
    end

    test "returns empty list when table is empty" do
      SessionRegistry.create_table()
      assert SessionRegistry.list_ids() == []
    end

    test "returns all session IDs" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      session3 = create_test_session(project_path: "/tmp/project3")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      ids = SessionRegistry.list_ids()
      assert length(ids) == 3
      assert session1.id in ids
      assert session2.id in ids
      assert session3.id in ids
    end

    test "returns IDs sorted by created_at (oldest first)" do
      SessionRegistry.create_table()

      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)
      later = DateTime.add(now, 60, :second)

      session1 = %Session{
        id: "id-later",
        name: "project1",
        project_path: "/tmp/project1",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: later,
        updated_at: later
      }

      session2 = %Session{
        id: "id-earlier",
        name: "project2",
        project_path: "/tmp/project2",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: earlier,
        updated_at: earlier
      }

      session3 = %Session{
        id: "id-now",
        name: "project3",
        project_path: "/tmp/project3",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: now,
        updated_at: now
      }

      # Register in random order
      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      ids = SessionRegistry.list_ids()

      # Should be sorted: earlier, now, later
      assert ids == ["id-earlier", "id-now", "id-later"]
    end

    test "returns only strings" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      ids = SessionRegistry.list_ids()
      assert Enum.all?(ids, &is_binary/1)
    end
  end

  # ============================================================================
  # get_default_session_id/0 Tests
  # ============================================================================

  describe "get_default_session_id/0" do
    test "returns error when table does not exist" do
      assert {:error, :no_sessions} = SessionRegistry.get_default_session_id()
    end

    test "returns error when table is empty" do
      SessionRegistry.create_table()
      assert {:error, :no_sessions} = SessionRegistry.get_default_session_id()
    end

    test "returns first session ID when one session exists" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      assert {:ok, session.id} == SessionRegistry.get_default_session_id()
    end

    test "returns oldest session ID when multiple sessions exist" do
      SessionRegistry.create_table()

      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)
      later = DateTime.add(now, 60, :second)

      session1 = %Session{
        id: "id-later",
        name: "project1",
        project_path: "/tmp/project1",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: later,
        updated_at: later
      }

      session2 = %Session{
        id: "id-earlier",
        name: "project2",
        project_path: "/tmp/project2",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: earlier,
        updated_at: earlier
      }

      session3 = %Session{
        id: "id-now",
        name: "project3",
        project_path: "/tmp/project3",
        config: %{provider: "anthropic", model: "claude", temperature: 0.7, max_tokens: 4096},
        created_at: now,
        updated_at: now
      }

      # Register in random order
      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      # Should return the oldest (session2 - id-earlier)
      assert {:ok, "id-earlier"} = SessionRegistry.get_default_session_id()
    end

    test "returns string ID" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      {:ok, id} = SessionRegistry.get_default_session_id()
      assert is_binary(id)
    end

    test "returns error after clear" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      assert {:ok, _} = SessionRegistry.get_default_session_id()

      SessionRegistry.clear()

      assert {:error, :no_sessions} = SessionRegistry.get_default_session_id()
    end
  end

  # ============================================================================
  # unregister/1 Tests
  # ============================================================================

  describe "unregister/1" do
    test "removes session from registry" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)

      assert SessionRegistry.count() == 1

      result = SessionRegistry.unregister(session.id)

      assert result == :ok
      assert SessionRegistry.count() == 0
      assert SessionRegistry.lookup(session.id) == {:error, :not_found}
    end

    test "returns :ok even if session did not exist" do
      SessionRegistry.create_table()

      result = SessionRegistry.unregister("non-existent-id")

      assert result == :ok
    end

    test "returns :ok for previously registered then unregistered session" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)
      SessionRegistry.unregister(session.id)

      # Unregister again - should still return :ok
      result = SessionRegistry.unregister(session.id)

      assert result == :ok
    end

    test "decrements count after removal" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      {:ok, session1} = SessionRegistry.register(session1)
      {:ok, _session2} = SessionRegistry.register(session2)

      assert SessionRegistry.count() == 2

      SessionRegistry.unregister(session1.id)

      assert SessionRegistry.count() == 1
    end

    test "only removes the specified session" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      {:ok, session1} = SessionRegistry.register(session1)
      {:ok, session2} = SessionRegistry.register(session2)

      SessionRegistry.unregister(session1.id)

      assert SessionRegistry.lookup(session1.id) == {:error, :not_found}
      assert {:ok, ^session2} = SessionRegistry.lookup(session2.id)
    end

    test "allows re-registration after unregister" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)
      SessionRegistry.unregister(session.id)

      # Should be able to register a new session with same project path
      new_session = create_test_session()
      result = SessionRegistry.register(new_session)

      assert {:ok, _} = result
    end
  end

  # ============================================================================
  # clear/0 Tests
  # ============================================================================

  describe "clear/0" do
    test "removes all sessions from registry" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      session3 = create_test_session(project_path: "/tmp/project3")
      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)
      {:ok, _} = SessionRegistry.register(session3)

      assert SessionRegistry.count() == 3

      result = SessionRegistry.clear()

      assert result == :ok
      assert SessionRegistry.count() == 0
      assert SessionRegistry.list_all() == []
    end

    test "returns :ok when table is empty" do
      SessionRegistry.create_table()

      result = SessionRegistry.clear()

      assert result == :ok
    end

    test "returns :ok when table does not exist" do
      # Don't create the table
      result = SessionRegistry.clear()

      assert result == :ok
    end

    test "is idempotent - can be called multiple times" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, _} = SessionRegistry.register(session)

      assert SessionRegistry.clear() == :ok
      assert SessionRegistry.clear() == :ok
      assert SessionRegistry.clear() == :ok

      assert SessionRegistry.count() == 0
    end

    test "allows new registrations after clear" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      {:ok, _} = SessionRegistry.register(session1)

      SessionRegistry.clear()

      # Should be able to register new sessions
      session2 = create_test_session(project_path: "/tmp/project2")
      result = SessionRegistry.register(session2)

      assert {:ok, _} = result
      assert SessionRegistry.count() == 1
    end
  end

  # ============================================================================
  # update/1 Tests
  # ============================================================================

  describe "update/1" do
    test "updates existing session successfully" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)

      # Simulate a rename by creating updated session
      updated_session = %{session | name: "new-name", updated_at: DateTime.utc_now()}

      result = SessionRegistry.update(updated_session)

      assert {:ok, ^updated_session} = result
    end

    test "returns error for non-existent session" do
      SessionRegistry.create_table()

      session = create_test_session()
      # Don't register it

      result = SessionRegistry.update(session)

      assert result == {:error, :not_found}
    end

    test "updated session can be retrieved via lookup" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)

      updated_session = %{session | name: "updated-name"}
      {:ok, _} = SessionRegistry.update(updated_session)

      {:ok, retrieved} = SessionRegistry.lookup(session.id)

      assert retrieved.name == "updated-name"
    end

    test "update preserves other sessions" do
      SessionRegistry.create_table()

      session1 = create_test_session(project_path: "/tmp/project1")
      session2 = create_test_session(project_path: "/tmp/project2")
      {:ok, session1} = SessionRegistry.register(session1)
      {:ok, session2} = SessionRegistry.register(session2)

      updated_session1 = %{session1 | name: "updated-name"}
      {:ok, _} = SessionRegistry.update(updated_session1)

      # session2 should be unchanged
      {:ok, retrieved2} = SessionRegistry.lookup(session2.id)
      assert retrieved2 == session2

      # Count should still be 2
      assert SessionRegistry.count() == 2
    end

    test "update with changed config" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)

      new_config = %{session.config | temperature: 0.9, max_tokens: 8000}
      updated_session = %{session | config: new_config, updated_at: DateTime.utc_now()}
      {:ok, _} = SessionRegistry.update(updated_session)

      {:ok, retrieved} = SessionRegistry.lookup(session.id)

      assert retrieved.config.temperature == 0.9
      assert retrieved.config.max_tokens == 8000
    end

    test "returns error when table has sessions but ID not found" do
      SessionRegistry.create_table()

      # Register one session
      session1 = create_test_session(project_path: "/tmp/project1")
      {:ok, _} = SessionRegistry.register(session1)

      # Try to update a different session that was never registered
      session2 = create_test_session(project_path: "/tmp/project2")

      result = SessionRegistry.update(session2)

      assert result == {:error, :not_found}
    end

    test "can update immediately after registration" do
      SessionRegistry.create_table()

      session = create_test_session()
      {:ok, session} = SessionRegistry.register(session)

      # Immediately update
      updated = %{session | name: "immediate-update"}
      result = SessionRegistry.update(updated)

      assert {:ok, _} = result
      {:ok, retrieved} = SessionRegistry.lookup(session.id)
      assert retrieved.name == "immediate-update"
    end
  end
end
