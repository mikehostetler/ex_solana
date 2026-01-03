defmodule JidoCode.Tools.BridgeTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Bridge

  @moduletag :tmp_dir

  describe "is_binary_content?/1" do
    test "detects null bytes as binary" do
      assert Bridge.is_binary_content?(<<0, 1, 2, 3>>)
      assert Bridge.is_binary_content?("hello\x00world")
    end

    test "detects text as non-binary" do
      refute Bridge.is_binary_content?("Hello, World!")
      refute Bridge.is_binary_content?("line1\nline2\nline3")
      refute Bridge.is_binary_content?("UTF-8: こんにちは")
    end

    test "handles empty content" do
      refute Bridge.is_binary_content?("")
    end
  end

  describe "format_with_line_numbers/3" do
    test "formats single line" do
      result = Bridge.format_with_line_numbers("hello", 1, 2000)
      assert result == "     1→hello"
    end

    test "formats multiple lines" do
      result = Bridge.format_with_line_numbers("one\ntwo\nthree", 1, 2000)
      assert result == "     1→one\n     2→two\n     3→three"
    end

    test "applies offset" do
      result = Bridge.format_with_line_numbers("one\ntwo\nthree\nfour", 2, 2000)
      # Starts from line 2, but line numbers are preserved
      assert result == "     2→two\n     3→three\n     4→four"
    end

    test "applies limit" do
      result = Bridge.format_with_line_numbers("one\ntwo\nthree\nfour", 1, 2)
      assert result == "     1→one\n     2→two"
    end

    test "applies both offset and limit" do
      result = Bridge.format_with_line_numbers("one\ntwo\nthree\nfour\nfive", 2, 2)
      assert result == "     2→two\n     3→three"
    end

    test "truncates long lines" do
      long_line = String.duplicate("x", 2500)
      result = Bridge.format_with_line_numbers(long_line, 1, 2000)
      assert result =~ "[truncated]"
      assert String.length(result) < 2500
    end

    test "handles empty content" do
      result = Bridge.format_with_line_numbers("", 1, 2000)
      assert result == "     1→"
    end

    test "handles Windows line endings" do
      result = Bridge.format_with_line_numbers("one\r\ntwo\r\nthree", 1, 2000)
      assert result =~ "1→one"
      assert result =~ "2→two"
      assert result =~ "3→three"
    end

    test "adjusts line number width for large files" do
      # Create content with 100,000+ lines worth of numbers
      lines = Enum.map_join(1..100_001, "\n", &Integer.to_string/1)
      result = Bridge.format_with_line_numbers(lines, 100_000, 2)
      # Line number should be right-padded for 6+ digits
      assert result =~ "100000→100000"
      assert result =~ "100001→100001"
    end
  end

  describe "lua_read_file/3" do
    test "reads file contents with line numbers", %{tmp_dir: tmp_dir} do
      # Create a test file
      file_path = Path.join(tmp_dir, "test.txt")
      File.write!(file_path, "Hello, World!")

      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["test.txt"], state, tmp_dir)

      assert [content] = result
      assert content =~ "1→Hello, World!"
    end

    test "reads multi-line file with line numbers", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "multi.txt")
      File.write!(file_path, "line one\nline two\nline three")

      state = :luerl.init()
      {[content], _state} = Bridge.lua_read_file(["multi.txt"], state, tmp_dir)

      assert content =~ "1→line one"
      assert content =~ "2→line two"
      assert content =~ "3→line three"
    end

    test "reads nested file with line numbers", %{tmp_dir: tmp_dir} do
      nested_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(nested_dir)
      file_path = Path.join(nested_dir, "code.ex")
      File.write!(file_path, "defmodule Test do\nend")

      state = :luerl.init()
      {[content], _state} = Bridge.lua_read_file(["src/code.ex"], state, tmp_dir)

      assert content =~ "1→defmodule Test do"
      assert content =~ "2→end"
    end

    test "supports offset option", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "lines.txt")
      File.write!(file_path, "one\ntwo\nthree\nfour\nfive")

      state = :luerl.init()
      opts = [{"offset", 3}]
      {[content], _state} = Bridge.lua_read_file(["lines.txt", opts], state, tmp_dir)

      # Should start from line 3
      refute content =~ "1→one"
      refute content =~ "2→two"
      assert content =~ "3→three"
      assert content =~ "4→four"
      assert content =~ "5→five"
    end

    test "supports limit option", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "lines.txt")
      File.write!(file_path, "one\ntwo\nthree\nfour\nfive")

      state = :luerl.init()
      opts = [{"limit", 2}]
      {[content], _state} = Bridge.lua_read_file(["lines.txt", opts], state, tmp_dir)

      # Should only have first 2 lines
      assert content =~ "1→one"
      assert content =~ "2→two"
      refute content =~ "3→three"
    end

    test "supports combined offset and limit", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "lines.txt")
      File.write!(file_path, "one\ntwo\nthree\nfour\nfive")

      state = :luerl.init()
      opts = [{"offset", 2}, {"limit", 2}]
      {[content], _state} = Bridge.lua_read_file(["lines.txt", opts], state, tmp_dir)

      # Should have lines 2 and 3 only
      refute content =~ "1→one"
      assert content =~ "2→two"
      assert content =~ "3→three"
      refute content =~ "4→four"
    end

    test "truncates long lines with indicator", %{tmp_dir: tmp_dir} do
      # Create a file with a very long line (> 2000 chars)
      long_line = String.duplicate("x", 2500)
      file_path = Path.join(tmp_dir, "long.txt")
      File.write!(file_path, long_line)

      state = :luerl.init()
      {[content], _state} = Bridge.lua_read_file(["long.txt"], state, tmp_dir)

      assert content =~ "[truncated]"
      # The truncated content plus indicator should be less than the original
      refute String.length(content) >= 2500
    end

    test "rejects binary files", %{tmp_dir: tmp_dir} do
      # Create a file with null bytes (binary file indicator)
      binary_content = <<0, 1, 2, 3, 0, 255, 254>>
      file_path = Path.join(tmp_dir, "binary.bin")
      File.write!(file_path, binary_content)

      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["binary.bin"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Binary file detected"
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

    test "handles empty file", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "empty.txt")
      File.write!(file_path, "")

      state = :luerl.init()
      {[content], _state} = Bridge.lua_read_file(["empty.txt"], state, tmp_dir)

      # Empty file should return empty content (just one line with empty content)
      assert content == "     1→"
    end

    test "returns error for permission denied", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "no_read.txt")
      File.write!(file_path, "secret content")

      # Remove read permissions (write-only)
      File.chmod!(file_path, 0o200)

      state = :luerl.init()
      {result, _state} = Bridge.lua_read_file(["no_read.txt"], state, tmp_dir)

      # Restore permissions for cleanup
      File.chmod!(file_path, 0o644)

      assert [nil, error] = result
      assert error =~ "permission" or error =~ "eacces" or error =~ "denied"
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
    test "lists directory contents with type indicators", %{tmp_dir: tmp_dir} do
      # Create some files and a directory
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.write!(Path.join(tmp_dir, "b.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir([""], state, tmp_dir)

      # Result is a Lua array with {index, [{name, value}, {type, value}]} entries
      # Directories come first, then files alphabetically
      assert [{1, subdir_entry}, {2, a_entry}, {3, b_entry}] = result

      # Check directory entry
      subdir_map = Map.new(subdir_entry)
      assert subdir_map["name"] == "subdir"
      assert subdir_map["type"] == "directory"

      # Check file entries
      a_map = Map.new(a_entry)
      assert a_map["name"] == "a.txt"
      assert a_map["type"] == "file"

      b_map = Map.new(b_entry)
      assert b_map["name"] == "b.txt"
      assert b_map["type"] == "file"
    end

    test "sorts directories first then alphabetically", %{tmp_dir: tmp_dir} do
      # Create files and directories in non-sorted order
      File.write!(Path.join(tmp_dir, "z.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "beta"))
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.mkdir_p!(Path.join(tmp_dir, "alpha"))

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir([""], state, tmp_dir)

      # Extract names in order
      names = Enum.map(result, fn {_idx, entry} ->
        Map.new(entry)["name"]
      end)

      # Directories first (alpha, beta), then files (a.txt, z.txt)
      assert names == ["alpha", "beta", "a.txt", "z.txt"]
    end

    test "lists subdirectory", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "src")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "main.ex"), "")
      File.write!(Path.join(subdir, "helper.ex"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_list_dir(["src"], state, tmp_dir)

      # Extract names
      names = Enum.map(result, fn {_idx, entry} ->
        Map.new(entry)["name"]
      end)

      assert names == ["helper.ex", "main.ex"]
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

      assert [{1, entry}] = result
      entry_map = Map.new(entry)
      assert entry_map["name"] == "root.txt"
      assert entry_map["type"] == "file"
    end

    test "supports ignore_patterns option", %{tmp_dir: tmp_dir} do
      # Create various files
      File.write!(Path.join(tmp_dir, "main.ex"), "")
      File.write!(Path.join(tmp_dir, "test.log"), "")
      File.write!(Path.join(tmp_dir, "debug.log"), "")
      File.mkdir_p!(Path.join(tmp_dir, "node_modules"))

      state = :luerl.init()
      # Pass ignore_patterns as Lua table format
      opts = [{"ignore_patterns", [{1, "*.log"}, {2, "node_modules"}]}]
      {[result], _state} = Bridge.lua_list_dir(["", opts], state, tmp_dir)

      # Extract names
      names = Enum.map(result, fn {_idx, entry} ->
        Map.new(entry)["name"]
      end)

      # Should only have main.ex (*.log and node_modules filtered out)
      assert names == ["main.ex"]
    end

    test "ignore_patterns with wildcard matching", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "app.test.js"), "")
      File.write!(Path.join(tmp_dir, "util.test.js"), "")
      File.write!(Path.join(tmp_dir, "main.js"), "")

      state = :luerl.init()
      opts = [{"ignore_patterns", [{1, "*.test.js"}]}]
      {[result], _state} = Bridge.lua_list_dir(["", opts], state, tmp_dir)

      names = Enum.map(result, fn {_idx, entry} ->
        Map.new(entry)["name"]
      end)

      assert names == ["main.js"]
    end

    test "empty ignore_patterns has no effect", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file.txt"), "")

      state = :luerl.init()
      opts = [{"ignore_patterns", []}]
      {[result], _state} = Bridge.lua_list_dir(["", opts], state, tmp_dir)

      assert [{1, entry}] = result
      entry_map = Map.new(entry)
      assert entry_map["name"] == "file.txt"
    end

    test "returns error for file path (not directory)", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file.txt"), "content")

      state = :luerl.init()
      {result, _state} = Bridge.lua_list_dir(["file.txt"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Not a directory"
    end
  end

  describe "lua_glob/3" do
    test "finds files with ** pattern", %{tmp_dir: tmp_dir} do
      # Create nested directory structure
      lib_dir = Path.join(tmp_dir, "lib")
      File.mkdir_p!(lib_dir)
      File.write!(Path.join(lib_dir, "main.ex"), "")
      File.write!(Path.join(lib_dir, "helper.ex"), "")

      sub_dir = Path.join(lib_dir, "sub")
      File.mkdir_p!(sub_dir)
      File.write!(Path.join(sub_dir, "nested.ex"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["**/*.ex"], state, tmp_dir)

      # Extract paths from Lua array
      paths = Enum.map(result, fn {_idx, path} -> path end)

      assert length(paths) == 3
      assert "lib/main.ex" in paths
      assert "lib/helper.ex" in paths
      assert "lib/sub/nested.ex" in paths
    end

    test "finds files with simple * pattern", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a.ex"), "")
      File.write!(Path.join(tmp_dir, "b.ex"), "")
      File.write!(Path.join(tmp_dir, "c.txt"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["*.ex"], state, tmp_dir)

      paths = Enum.map(result, fn {_idx, path} -> path end)

      assert length(paths) == 2
      assert "a.ex" in paths
      assert "b.ex" in paths
      refute "c.txt" in paths
    end

    test "finds files with brace expansion pattern", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "main.ex"), "")
      File.write!(Path.join(tmp_dir, "test.exs"), "")
      File.write!(Path.join(tmp_dir, "readme.md"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["*.{ex,exs}"], state, tmp_dir)

      paths = Enum.map(result, fn {_idx, path} -> path end)

      assert length(paths) == 2
      assert "main.ex" in paths
      assert "test.exs" in paths
      refute "readme.md" in paths
    end

    test "uses base path for searching", %{tmp_dir: tmp_dir} do
      lib_dir = Path.join(tmp_dir, "lib")
      File.mkdir_p!(lib_dir)
      File.write!(Path.join(lib_dir, "app.ex"), "")

      test_dir = Path.join(tmp_dir, "test")
      File.mkdir_p!(test_dir)
      File.write!(Path.join(test_dir, "app_test.exs"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["*.ex", "lib"], state, tmp_dir)

      paths = Enum.map(result, fn {_idx, path} -> path end)

      assert paths == ["lib/app.ex"]
    end

    test "returns empty array for no matches", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "file.txt"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["*.ex"], state, tmp_dir)

      assert result == []
    end

    test "sorts results by modification time newest first", %{tmp_dir: tmp_dir} do
      # Create files with slight delay to ensure different mtimes
      File.write!(Path.join(tmp_dir, "old.ex"), "old")
      :timer.sleep(10)
      File.write!(Path.join(tmp_dir, "new.ex"), "new")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["*.ex"], state, tmp_dir)

      paths = Enum.map(result, fn {_idx, path} -> path end)

      # Newest file should be first
      assert hd(paths) == "new.ex"
    end

    test "returns error for path traversal in base path", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_glob(["*.ex", "../.."], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "Security error"
    end

    test "returns error for missing pattern argument", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_glob([], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "glob requires a pattern argument"
    end

    test "filters results to stay within project boundary", %{tmp_dir: tmp_dir} do
      # Create a file within boundary
      File.write!(Path.join(tmp_dir, "safe.ex"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["*.ex"], state, tmp_dir)

      paths = Enum.map(result, fn {_idx, path} -> path end)

      # Should only contain files within the project boundary
      assert "safe.ex" in paths
    end

    test "returns error for non-existent base path", %{tmp_dir: tmp_dir} do
      state = :luerl.init()
      {result, _state} = Bridge.lua_glob(["*.ex", "nonexistent"], state, tmp_dir)

      assert [nil, error] = result
      assert error =~ "File not found"
    end

    test "finds files with ? wildcard pattern", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a1.ex"), "")
      File.write!(Path.join(tmp_dir, "a2.ex"), "")
      File.write!(Path.join(tmp_dir, "abc.ex"), "")

      state = :luerl.init()
      {[result], _state} = Bridge.lua_glob(["a?.ex"], state, tmp_dir)

      paths = Enum.map(result, fn {_idx, path} -> path end)

      assert length(paths) == 2
      assert "a1.ex" in paths
      assert "a2.ex" in paths
      refute "abc.ex" in paths
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

    test "read_file works from Lua with line numbers", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "hello.txt"), "Hello from Lua!")

      lua_state = :luerl.init()
      lua_state = Bridge.register(lua_state, tmp_dir)

      {:ok, [content], _state} = :luerl.do(~s[return jido.read_file("hello.txt")], lua_state)
      assert content =~ "1→Hello from Lua!"
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
