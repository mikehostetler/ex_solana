defmodule JidoCode.Tools.ManagerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias JidoCode.Session
  alias JidoCode.Tools.Manager

  # Most tests use a separate test instance, but some tests need to use the global Manager
  # that's started by the application supervision tree.

  setup do
    # Ensure application is started (Manager is in supervision tree)
    Application.ensure_all_started(:jido_code)

    # Suppress deprecation warnings for most tests
    Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

    on_exit(fn ->
      Application.delete_env(:jido_code, :suppress_global_manager_warnings)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts with default project root (cwd)" do
      # Start a separate test manager with a different name
      {:ok, pid} = Manager.start_link(name: :test_manager_default)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, root} = GenServer.call(:test_manager_default, :project_root)
      assert root == File.cwd!()
    end

    test "starts with custom project root" do
      # Start a test manager with custom project root
      {:ok, pid} =
        Manager.start_link(name: :test_manager_custom_root, project_root: System.tmp_dir!())

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, path} = GenServer.call(:test_manager_custom_root, :project_root)
      assert path == System.tmp_dir!()
    end

    test "starts with custom name" do
      {:ok, pid} = Manager.start_link(name: :custom_manager, project_root: "/tmp")

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      assert Process.alive?(pid)
      {:ok, root} = GenServer.call(:custom_manager, :project_root)
      assert root == "/tmp"
    end
  end

  describe "project_root/0" do
    test "returns the configured project root" do
      # Uses the global manager
      assert {:ok, path} = Manager.project_root()
      assert is_binary(path)
    end
  end

  describe "execute/3 - basic execution" do
    test "executes simple Lua expressions" do
      {:ok, result} = Manager.execute("return 42")
      assert result == 42 or result == 42.0
    end

    test "executes string operations" do
      assert {:ok, "hello"} = Manager.execute("return 'hello'")
    end

    test "executes arithmetic" do
      {:ok, result} = Manager.execute("return 10 + 5")
      assert result == 15 or result == 15.0
    end

    test "executes boolean expressions" do
      assert {:ok, true} = Manager.execute("return true")
      assert {:ok, false} = Manager.execute("return false")
    end

    test "returns nil for no return value" do
      assert {:ok, nil} = Manager.execute("local x = 1")
    end

    test "returns multiple values as list" do
      {:ok, result} = Manager.execute("return 1, 2, 3")
      assert result == [1, 2, 3] or result == [1.0, 2.0, 3.0]
    end
  end

  describe "execute/3 - with arguments" do
    test "accesses args table" do
      assert {:ok, "hello"} = Manager.execute("return args.name", %{"name" => "hello"})
    end

    test "uses numeric args" do
      {:ok, result} = Manager.execute("return args.x + args.y", %{"x" => 10, "y" => 20})
      assert result == 30 or result == 30.0
    end

    test "handles empty args" do
      {:ok, result} = Manager.execute("return 1", %{})
      assert result == 1 or result == 1.0
    end

    test "handles nested args" do
      args = %{"user" => %{"name" => "alice", "age" => 30}}
      assert {:ok, "alice"} = Manager.execute("return args.user.name", args)
    end

    test "handles array args" do
      args = %{"items" => [1, 2, 3]}
      {:ok, result} = Manager.execute("return args.items[1]", args)
      assert result == 1 or result == 1.0
    end
  end

  describe "execute/3 - table results" do
    test "returns Lua table as map" do
      {:ok, result} = Manager.execute("return {name = 'test', value = 42}")
      assert result["name"] == "test"
      assert result["value"] == 42 or result["value"] == 42.0
    end

    test "returns Lua array as list" do
      {:ok, result} = Manager.execute("return {1, 2, 3}")
      assert result == [1, 2, 3] or result == [1.0, 2.0, 3.0]
    end

    test "returns nested tables" do
      {:ok, result} = Manager.execute("return {outer = {inner = 'value'}}")
      assert result["outer"]["inner"] == "value"
    end
  end

  describe "execute/3 - error handling" do
    test "returns error for syntax errors" do
      assert {:error, _reason} = Manager.execute("return {")
    end

    test "returns error for runtime errors" do
      assert {:error, reason} = Manager.execute("error('test error')")
      assert reason =~ "test error"
    end

    test "returns error for undefined variable access" do
      assert {:error, _reason} = Manager.execute("return undefined_var.field")
    end
  end

  describe "sandbox restrictions" do
    test "os.execute is blocked" do
      assert {:error, reason} = Manager.execute("return os.execute('echo hello')")
      assert reason =~ "nil" or reason =~ "attempt to call"
    end

    test "os.exit is blocked" do
      assert {:error, reason} = Manager.execute("os.exit(1)")
      assert reason =~ "nil" or reason =~ "attempt to call"
    end

    test "io.popen is blocked" do
      assert {:error, reason} = Manager.execute("return io.popen('ls')")
      assert reason =~ "nil" or reason =~ "attempt to call"
    end

    test "loadfile is blocked" do
      assert {:error, reason} = Manager.execute("return loadfile('/etc/passwd')")
      assert reason =~ "nil" or reason =~ "attempt to call"
    end

    test "dofile is blocked" do
      assert {:error, reason} = Manager.execute("dofile('/etc/passwd')")
      assert reason =~ "nil" or reason =~ "attempt to call"
    end

    test "require is blocked" do
      assert {:error, reason} = Manager.execute("return require('os')")
      assert reason =~ "nil" or reason =~ "attempt to call"
    end

    test "package is blocked" do
      assert {:error, reason} = Manager.execute("return package.path")
      assert reason =~ "nil" or reason =~ "attempt to index"
    end

    test "basic os functions still work" do
      # os.time should still be available
      assert {:ok, result} = Manager.execute("return os.time()")
      assert is_number(result)
    end

    test "basic string functions work" do
      assert {:ok, "HELLO"} = Manager.execute("return string.upper('hello')")
    end

    test "basic math functions work" do
      assert {:ok, 4.0} = Manager.execute("return math.sqrt(16)")
    end

    test "basic table functions work" do
      {:ok, result} = Manager.execute("local t = {1,2,3}; return #t")
      assert result == 3 or result == 3.0
    end
  end

  describe "restricted?/1" do
    test "returns true for restricted functions" do
      assert Manager.restricted?([:os, :execute])
      assert Manager.restricted?([:os, :exit])
      assert Manager.restricted?([:io, :popen])
      assert Manager.restricted?([:loadfile])
      assert Manager.restricted?([:dofile])
      assert Manager.restricted?([:package])
      assert Manager.restricted?([:require])
    end

    test "returns false for allowed functions" do
      refute Manager.restricted?([:os, :time])
      refute Manager.restricted?([:string, :upper])
      refute Manager.restricted?([:math, :sqrt])
      refute Manager.restricted?([:print])
    end
  end

  describe "execution isolation" do
    test "global state does not persist between calls" do
      # Set a global in first call
      assert {:ok, nil} = Manager.execute("test_global = 123")

      # Global state is isolated - each call gets fresh state (args only, not persisted globals)
      # This is because we don't update the GenServer state with the modified Lua state
      assert {:ok, nil} = Manager.execute("return test_global")
    end

    test "args are fresh each call" do
      assert {:ok, "first"} = Manager.execute("return args.value", %{"value" => "first"})
      assert {:ok, "second"} = Manager.execute("return args.value", %{"value" => "second"})
    end
  end

  describe "validate_path/2" do
    test "accepts valid relative path" do
      {:ok, project_root} = Manager.project_root()
      {:ok, resolved} = Manager.validate_path("src/file.ex", log_violations: false)
      assert String.starts_with?(resolved, project_root)
    end

    test "rejects path traversal" do
      assert {:error, :path_escapes_boundary} =
               Manager.validate_path("../../../etc/passwd", log_violations: false)
    end

    test "rejects absolute path outside project" do
      assert {:error, :path_outside_boundary} =
               Manager.validate_path("/etc/passwd", log_violations: false)
    end

    test "uses project root from Manager state" do
      {:ok, project_root} = Manager.project_root()
      {:ok, resolved} = Manager.validate_path("test.txt", log_violations: false)
      assert resolved == Path.join(project_root, "test.txt")
    end
  end

  # ============================================================================
  # Session-Aware Compatibility Layer Tests
  # ============================================================================

  describe "session-aware compatibility layer" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Create a session with a manager for testing
      {:ok, session} = Session.new(project_path: tmp_dir, name: "test-session")

      {:ok, supervisor_pid} =
        Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:test_supervisor, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session, tmp_dir: tmp_dir}
    end

    test "project_root/1 delegates to Session.Manager when session_id provided", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      {:ok, path} = Manager.project_root(session_id: session.id)
      assert path == tmp_dir
    end

    test "project_root/1 uses global manager when no session_id", %{tmp_dir: _tmp_dir} do
      {:ok, path} = Manager.project_root()
      # Global manager returns its own project root (not the session's)
      assert is_binary(path)
    end

    test "project_root/1 returns error for unknown session_id" do
      assert {:error, :not_found} = Manager.project_root(session_id: "non_existent_session")
    end

    test "validate_path/2 delegates to Session.Manager when session_id provided", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      {:ok, resolved} = Manager.validate_path("test.txt", session_id: session.id)
      assert resolved == Path.join(tmp_dir, "test.txt")
    end

    test "validate_path/2 uses global manager when no session_id" do
      {:ok, project_root} = Manager.project_root()
      {:ok, resolved} = Manager.validate_path("test.txt", log_violations: false)
      assert resolved == Path.join(project_root, "test.txt")
    end

    test "validate_path/2 returns error for unknown session_id" do
      assert {:error, :not_found} = Manager.validate_path("test.txt", session_id: "non_existent")
    end

    test "read_file/2 delegates to Session.Manager when session_id provided", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      # Create a test file
      test_file = Path.join(tmp_dir, "test_read.txt")
      File.write!(test_file, "test content")

      {:ok, content} = Manager.read_file("test_read.txt", session_id: session.id)
      # Now returns line-numbered content via Lua bridge
      assert content == "     1→test content"
    end

    test "read_file/2 returns error for unknown session_id" do
      assert {:error, :not_found} = Manager.read_file("test.txt", session_id: "non_existent")
    end

    test "read_file/2 with offset option skips initial lines", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      # Create a multi-line file
      test_file = Path.join(tmp_dir, "multiline.txt")
      File.write!(test_file, "line1\nline2\nline3\nline4\nline5")

      {:ok, content} = Manager.read_file("multiline.txt", session_id: session.id, offset: 3)
      # Should start from line 3
      assert content =~ "3→line3"
      assert content =~ "4→line4"
      assert content =~ "5→line5"
      refute content =~ "1→line1"
      refute content =~ "2→line2"
    end

    test "read_file/2 with limit option caps output lines", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      # Create a multi-line file
      test_file = Path.join(tmp_dir, "multiline_limit.txt")
      File.write!(test_file, "line1\nline2\nline3\nline4\nline5")

      {:ok, content} = Manager.read_file("multiline_limit.txt", session_id: session.id, limit: 2)
      # Should only return first 2 lines
      assert content =~ "1→line1"
      assert content =~ "2→line2"
      refute content =~ "3→line3"
    end

    test "read_file/2 with offset and limit options combined", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      # Create a multi-line file
      test_file = Path.join(tmp_dir, "offset_limit.txt")
      File.write!(test_file, "a\nb\nc\nd\ne\nf\ng")

      {:ok, content} =
        Manager.read_file("offset_limit.txt", session_id: session.id, offset: 3, limit: 2)

      # Should return lines 3 and 4 only
      assert content =~ "3→c"
      assert content =~ "4→d"
      refute content =~ "1→a"
      refute content =~ "5→e"
    end

    test "write_file/3 delegates to Session.Manager when session_id provided", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      :ok = Manager.write_file("test_write.txt", "written content", session_id: session.id)

      # Verify the file was written
      test_file = Path.join(tmp_dir, "test_write.txt")
      assert File.read!(test_file) == "written content"
    end

    test "write_file/3 returns error for unknown session_id" do
      assert {:error, :not_found} =
               Manager.write_file("test.txt", "content", session_id: "non_existent")
    end

    test "list_dir/2 delegates to Session.Manager when session_id provided", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      # Create a test subdirectory with files
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "file1.txt"), "")
      File.write!(Path.join(subdir, "file2.txt"), "")

      {:ok, entries} = Manager.list_dir("subdir", session_id: session.id)
      assert Enum.sort(entries) == ["file1.txt", "file2.txt"]
    end

    test "list_dir/2 returns error for unknown session_id" do
      assert {:error, :not_found} = Manager.list_dir(".", session_id: "non_existent")
    end
  end

  describe "deprecation warnings" do
    test "logs warning when using global manager without session_id" do
      # Temporarily enable warnings
      Application.put_env(:jido_code, :suppress_global_manager_warnings, false)

      log =
        capture_log(fn ->
          Manager.project_root()
        end)

      assert log =~ "Global manager usage is deprecated"
      assert log =~ "session_id"
    end

    test "suppresses warning when configured" do
      Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

      log =
        capture_log(fn ->
          Manager.project_root()
        end)

      refute log =~ "Global manager usage is deprecated"
    end

    test "does not log warning when session_id provided", %{} do
      # Need a session for this test
      tmp_dir = System.tmp_dir!()
      {:ok, session} = Session.new(project_path: tmp_dir, name: "warning-test")

      {:ok, supervisor_pid} =
        Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:warning_test, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      # Enable warnings
      Application.put_env(:jido_code, :suppress_global_manager_warnings, false)

      log =
        capture_log(fn ->
          Manager.project_root(session_id: session.id)
        end)

      refute log =~ "Global manager usage is deprecated"
    end
  end
end
