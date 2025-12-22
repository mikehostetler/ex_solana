defmodule JidoCode.Session.ManagerTest do
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.Manager

  @registry JidoCode.SessionProcessRegistry

  setup do
    setup_session_registry("manager_test")
  end

  describe "start_link/1" do
    test "starts manager successfully", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} = Manager.start_link(session: session)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "registers in SessionProcessRegistry with :manager key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      # Should be findable via Registry with :manager key
      assert [{^pid, _}] = Registry.lookup(@registry, {:manager, session.id})

      # Cleanup
      GenServer.stop(pid)
    end

    test "requires :session option" do
      assert_raise KeyError, ~r/:session/, fn ->
        Manager.start_link([])
      end
    end

    test "fails for duplicate session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid1} = Manager.start_link(session: session)

      # Second start with same session should fail
      assert {:error, {:already_started, ^pid1}} = Manager.start_link(session: session)

      # Cleanup
      GenServer.stop(pid1)
    end

    test "initializes state with correct structure", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      # Access state via sys to verify structure
      state = :sys.get_state(pid)

      assert is_map(state)
      assert Map.has_key?(state, :session_id)
      assert Map.has_key?(state, :project_root)
      assert Map.has_key?(state, :lua_state)

      assert state.session_id == session.id
      assert state.project_root == tmp_dir

      # Cleanup
      GenServer.stop(pid)
    end

    test "initializes Lua sandbox with bridge functions", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      # Access state via sys to verify Lua state
      state = :sys.get_state(pid)

      # Lua state should be initialized (not nil)
      assert state.lua_state != nil

      # Verify jido namespace exists by executing Lua code
      # The jido table should be accessible
      lua_state = state.lua_state
      {:ok, result, _new_state} = :luerl.do("return type(jido)", lua_state)
      assert result == ["table"]

      # Cleanup
      GenServer.stop(pid)
    end

    test "Lua sandbox has bridge functions registered", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      state = :sys.get_state(pid)
      lua_state = state.lua_state

      # Check that bridge functions exist
      {:ok, [read_file_type], _} = :luerl.do("return type(jido.read_file)", lua_state)
      {:ok, [write_file_type], _} = :luerl.do("return type(jido.write_file)", lua_state)
      {:ok, [list_dir_type], _} = :luerl.do("return type(jido.list_dir)", lua_state)
      {:ok, [shell_type], _} = :luerl.do("return type(jido.shell)", lua_state)

      assert read_file_type == "function"
      assert write_file_type == "function"
      assert list_dir_type == "function"
      assert shell_type == "function"

      # Cleanup
      GenServer.stop(pid)
    end

    test "Lua sandbox can execute bridge functions", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Create a test file
      test_file = Path.join(tmp_dir, "test.txt")
      File.write!(test_file, "hello world")

      {:ok, pid} = Manager.start_link(session: session)

      state = :sys.get_state(pid)
      lua_state = state.lua_state

      # Read the file through the Lua bridge
      {:ok, [content], _} = :luerl.do("return jido.read_file('test.txt')", lua_state)

      assert content == "hello world"

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "child_spec/1" do
    test "returns correct specification", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      spec = Manager.child_spec(session: session)

      assert spec.id == {:session_manager, session.id}
      assert spec.start == {Manager, :start_link, [[session: session]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end

  describe "project_root/1" do
    test "returns the project root path", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} = Manager.start_link(session: session)

      assert {:ok, path} = Manager.project_root(session.id)
      assert path == tmp_dir
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Manager.project_root("non_existent_session")
    end
  end

  describe "session_id/1" do
    test "returns the session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} = Manager.start_link(session: session)

      assert {:ok, id} = Manager.session_id(session.id)
      assert id == session.id
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Manager.session_id("non_existent_session")
    end
  end

  describe "get_session/1" do
    test "returns the session struct (backwards compatibility)", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      assert {:ok, returned_session} = Manager.get_session(pid)
      assert returned_session.id == session.id
      assert returned_session.project_path == session.project_path

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "validate_path/2" do
    test "validates relative path within boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:ok, resolved} = Manager.validate_path(session.id, "src/file.ex")
      assert resolved == Path.join(tmp_dir, "src/file.ex")
    end

    test "validates absolute path within boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      absolute_path = Path.join(tmp_dir, "src/file.ex")
      assert {:ok, ^absolute_path} = Manager.validate_path(session.id, absolute_path)
    end

    test "rejects path traversal attack", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :path_escapes_boundary} =
               Manager.validate_path(session.id, "../../../etc/passwd")
    end

    test "rejects absolute path outside boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :path_outside_boundary} =
               Manager.validate_path(session.id, "/etc/passwd")
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Manager.validate_path("non_existent_session", "file.ex")
    end
  end

  describe "read_file/2" do
    test "reads file within boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      # Create a test file
      test_file = Path.join(tmp_dir, "test_read.txt")
      File.write!(test_file, "hello world")

      assert {:ok, "hello world"} = Manager.read_file(session.id, "test_read.txt")
    end

    test "rejects path outside boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :path_outside_boundary} = Manager.read_file(session.id, "/etc/passwd")
    end

    test "returns error for non-existent file", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :enoent} = Manager.read_file(session.id, "nonexistent.txt")
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Manager.read_file("non_existent_session", "file.ex")
    end
  end

  describe "write_file/3" do
    test "writes file within boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert :ok = Manager.write_file(session.id, "test_write.txt", "new content")

      # Verify file was written
      assert File.read!(Path.join(tmp_dir, "test_write.txt")) == "new content"
    end

    test "creates parent directories", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert :ok = Manager.write_file(session.id, "subdir/nested/file.txt", "nested content")

      # Verify file was written
      assert File.read!(Path.join(tmp_dir, "subdir/nested/file.txt")) == "nested content"
    end

    test "rejects path outside boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :path_outside_boundary} =
               Manager.write_file(session.id, "/etc/passwd", "malicious")
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} =
               Manager.write_file("non_existent_session", "file.ex", "content")
    end
  end

  describe "list_dir/2" do
    test "lists directory within boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      # Create some files
      File.write!(Path.join(tmp_dir, "file1.txt"), "")
      File.write!(Path.join(tmp_dir, "file2.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      {:ok, entries} = Manager.list_dir(session.id, ".")
      assert "file1.txt" in entries
      assert "file2.txt" in entries
      assert "subdir" in entries
    end

    test "rejects path outside boundary", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :path_outside_boundary} = Manager.list_dir(session.id, "/etc")
    end

    test "returns error for non-existent directory", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, :enoent} = Manager.list_dir(session.id, "nonexistent_dir")
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Manager.list_dir("non_existent_session", ".")
    end
  end

  describe "run_lua/2" do
    test "executes simple Lua expressions", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:ok, [42]} = Manager.run_lua(session.id, "return 21 + 21")
      assert {:ok, ["hello"]} = Manager.run_lua(session.id, "return 'hello'")
    end

    test "Lua state persists between calls", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      # Set a variable
      assert {:ok, []} = Manager.run_lua(session.id, "my_var = 123")

      # Read it back
      assert {:ok, [123]} = Manager.run_lua(session.id, "return my_var")
    end

    test "can access bridge functions", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Create a test file
      test_file = Path.join(tmp_dir, "lua_test.txt")
      File.write!(test_file, "content from file")

      {:ok, _pid} = Manager.start_link(session: session)

      assert {:ok, ["content from file"]} =
               Manager.run_lua(session.id, "return jido.read_file('lua_test.txt')")
    end

    test "handles Lua syntax errors", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, _reason} = Manager.run_lua(session.id, "this is not valid lua !!!")
    end

    test "handles Lua runtime errors", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = Manager.start_link(session: session)

      assert {:error, _reason} = Manager.run_lua(session.id, "error('intentional error')")
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Manager.run_lua("non_existent_session", "return 1")
    end
  end
end
