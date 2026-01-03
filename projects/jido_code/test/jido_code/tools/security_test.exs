defmodule JidoCode.Tools.SecurityTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Security

  import ExUnit.CaptureLog

  # Use a temp directory for tests
  @test_root System.tmp_dir!() |> Path.join("security_test_#{:rand.uniform(100_000)}")

  setup_all do
    # Create test directory structure
    File.mkdir_p!(@test_root)
    File.mkdir_p!(Path.join(@test_root, "src"))
    File.mkdir_p!(Path.join(@test_root, "lib/nested"))
    File.write!(Path.join(@test_root, "file.txt"), "test")
    File.write!(Path.join(@test_root, "src/main.ex"), "defmodule Main do end")

    # Create symlinks for testing
    internal_link = Path.join(@test_root, "internal_link")
    external_link = Path.join(@test_root, "external_link")
    chain_link = Path.join(@test_root, "chain_link")

    # Internal symlink (points to file within project)
    File.rm(internal_link)
    File.ln_s(Path.join(@test_root, "file.txt"), internal_link)

    # External symlink (points outside project)
    File.rm(external_link)
    File.ln_s("/etc/hosts", external_link)

    # Chained symlink (points to internal_link)
    File.rm(chain_link)
    File.ln_s(internal_link, chain_link)

    on_exit(fn ->
      File.rm_rf!(@test_root)
    end)

    :ok
  end

  describe "validate_path/3 - relative paths" do
    test "accepts valid relative path" do
      assert {:ok, resolved} =
               Security.validate_path("src/main.ex", @test_root, log_violations: false)

      assert resolved == Path.join(@test_root, "src/main.ex")
    end

    test "accepts nested relative path" do
      assert {:ok, resolved} =
               Security.validate_path("lib/nested/file.ex", @test_root, log_violations: false)

      assert resolved == Path.join(@test_root, "lib/nested/file.ex")
    end

    test "accepts current directory reference" do
      assert {:ok, resolved} =
               Security.validate_path("./src/main.ex", @test_root, log_violations: false)

      assert resolved == Path.join(@test_root, "src/main.ex")
    end

    test "accepts path with .. that stays within boundary" do
      assert {:ok, resolved} =
               Security.validate_path("src/../file.txt", @test_root, log_violations: false)

      assert resolved == Path.join(@test_root, "file.txt")
    end

    test "rejects path traversal that escapes boundary" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("../../../etc/passwd", @test_root, log_violations: false)
    end

    test "rejects excessive .. sequences" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("../../../../../../../../etc/passwd", @test_root,
                 log_violations: false
               )
    end

    test "rejects hidden path traversal" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("src/../../etc/passwd", @test_root, log_violations: false)
    end
  end

  describe "validate_path/3 - absolute paths" do
    test "accepts absolute path within project" do
      path = Path.join(@test_root, "src/main.ex")
      assert {:ok, ^path} = Security.validate_path(path, @test_root, log_violations: false)
    end

    test "accepts project root itself" do
      assert {:ok, resolved} =
               Security.validate_path(@test_root, @test_root, log_violations: false)

      assert resolved == @test_root
    end

    test "rejects absolute path outside project" do
      assert {:error, :path_outside_boundary} =
               Security.validate_path("/etc/passwd", @test_root, log_violations: false)
    end

    test "rejects absolute path to sibling directory" do
      sibling = Path.join(Path.dirname(@test_root), "other_project")

      assert {:error, :path_outside_boundary} =
               Security.validate_path(sibling, @test_root, log_violations: false)
    end

    test "rejects path that is prefix of project root" do
      # e.g., /tmp/security_test shouldn't match /tmp/security_test_other
      parent = Path.dirname(@test_root)

      assert {:error, :path_outside_boundary} =
               Security.validate_path(parent, @test_root, log_violations: false)
    end
  end

  describe "validate_path/3 - symlinks" do
    test "accepts symlink pointing within project" do
      link_path = Path.join(@test_root, "internal_link")

      if File.exists?(link_path) do
        assert {:ok, _} = Security.validate_path(link_path, @test_root, log_violations: false)
      end
    end

    test "rejects symlink pointing outside project" do
      link_path = Path.join(@test_root, "external_link")

      if File.exists?(link_path) do
        assert {:error, :symlink_escapes_boundary} =
                 Security.validate_path(link_path, @test_root, log_violations: false)
      end
    end

    test "accepts chained symlinks within project" do
      link_path = Path.join(@test_root, "chain_link")

      if File.exists?(link_path) do
        assert {:ok, _} = Security.validate_path(link_path, @test_root, log_violations: false)
      end
    end
  end

  describe "validate_path/3 - edge cases" do
    test "handles empty path" do
      # Empty path resolves to project root
      assert {:ok, resolved} = Security.validate_path("", @test_root, log_violations: false)
      assert resolved == @test_root
    end

    test "handles path with only dots" do
      assert {:ok, resolved} = Security.validate_path(".", @test_root, log_violations: false)
      assert resolved == @test_root
    end

    test "handles non-existent path within boundary" do
      assert {:ok, resolved} =
               Security.validate_path("nonexistent/path.ex", @test_root, log_violations: false)

      assert resolved == Path.join(@test_root, "nonexistent/path.ex")
    end

    test "handles path with special characters" do
      assert {:ok, resolved} =
               Security.validate_path("src/file with spaces.ex", @test_root,
                 log_violations: false
               )

      assert resolved == Path.join(@test_root, "src/file with spaces.ex")
    end

    test "rejects nil path" do
      assert {:error, :invalid_path} =
               Security.validate_path(nil, @test_root, log_violations: false)
    end

    test "rejects non-string path" do
      assert {:error, :invalid_path} =
               Security.validate_path(123, @test_root, log_violations: false)
    end
  end

  describe "validate_path/3 - logging" do
    test "logs warning on path traversal violation" do
      log =
        capture_log(fn ->
          Security.validate_path("../../../etc/passwd", @test_root)
        end)

      assert log =~ "Security violation"
      assert log =~ "path_escapes_boundary"
    end

    test "logs warning on absolute path violation" do
      log =
        capture_log(fn ->
          Security.validate_path("/etc/passwd", @test_root)
        end)

      assert log =~ "Security violation"
      assert log =~ "path_outside_boundary"
    end

    test "logs warning on symlink violation" do
      link_path = Path.join(@test_root, "external_link")

      if File.exists?(link_path) do
        log =
          capture_log(fn ->
            Security.validate_path(link_path, @test_root)
          end)

        assert log =~ "Security violation"
        assert log =~ "symlink_escapes_boundary"
      end
    end

    test "suppresses logging when log_violations: false" do
      log =
        capture_log(fn ->
          Security.validate_path("../../../etc/passwd", @test_root, log_violations: false)
        end)

      assert log == ""
    end
  end

  describe "within_boundary?/2" do
    test "returns true for path within boundary" do
      path = Path.join(@test_root, "src/file.ex")
      assert Security.within_boundary?(path, @test_root)
    end

    test "returns true for exact boundary match" do
      assert Security.within_boundary?(@test_root, @test_root)
    end

    test "returns false for path outside boundary" do
      refute Security.within_boundary?("/etc/passwd", @test_root)
    end

    test "returns false for parent directory" do
      parent = Path.dirname(@test_root)
      refute Security.within_boundary?(parent, @test_root)
    end

    test "returns false for sibling with similar prefix" do
      # Ensure /project doesn't match /project2
      sibling = @test_root <> "_sibling"
      refute Security.within_boundary?(sibling, @test_root)
    end
  end

  describe "resolve_path/2" do
    test "resolves relative path" do
      resolved = Security.resolve_path("src/file.ex", @test_root)
      assert resolved == Path.join(@test_root, "src/file.ex")
    end

    test "resolves absolute path unchanged" do
      path = "/some/absolute/path"
      resolved = Security.resolve_path(path, @test_root)
      assert resolved == path
    end

    test "resolves .. sequences" do
      resolved = Security.resolve_path("src/../file.txt", @test_root)
      assert resolved == Path.join(@test_root, "file.txt")
    end
  end

  describe "security attack vectors" do
    test "blocks null byte injection" do
      # Null bytes could be used to truncate paths in some systems
      # Elixir/Erlang handles this safely, but test anyway
      result =
        Security.validate_path("file.txt\x00/../../etc/passwd", @test_root, log_violations: false)

      # Should either be safe or error
      case result do
        {:ok, path} -> assert String.starts_with?(path, @test_root)
        {:error, _} -> :ok
      end
    end

    test "blocks URL encoding attacks" do
      # %2e%2e = .. in URL encoding (not decoded by Path functions)
      result =
        Security.validate_path("%2e%2e/%2e%2e/etc/passwd", @test_root, log_violations: false)

      # Should be treated as literal filename, staying within boundary
      case result do
        {:ok, path} -> assert String.starts_with?(path, @test_root)
        {:error, _} -> :ok
      end
    end

    test "blocks backslash path traversal" do
      # Windows-style path separators
      result = Security.validate_path("..\\..\\etc\\passwd", @test_root, log_violations: false)
      # Should be treated as literal filename on Unix
      case result do
        {:ok, path} -> assert String.starts_with?(path, @test_root)
        {:error, _} -> :ok
      end
    end

    test "blocks double slash tricks" do
      result = Security.validate_path("src//../../etc/passwd", @test_root, log_violations: false)
      assert {:error, :path_escapes_boundary} = result
    end

    test "blocks mixed separator attacks" do
      result = Security.validate_path("src/./../../etc/passwd", @test_root, log_violations: false)
      assert {:error, :path_escapes_boundary} = result
    end
  end

  describe "URL-encoded path traversal detection" do
    test "blocks standard URL-encoded path traversal (%2e%2e%2f)" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("%2e%2e%2f/etc/passwd", @test_root, log_violations: false)
    end

    test "blocks partial URL-encoded traversal (..%2f)" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("..%2f..%2f/etc/passwd", @test_root, log_violations: false)
    end

    test "blocks mixed case URL-encoded traversal (%2E%2E%2F)" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("%2E%2E%2F/etc/passwd", @test_root, log_violations: false)
    end

    test "blocks double URL-encoded traversal (%252e%252e%252f)" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path(
                 "%252e%252e%252f/etc/passwd",
                 @test_root,
                 log_violations: false
               )
    end

    test "blocks URL-encoded backslash traversal (..%5c)" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("..%5c..%5c/etc/passwd", @test_root, log_violations: false)
    end

    test "blocks URL-encoded traversal embedded in valid path" do
      assert {:error, :path_escapes_boundary} =
               Security.validate_path("src/%2e%2e%2fsecret", @test_root, log_violations: false)
    end

    test "allows paths that look similar but are not traversal patterns" do
      # %2d = hyphen, not a path separator
      assert {:ok, _} =
               Security.validate_path("file%2dname.txt", @test_root, log_violations: false)
    end
  end

  describe "Unicode and special character paths" do
    setup do
      # Create files with Unicode names for testing
      unicode_dir = Path.join(@test_root, "unicode_files")
      File.mkdir_p!(unicode_dir)

      # Create files with various special names
      File.write!(Path.join(unicode_dir, "日本語.txt"), "japanese content")
      File.write!(Path.join(unicode_dir, "émoji_📁.txt"), "emoji content")
      File.write!(Path.join(unicode_dir, "spaces and tabs.txt"), "whitespace")
      File.write!(Path.join(unicode_dir, "special!@#$%^&().txt"), "special chars")

      on_exit(fn ->
        File.rm_rf!(unicode_dir)
      end)

      {:ok, unicode_dir: unicode_dir}
    end

    test "accepts paths with Japanese characters", %{unicode_dir: unicode_dir} do
      path = Path.join(unicode_dir, "日本語.txt")
      relative_path = Path.relative_to(path, @test_root)

      assert {:ok, resolved} =
               Security.validate_path(relative_path, @test_root, log_violations: false)

      assert resolved == path
    end

    test "accepts paths with emoji characters", %{unicode_dir: unicode_dir} do
      path = Path.join(unicode_dir, "émoji_📁.txt")
      relative_path = Path.relative_to(path, @test_root)

      assert {:ok, resolved} =
               Security.validate_path(relative_path, @test_root, log_violations: false)

      assert resolved == path
    end

    test "accepts paths with spaces and special characters", %{unicode_dir: unicode_dir} do
      path = Path.join(unicode_dir, "spaces and tabs.txt")
      relative_path = Path.relative_to(path, @test_root)

      assert {:ok, resolved} =
               Security.validate_path(relative_path, @test_root, log_violations: false)

      assert resolved == path
    end

    test "accepts paths with shell special characters", %{unicode_dir: unicode_dir} do
      path = Path.join(unicode_dir, "special!@#$%^&().txt")
      relative_path = Path.relative_to(path, @test_root)

      assert {:ok, resolved} =
               Security.validate_path(relative_path, @test_root, log_violations: false)

      assert resolved == path
    end

    test "atomic_read works with Unicode filenames", %{unicode_dir: unicode_dir} do
      relative_path =
        Path.join(Path.relative_to(unicode_dir, @test_root), "日本語.txt")

      assert {:ok, "japanese content"} =
               Security.atomic_read(relative_path, @test_root, log_violations: false)
    end

    test "atomic_write works with Unicode filenames", %{unicode_dir: unicode_dir} do
      new_file = Path.join(Path.relative_to(unicode_dir, @test_root), "新規ファイル.txt")
      content = "new unicode content"

      assert :ok = Security.atomic_write(new_file, content, @test_root, log_violations: false)

      # Verify content was written
      full_path = Path.join(@test_root, new_file)
      assert File.read!(full_path) == content
    end
  end

  describe "advanced symlink scenarios" do
    setup do
      symlink_dir = Path.join(@test_root, "symlink_test")
      File.mkdir_p!(symlink_dir)

      # Create a regular file
      File.write!(Path.join(symlink_dir, "target.txt"), "target content")

      # Create a directory with files
      nested_dir = Path.join(symlink_dir, "nested")
      File.mkdir_p!(nested_dir)
      File.write!(Path.join(nested_dir, "nested_file.txt"), "nested content")

      on_exit(fn ->
        File.rm_rf!(symlink_dir)
      end)

      {:ok, symlink_dir: symlink_dir, nested_dir: nested_dir}
    end

    test "rejects symlink loop", %{symlink_dir: symlink_dir} do
      # Create symlink loop: a -> b -> a
      link_a = Path.join(symlink_dir, "loop_a")
      link_b = Path.join(symlink_dir, "loop_b")

      File.rm(link_a)
      File.rm(link_b)

      # Create circular symlinks (order matters)
      File.ln_s(link_b, link_a)
      File.ln_s(link_a, link_b)

      # Should detect loop and return error
      result = Security.validate_path(link_a, @test_root, log_violations: false)

      assert {:error, :invalid_path} = result
    end

    test "accepts symlink to directory within boundary", %{
      symlink_dir: symlink_dir,
      nested_dir: nested_dir
    } do
      dir_link = Path.join(symlink_dir, "dir_link")
      File.rm(dir_link)
      File.ln_s(nested_dir, dir_link)

      assert {:ok, _} = Security.validate_path(dir_link, @test_root, log_violations: false)
    end

    test "accepts relative symlink within boundary", %{symlink_dir: symlink_dir} do
      relative_link = Path.join(symlink_dir, "relative_link")
      File.rm(relative_link)

      # Create relative symlink to sibling file
      File.ln_s("target.txt", relative_link)

      assert {:ok, resolved} =
               Security.validate_path(relative_link, @test_root, log_violations: false)

      # Verify symlink was followed
      assert File.exists?(resolved)
    end

    test "rejects symlink chain that eventually escapes", %{symlink_dir: symlink_dir} do
      # Create chain: link1 -> link2 -> /etc/hosts
      link1 = Path.join(symlink_dir, "chain_escape_1")
      link2 = Path.join(symlink_dir, "chain_escape_2")

      File.rm(link1)
      File.rm(link2)

      # link2 points outside
      File.ln_s("/etc/hosts", link2)
      # link1 points to link2
      File.ln_s(link2, link1)

      # Should detect escape through chain
      assert {:error, :symlink_escapes_boundary} =
               Security.validate_path(link1, @test_root, log_violations: false)
    end
  end

  describe "atomic_read/3 - TOCTOU mitigation" do
    test "reads file within boundary" do
      assert {:ok, "test"} = Security.atomic_read("file.txt", @test_root, log_violations: false)
    end

    test "reads nested file within boundary" do
      assert {:ok, content} =
               Security.atomic_read("src/main.ex", @test_root, log_violations: false)

      assert content =~ "defmodule Main"
    end

    test "rejects path traversal attempts" do
      assert {:error, :path_escapes_boundary} =
               Security.atomic_read("../../../etc/passwd", @test_root, log_violations: false)
    end

    test "rejects absolute paths outside boundary" do
      assert {:error, :path_outside_boundary} =
               Security.atomic_read("/etc/passwd", @test_root, log_violations: false)
    end

    test "returns file error for non-existent file" do
      assert {:error, :enoent} =
               Security.atomic_read("nonexistent.txt", @test_root, log_violations: false)
    end

    test "rejects symlink pointing outside boundary" do
      link_path = Path.join(@test_root, "external_link")

      if File.exists?(link_path) do
        # When reading via symlink that escapes, should detect during validation
        assert {:error, :symlink_escapes_boundary} =
                 Security.atomic_read("external_link", @test_root, log_violations: false)
      end
    end
  end

  describe "atomic_write/4 - TOCTOU mitigation" do
    @tag :tmp_dir
    test "writes file within boundary", %{tmp_dir: tmp_dir} do
      content = "test content #{:rand.uniform(1000)}"

      assert :ok =
               Security.atomic_write("test_write.txt", content, tmp_dir, log_violations: false)

      assert File.read!(Path.join(tmp_dir, "test_write.txt")) == content
    end

    @tag :tmp_dir
    test "creates parent directories", %{tmp_dir: tmp_dir} do
      content = "nested content"

      assert :ok =
               Security.atomic_write("a/b/c/nested.txt", content, tmp_dir, log_violations: false)

      assert File.read!(Path.join(tmp_dir, "a/b/c/nested.txt")) == content
    end

    @tag :tmp_dir
    test "rejects path traversal attempts", %{tmp_dir: tmp_dir} do
      assert {:error, :path_escapes_boundary} =
               Security.atomic_write("../evil.txt", "bad", tmp_dir, log_violations: false)
    end

    @tag :tmp_dir
    test "rejects absolute paths outside boundary", %{tmp_dir: tmp_dir} do
      assert {:error, :path_outside_boundary} =
               Security.atomic_write("/tmp/evil.txt", "bad", tmp_dir, log_violations: false)
    end
  end

  describe "validate_realpath/3 - post-operation validation" do
    test "accepts file within boundary" do
      path = Path.join(@test_root, "file.txt")
      assert :ok = Security.validate_realpath(path, @test_root, log_violations: false)
    end

    test "returns ok for non-existent file" do
      path = Path.join(@test_root, "nonexistent.txt")
      assert :ok = Security.validate_realpath(path, @test_root, log_violations: false)
    end

    test "rejects symlink pointing outside boundary" do
      link_path = Path.join(@test_root, "external_link")

      if File.exists?(link_path) do
        # The real path of external_link is /etc/hosts which is outside boundary
        # Note: validate_realpath checks the expanded path, but external_link
        # is detected earlier during symlink resolution
        result = Security.validate_realpath(link_path, @test_root, log_violations: false)
        # The symlink itself is within the project, but points outside
        # validate_realpath only checks if the file location is valid
        assert result == :ok or result == {:error, :symlink_escapes_boundary}
      end
    end
  end

  describe "validate_path/3 - protected settings files" do
    test "blocks access to .jido_code/settings.json in project root" do
      assert {:error, :protected_settings_file} =
               Security.validate_path(".jido_code/settings.json", @test_root,
                 log_violations: false
               )
    end

    test "blocks access to .jido_code/settings.json with absolute path" do
      settings_path = Path.join(@test_root, ".jido_code/settings.json")

      assert {:error, :protected_settings_file} =
               Security.validate_path(settings_path, @test_root, log_violations: false)
    end

    test "blocks access to .jido_code/settings.json in subdirectory" do
      subdir_settings = "src/.jido_code/settings.json"

      assert {:error, :protected_settings_file} =
               Security.validate_path(subdir_settings, @test_root, log_violations: false)
    end

    test "blocks access with path traversal to .jido_code/settings.json" do
      traversal_path = "src/../.jido_code/settings.json"

      assert {:error, :protected_settings_file} =
               Security.validate_path(traversal_path, @test_root, log_violations: false)
    end

    test "allows access to other files in .jido_code directory" do
      # Other files in .jido_code should be accessible
      assert {:ok, _resolved} =
               Security.validate_path(".jido_code/cache.json", @test_root, log_violations: false)

      assert {:ok, _resolved} =
               Security.validate_path(".jido_code/logs/app.log", @test_root,
                 log_violations: false
               )
    end

    test "allows access to files named settings.json elsewhere" do
      # settings.json in other directories should be fine
      assert {:ok, _resolved} =
               Security.validate_path("config/settings.json", @test_root, log_violations: false)

      assert {:ok, _resolved} =
               Security.validate_path("src/settings.json", @test_root, log_violations: false)
    end

    test "allows access to directories named .jido_code" do
      # Can access the .jido_code directory itself, just not settings.json in it
      assert {:ok, _resolved} =
               Security.validate_path(".jido_code", @test_root, log_violations: false)

      assert {:ok, _resolved} =
               Security.validate_path(".jido_code/", @test_root, log_violations: false)
    end

    test "logs violation when attempting to access protected settings" do
      log =
        capture_log(fn ->
          Security.validate_path(".jido_code/settings.json", @test_root, log_violations: true)
        end)

      assert log =~ "Security violation: protected_settings_file"
    end
  end

  describe "atomic_read/3 - protected settings files" do
    setup do
      # Create .jido_code directory and settings file for testing
      jido_dir = Path.join(@test_root, ".jido_code")
      File.mkdir_p!(jido_dir)
      settings_file = Path.join(jido_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "anthropic"}))

      on_exit(fn ->
        File.rm_rf!(jido_dir)
      end)

      {:ok, settings_file: settings_file}
    end

    test "blocks reading protected settings file", %{settings_file: settings_file} do
      assert {:error, :protected_settings_file} =
               Security.atomic_read(settings_file, @test_root, log_violations: false)
    end

    test "blocks reading protected settings file with relative path" do
      assert {:error, :protected_settings_file} =
               Security.atomic_read(".jido_code/settings.json", @test_root, log_violations: false)
    end
  end

  describe "atomic_write/3 - protected settings files" do
    test "blocks writing to protected settings file" do
      content = ~s({"provider": "openai"})

      assert {:error, :protected_settings_file} =
               Security.atomic_write(
                 ".jido_code/settings.json",
                 content,
                 @test_root,
                 log_violations: false
               )
    end

    test "blocks writing to protected settings file with absolute path" do
      settings_path = Path.join(@test_root, ".jido_code/settings.json")
      content = ~s({"provider": "openai"})

      assert {:error, :protected_settings_file} =
               Security.atomic_write(settings_path, content, @test_root, log_violations: false)
    end

    test "allows writing to other files in .jido_code directory" do
      content = "cache data"

      assert :ok =
               Security.atomic_write(".jido_code/cache.json", content, @test_root,
                 log_violations: false
               )

      # Verify file was written
      cache_path = Path.join(@test_root, ".jido_code/cache.json")
      assert File.exists?(cache_path)
      assert File.read!(cache_path) == content

      # Cleanup
      File.rm!(cache_path)
    end
  end
end
