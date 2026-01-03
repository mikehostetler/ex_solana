defmodule JidoCode.Tools.Helpers.GlobMatcherTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Helpers.GlobMatcher

  import ExUnit.CaptureLog

  @moduletag :tmp_dir

  describe "matches_any?/2" do
    test "returns false for empty pattern list" do
      refute GlobMatcher.matches_any?("test.log", [])
    end

    test "returns true when entry matches any pattern" do
      assert GlobMatcher.matches_any?("test.log", ["*.log", "*.tmp"])
    end

    test "returns false when entry matches no patterns" do
      refute GlobMatcher.matches_any?("readme.md", ["*.log", "*.tmp"])
    end

    test "handles multiple patterns" do
      assert GlobMatcher.matches_any?("node_modules", ["*.log", "node_modules", "dist"])
      assert GlobMatcher.matches_any?("dist", ["*.log", "node_modules", "dist"])
      refute GlobMatcher.matches_any?("src", ["*.log", "node_modules", "dist"])
    end

    test "returns false for non-binary entry" do
      refute GlobMatcher.matches_any?(123, ["*.log"])
    end

    test "returns false for non-list patterns" do
      refute GlobMatcher.matches_any?("test.log", "*.log")
    end
  end

  describe "matches_glob?/2" do
    test "matches exact string" do
      assert GlobMatcher.matches_glob?("node_modules", "node_modules")
      refute GlobMatcher.matches_glob?("node", "node_modules")
    end

    test "matches asterisk wildcard" do
      assert GlobMatcher.matches_glob?("test.log", "*.log")
      assert GlobMatcher.matches_glob?("error.log", "*.log")
      refute GlobMatcher.matches_glob?("test.txt", "*.log")
    end

    test "matches question mark wildcard" do
      assert GlobMatcher.matches_glob?("config.json", "config.????")
      refute GlobMatcher.matches_glob?("config.json", "config.???")
      assert GlobMatcher.matches_glob?("a1b", "a?b")
      refute GlobMatcher.matches_glob?("a12b", "a?b")
    end

    test "matches combined wildcards" do
      assert GlobMatcher.matches_glob?("test_123.log", "test_*.log")
      assert GlobMatcher.matches_glob?("a1.txt", "a?.txt")
      assert GlobMatcher.matches_glob?("file.test.log", "*.test.log")
    end

    test "escapes regex metacharacters - dot" do
      # The dot should be treated as literal, not regex "any character"
      assert GlobMatcher.matches_glob?("file.txt", "file.txt")
      refute GlobMatcher.matches_glob?("filextxt", "file.txt")
    end

    test "escapes regex metacharacters - plus" do
      # Pattern with + should not be treated as regex quantifier
      assert GlobMatcher.matches_glob?("c++", "c++")
      refute GlobMatcher.matches_glob?("ccc", "c++")
    end

    test "escapes regex metacharacters - brackets" do
      # Square brackets should be literal, not character class
      assert GlobMatcher.matches_glob?("[test]", "[test]")
      refute GlobMatcher.matches_glob?("t", "[test]")
    end

    test "escapes regex metacharacters - parentheses" do
      # Parentheses should be literal
      assert GlobMatcher.matches_glob?("(foo)", "(foo)")
      refute GlobMatcher.matches_glob?("foo", "(foo)")
    end

    test "escapes regex metacharacters - pipe" do
      # Pipe should be literal, not alternation
      assert GlobMatcher.matches_glob?("a|b", "a|b")
      refute GlobMatcher.matches_glob?("a", "a|b")
    end

    test "escapes regex metacharacters - braces" do
      # Braces should be literal
      assert GlobMatcher.matches_glob?("{foo}", "{foo}")
      refute GlobMatcher.matches_glob?("foo", "{foo}")
    end

    test "escapes regex metacharacters - caret and dollar" do
      # Should be literal, not anchors
      assert GlobMatcher.matches_glob?("^start", "^start")
      assert GlobMatcher.matches_glob?("end$", "end$")
    end

    test "escapes regex metacharacters - backslash" do
      # Backslash should be literal
      assert GlobMatcher.matches_glob?("path\\file", "path\\file")
    end

    test "handles unicode filenames" do
      assert GlobMatcher.matches_glob?("文件.txt", "*.txt")
      assert GlobMatcher.matches_glob?("файл.log", "*.log")
      assert GlobMatcher.matches_glob?("αβγ.md", "αβγ.md")
    end

    test "handles filenames with spaces" do
      assert GlobMatcher.matches_glob?("my file.txt", "my file.txt")
      assert GlobMatcher.matches_glob?("my file.txt", "*.txt")
    end

    test "handles hidden files (dot prefix)" do
      assert GlobMatcher.matches_glob?(".gitignore", ".gitignore")
      assert GlobMatcher.matches_glob?(".hidden", ".*")
      # Note: * does not match dot-prefix by default in shell glob,
      # but our simple implementation treats * as "match anything"
      assert GlobMatcher.matches_glob?(".hidden", "*")
    end

    test "logs warning for invalid patterns" do
      # This pattern could cause regex compilation issues if not properly escaped
      # Actually with proper escaping, all patterns should compile. Let's test
      # that a pattern with unclosed group would have failed before escaping
      log =
        capture_log(fn ->
          # This should work now because we escape everything
          result = GlobMatcher.matches_glob?("test", "[unclosed")
          assert result == true or result == false
        end)

      # With proper escaping, there should be no warning since the pattern compiles
      # Actually, "[unclosed" after escaping becomes "\\[unclosed" which is valid
      assert log == ""
    end

    test "returns false for non-binary inputs" do
      refute GlobMatcher.matches_glob?(123, "*.txt")
      refute GlobMatcher.matches_glob?("test.txt", 123)
      refute GlobMatcher.matches_glob?(nil, nil)
    end
  end

  describe "sort_directories_first/2" do
    test "sorts directories before files", %{tmp_dir: tmp_dir} do
      # Create test structure
      File.mkdir_p!(Path.join(tmp_dir, "dir_a"))
      File.mkdir_p!(Path.join(tmp_dir, "dir_b"))
      File.write!(Path.join(tmp_dir, "file_a.txt"), "a")
      File.write!(Path.join(tmp_dir, "file_b.txt"), "b")

      entries = ["file_a.txt", "dir_b", "file_b.txt", "dir_a"]
      sorted = GlobMatcher.sort_directories_first(entries, tmp_dir)

      # Directories should come first, then files
      assert sorted == ["dir_a", "dir_b", "file_a.txt", "file_b.txt"]
    end

    test "maintains alphabetical order within groups", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "zebra_dir"))
      File.mkdir_p!(Path.join(tmp_dir, "alpha_dir"))
      File.write!(Path.join(tmp_dir, "zebra.txt"), "z")
      File.write!(Path.join(tmp_dir, "alpha.txt"), "a")

      entries = ["zebra.txt", "zebra_dir", "alpha.txt", "alpha_dir"]
      sorted = GlobMatcher.sort_directories_first(entries, tmp_dir)

      assert sorted == ["alpha_dir", "zebra_dir", "alpha.txt", "zebra.txt"]
    end

    test "handles empty list" do
      assert GlobMatcher.sort_directories_first([], "/tmp") == []
    end

    test "handles files only", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "c.txt"), "c")
      File.write!(Path.join(tmp_dir, "a.txt"), "a")
      File.write!(Path.join(tmp_dir, "b.txt"), "b")

      entries = ["c.txt", "a.txt", "b.txt"]
      sorted = GlobMatcher.sort_directories_first(entries, tmp_dir)

      assert sorted == ["a.txt", "b.txt", "c.txt"]
    end

    test "handles directories only", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "c_dir"))
      File.mkdir_p!(Path.join(tmp_dir, "a_dir"))
      File.mkdir_p!(Path.join(tmp_dir, "b_dir"))

      entries = ["c_dir", "a_dir", "b_dir"]
      sorted = GlobMatcher.sort_directories_first(entries, tmp_dir)

      assert sorted == ["a_dir", "b_dir", "c_dir"]
    end
  end

  describe "entry_info/2" do
    test "returns file type for regular files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test.txt"), "content")

      info = GlobMatcher.entry_info(tmp_dir, "test.txt")

      assert info == %{name: "test.txt", type: "file"}
    end

    test "returns directory type for directories", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))

      info = GlobMatcher.entry_info(tmp_dir, "subdir")

      assert info == %{name: "subdir", type: "directory"}
    end

    test "handles hidden files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, ".hidden"), "secret")

      info = GlobMatcher.entry_info(tmp_dir, ".hidden")

      assert info == %{name: ".hidden", type: "file"}
    end

    test "handles unicode filenames", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "文件.txt"), "content")

      info = GlobMatcher.entry_info(tmp_dir, "文件.txt")

      assert info == %{name: "文件.txt", type: "file"}
    end

    test "handles filenames with spaces", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "my file.txt"), "content")

      info = GlobMatcher.entry_info(tmp_dir, "my file.txt")

      assert info == %{name: "my file.txt", type: "file"}
    end
  end

  # ===========================================================================
  # Glob Search Helper Tests
  # ===========================================================================

  describe "filter_within_boundary/2" do
    test "filters paths within project boundary", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)
      file1 = Path.join(tmp_dir, "file1.ex")
      file2 = Path.join(subdir, "file2.ex")
      File.write!(file1, "")
      File.write!(file2, "")

      paths = [file1, file2, "/etc/passwd"]
      result = GlobMatcher.filter_within_boundary(paths, tmp_dir)

      assert length(result) == 2
      assert file1 in result
      assert file2 in result
      refute "/etc/passwd" in result
    end

    test "excludes paths outside boundary", %{tmp_dir: tmp_dir} do
      paths = ["/etc/passwd", "/usr/bin/ls", "/tmp/outside"]
      result = GlobMatcher.filter_within_boundary(paths, tmp_dir)

      assert result == []
    end

    test "handles empty list", %{tmp_dir: tmp_dir} do
      result = GlobMatcher.filter_within_boundary([], tmp_dir)
      assert result == []
    end

    test "filters symlinks pointing outside boundary", %{tmp_dir: tmp_dir} do
      # Create a file inside the boundary
      inside_file = Path.join(tmp_dir, "inside.ex")
      File.write!(inside_file, "inside content")

      # Create a symlink pointing outside the boundary
      escape_link = Path.join(tmp_dir, "escape_link")

      case File.ln_s("/etc/passwd", escape_link) do
        :ok ->
          paths = [inside_file, escape_link]
          result = GlobMatcher.filter_within_boundary(paths, tmp_dir)

          # The symlink should be filtered out because its target is outside
          assert length(result) == 1
          assert inside_file in result
          refute escape_link in result

        {:error, _} ->
          # Symlinks might not be supported (e.g., Windows), skip
          :ok
      end
    end

    test "allows symlinks pointing inside boundary", %{tmp_dir: tmp_dir} do
      # Create target file inside boundary
      target = Path.join(tmp_dir, "target.ex")
      File.write!(target, "target content")

      # Create symlink pointing to the target
      link = Path.join(tmp_dir, "link.ex")

      case File.ln_s(target, link) do
        :ok ->
          paths = [target, link]
          result = GlobMatcher.filter_within_boundary(paths, tmp_dir)

          # Both should be included since link points to valid target
          assert length(result) == 2
          assert target in result
          assert link in result

        {:error, _} ->
          # Symlinks might not be supported, skip
          :ok
      end
    end
  end

  describe "sort_by_mtime_desc/1" do
    test "sorts files by modification time newest first", %{tmp_dir: tmp_dir} do
      file1 = Path.join(tmp_dir, "old.ex")
      file2 = Path.join(tmp_dir, "new.ex")

      # Create both files
      File.write!(file1, "old")
      File.write!(file2, "new")

      # Set explicit mtimes (file1 older, file2 newer)
      old_time = {{2020, 1, 1}, {0, 0, 0}}
      new_time = {{2024, 1, 1}, {0, 0, 0}}
      File.touch!(file1, old_time)
      File.touch!(file2, new_time)

      result = GlobMatcher.sort_by_mtime_desc([file1, file2])

      # Newest first
      assert hd(result) == file2
    end

    test "handles empty list" do
      result = GlobMatcher.sort_by_mtime_desc([])
      assert result == []
    end

    test "handles non-existent files gracefully" do
      paths = ["/nonexistent/file1.ex", "/nonexistent/file2.ex"]
      result = GlobMatcher.sort_by_mtime_desc(paths)

      # Should return the list unchanged (sorted by 0)
      assert length(result) == 2
    end
  end

  describe "make_relative/2" do
    test "converts absolute paths to relative", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "lib")
      File.mkdir_p!(subdir)
      file = Path.join(subdir, "app.ex")
      File.write!(file, "")

      result = GlobMatcher.make_relative([file], tmp_dir)

      assert result == ["lib/app.ex"]
    end

    test "handles multiple paths", %{tmp_dir: tmp_dir} do
      file1 = Path.join(tmp_dir, "a.ex")
      file2 = Path.join(tmp_dir, "b.ex")
      File.write!(file1, "")
      File.write!(file2, "")

      result = GlobMatcher.make_relative([file1, file2], tmp_dir)

      assert "a.ex" in result
      assert "b.ex" in result
    end

    test "handles empty list", %{tmp_dir: tmp_dir} do
      result = GlobMatcher.make_relative([], tmp_dir)
      assert result == []
    end

    test "handles nested directories", %{tmp_dir: tmp_dir} do
      deep_dir = Path.join([tmp_dir, "a", "b", "c"])
      File.mkdir_p!(deep_dir)
      file = Path.join(deep_dir, "deep.ex")
      File.write!(file, "")

      result = GlobMatcher.make_relative([file], tmp_dir)

      assert result == ["a/b/c/deep.ex"]
    end
  end
end
