defmodule JidoCode.Tools.ManagerTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Manager

  # Most tests use a separate test instance, but some tests need to use the global Manager
  # that's started by the application supervision tree.

  setup do
    # For most tests, we use the global Manager started by the application
    # Only specific tests that need isolation will start their own instance
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
end
