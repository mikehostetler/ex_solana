defmodule JidoCode.Tools.BridgeTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Bridge

  @moduletag :tmp_dir

  describe "lua_read_file/3" do
    test "reads file contents", %{tmp_dir: tmp_dir} do
      # Create a test file
      file_path = Path.join(tmp_dir, "test.txt")
      File.write!(file_path, "Hello, World!")

      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["test.txt"], state, tmp_dir)

      assert result == ["Hello, World!"]
    end

    test "reads nested file", %{tmp_dir: tmp_dir} do
      nested_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(nested_dir)
      file_path = Path.join(nested_dir, "code.ex")
      File.write!(file_path, "defmodule Test do\nend")

      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["src/code.ex"], state, tmp_dir)

      assert result == ["defmodule Test do\nend"]
    end

    test "returns error for non-existent file", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["missing.txt"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "File not found"
    end

    test "returns error for path traversal attempt", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["../../../etc/passwd"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
    end

    test "returns error for missing argument", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file([], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "requires a path argument"
    end

    test "returns error for non-string path", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file([123], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "requires a path argument"
    end
  end

  describe "lua_write_file/3" do
    test "writes file contents", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_write_file(["output.txt", "Test content"], state, tmp_dir)

      assert result == [true]
      assert File.read!(Path.join(tmp_dir, "output.txt")) == "Test content"
    end

    test "creates parent directories", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_write_file(["a/b/c/file.txt", "Nested"], state, tmp_dir)

      assert result == [true]
      assert File.read!(Path.join(tmp_dir, "a/b/c/file.txt")) == "Nested"
    end

    test "overwrites existing file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "existing.txt")
      File.write!(file_path, "Old content")

      state = :luerl.init()
      {result, _state} = Bridge.lua_write_file(["existing.txt", "New content"], state, tmp_dir)

      assert result == [true]
      assert File.read!(file_path) == "New content"
    end

    test "returns error for path traversal attempt", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_write_file(["../evil.txt", "Bad"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
    end

    test "returns error for missing content", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_write_file(["file.txt"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "requires path and content"
    end

    test "returns error for non-string content", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_write_file(["file.txt", 123], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "content must be a string"
    end
  end

  describe "lua_list_dir/3" do
    test "lists directory contents", %{tmp_dir: tmp_dir} do
      # Create some files
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.write!(Path.join(tmp_dir, "b.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir([""], state, tmp_dir)

      # Result is a Lua array (list of {index, value} tuples)
      assert [{1, "a.txt"}, {2, "b.txt"}, {3, "subdir"}] = Enum.sort(result)
    end

    test "lists subdirectory", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "src")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "main.ex"), "")
      File.write!(Path.join(subdir, "helper.ex"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir(["src"], state, tmp_dir)

      assert [{1, "helper.ex"}, {2, "main.ex"}] = Enum.sort(result)
    end

    test "returns empty array for empty directory", %{tmp_dir: tmp_dir} do
      empty_dir = Path.join(tmp_dir, "empty")
      File.mkdir_p!(empty_dir)

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir(["empty"], state, tmp_dir)

      assert [] = result
    end

    test "returns error for non-existent directory", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_list_dir(["missing"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "File not found" or error =~ "Not a directory"
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_list_dir(["../.."], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
    end

    test "defaults to project root with no args", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "root.txt"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir([], state, tmp_dir)

      assert [{1, "root.txt"}] = result
    end
  end

  describe "lua_file_exists/3" do
    test "returns true for existing file", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "exists.txt"), "")

      state = :luerl.init()
      {result, _state} = Bridge.lua_file_exists(["exists.txt"], state, tmp_dir)

      assert result == [true]
    end

    test "returns true for existing directory", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      state = :luerl.init()
      {result, _state} = Bridge.lua_file_exists(["subdir"], state, tmp_dir)

      assert result == [true]
    end

    test "returns false for non-existent path", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_file_exists(["missing.txt"], state, tmp_dir)

      assert result == [false]
    end

    test "returns error for path traversal", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_file_exists(["../../../etc"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
    end

    test "returns error for missing argument", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_file_exists([], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "requires a path argument"
    end
  end

  describe "lua_shell/3" do
    test "executes simple allowed command", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["echo", [{1, "hello"}]], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
      assert String.trim(result_map["stdout"]) == "hello"
      assert result_map["stderr"] == ""
    end

    test "captures exit code", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["false"], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] != 0
    end

    test "runs in project directory", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["pwd"], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
      assert String.trim(result_map["stdout"]) == tmp_dir
    end

    test "command with no args", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["true"], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
      assert result_map["stdout"] == ""
      assert result_map["stderr"] == ""
    end

    test "returns error for missing command", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell([], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "requires a command"
    end

    test "returns error for command not in allowlist", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell(["nonexistent_command_xyz"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error" or error =~ "command not in allowlist"
    end

    # SEC-1: Shell interpreter blocking tests
    test "blocks bash shell interpreter", %{tmp_dir: tmp_dir} do
      state = :luerl.init()

      {result, _state} =
        Bridge.lua_shell(["bash", [{1, "-c"}, {2, "echo pwned"}]], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "shell interpreters are blocked"
    end

    test "blocks sh shell interpreter", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell(["sh", [{1, "-c"}, {2, "rm -rf /"}]], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "shell interpreters are blocked"
    end

    test "blocks zsh shell interpreter", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell(["zsh"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "shell interpreters are blocked"
    end

    test "blocks fish shell interpreter", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell(["fish"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "shell interpreters are blocked"
    end

    # SEC-3: Path traversal blocking tests
    test "blocks path traversal in arguments", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell(["cat", [{1, "../../../etc/passwd"}]], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "path traversal"
    end

    test "blocks absolute paths outside project", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_shell(["cat", [{1, "/etc/passwd"}]], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "absolute paths outside project"
    end

    test "allows safe system paths like /dev/null", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["cat", [{1, "/dev/null"}]], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
    end

    test "allows absolute paths within project", %{tmp_dir: tmp_dir} do
      # Create a file in the project directory
      test_file = Path.join(tmp_dir, "test.txt")
      File.write!(test_file, "Hello")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["cat", [{1, test_file}]], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
      assert String.trim(result_map["stdout"]) == "Hello"
    end

    test "allows relative paths within project", %{tmp_dir: tmp_dir} do
      # Create a file in the project directory
      File.write!(Path.join(tmp_dir, "safe.txt"), "Safe content")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["cat", [{1, "safe.txt"}]], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
      assert String.trim(result_map["stdout"]) == "Safe content"
    end

    test "blocks multiple path traversal patterns", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      # Try hidden traversal with multiple levels
      {result, _state} = Bridge.lua_shell(["ls", [{1, "foo/../../bar"}]], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
      assert error =~ "path traversal"
    end

    # Test that allowed commands work
    test "allows mix command", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      # mix --version should work
      {[result], _state} = Bridge.lua_shell(["mix", [{1, "--version"}]], state, tmp_dir)

      result_map = Map.new(result)

      # Should execute (even if mix isn't installed, it would be "command not found" not security error)
      assert is_integer(result_map["exit_code"])
    end

    test "allows git command", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["git", [{1, "--version"}]], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
    end

    test "allows ls command", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {[result], _state} = Bridge.lua_shell(["ls"], state, tmp_dir)

      result_map = Map.new(result)
      assert result_map["exit_code"] == 0
    end
  end

  describe "register/2" do
    test "registers all bridge functions in jido namespace", %{tmp_dir: tmp_dir} do
      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      # Verify functions are registered by checking they're callable
      {:ok, [result], _state} = :luerl.do(~s[return type(jido.read_file)], lua_state)
      assert result == "function"

      {:ok, [result], _state} = :luerl.do(~s[return type(jido.write_file)], lua_state)
      assert result == "function"

      {:ok, [result], _state} = :luerl.do(~s[return type(jido.list_dir)], lua_state)
      assert result == "function"

      {:ok, [result], _state} = :luerl.do(~s[return type(jido.file_exists)], lua_state)
      assert result == "function"

      {:ok, [result], _state} = :luerl.do(~s[return type(jido.shell)], lua_state)
      assert result == "function"
    end

    test "registered functions are callable from Lua", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test.txt"), "content")

      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      # Call jido.file_exists from Lua
      {:ok, result, _state} = :luerl.do(~s[return jido.file_exists("test.txt")], lua_state)
      assert result == [true]
    end

    test "read_file works from Lua", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "Hello from Lua!")

      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      {:ok, result, _state} = :luerl.do(~s[return jido.read_file("hello.txt")], lua_state)
      assert result == ["Hello from Lua!"]
    end

    test "write_file works from Lua", %{tmp_dir: tmp_dir} do
      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      {:ok, result, _state} =
        :luerl.do(~s[return jido.write_file("new.txt", "Created by Lua")], lua_state)

      assert result == [true]
      assert File.read!(Path.join(tmp_dir, "new.txt")) == "Created by Lua"
    end

    test "list_dir works from Lua", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.write!(Path.join(tmp_dir, "b.txt"), "")

      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      # list_dir returns a table - verify it returns without error
      # Note: Due to luerl state handling, returned tables from bridge functions
      # may not be directly iterable. Direct function tests verify content.
      {:ok, result, _state} = :luerl.do(~s[return jido.list_dir("")], lua_state)
      # The function returns a value (the table)
      assert length(result) == 1
    end

    test "shell works from Lua", %{tmp_dir: tmp_dir} do
      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      # shell returns a table - verify it returns without error
      # Note: Due to luerl state handling, returned tables from bridge functions
      # may not be directly accessible. Direct function tests verify content.
      {:ok, result, _state} = :luerl.do(~s[return jido.shell("true")], lua_state)
      # The function returns a value
      assert length(result) == 1
    end

    test "security errors propagate correctly", %{tmp_dir: tmp_dir} do
      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      {:ok, result, _state} =
        :luerl.do(
          ~s[local content, err = jido.read_file("../../../etc/passwd"); return content, err],
          lua_state
        )

      assert [nil, error] = result
      assert is_binary(error)
      assert error =~ "Security error"
    end
  end
end
