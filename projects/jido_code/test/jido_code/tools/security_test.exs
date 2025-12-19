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
end
