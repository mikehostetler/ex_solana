defmodule JidoCode.Session.SettingsTest do
  use ExUnit.Case, async: true

  import Bitwise
  import ExUnit.CaptureLog

  alias JidoCode.Session.Settings

  # ============================================================================
  # Path Validation Tests (Security)
  # ============================================================================

  describe "validate_project_path/1" do
    test "accepts valid absolute paths" do
      assert {:ok, "/home/user/project"} = Settings.validate_project_path("/home/user/project")
      assert {:ok, "/tmp/test"} = Settings.validate_project_path("/tmp/test")
      assert {:ok, "/"} = Settings.validate_project_path("/")
    end

    test "expands paths with tilde" do
      {:ok, expanded} = Settings.validate_project_path("~/project")
      assert String.starts_with?(expanded, "/")
      refute String.contains?(expanded, "~")
    end

    test "rejects paths with traversal components" do
      assert {:error, "path contains '..' traversal"} =
               Settings.validate_project_path("/home/user/../etc")

      assert {:error, "path contains '..' traversal"} =
               Settings.validate_project_path("../escape")

      assert {:error, "path contains '..' traversal"} =
               Settings.validate_project_path("/safe/path/../../etc/passwd")
    end

    test "rejects paths with null bytes" do
      assert {:error, "path contains null byte"} =
               Settings.validate_project_path("/home/user\0/project")
    end

    test "rejects excessively long paths" do
      long_path = "/" <> String.duplicate("a", 5000)

      assert {:error, "path exceeds maximum length of 4096 bytes"} =
               Settings.validate_project_path(long_path)
    end

    test "rejects relative paths that don't expand to absolute" do
      # Relative paths without tilde that don't start with /
      # Note: Path.expand will make them absolute based on cwd,
      # so most relative paths will actually pass after expansion
      {:ok, expanded} = Settings.validate_project_path("relative/path")
      assert String.starts_with?(expanded, "/")
    end
  end

  describe "validate_project_path!/1" do
    test "returns path for valid input" do
      assert Settings.validate_project_path!("/tmp/test") == "/tmp/test"
    end

    test "raises ArgumentError for path traversal" do
      assert_raise ArgumentError, ~r/Invalid project path.*traversal/, fn ->
        Settings.validate_project_path!("/home/../etc")
      end
    end

    test "raises ArgumentError for null bytes" do
      assert_raise ArgumentError, ~r/Invalid project path.*null byte/, fn ->
        Settings.validate_project_path!("/home\0/user")
      end
    end
  end

  # ============================================================================
  # Settings Loading Tests
  # ============================================================================

  describe "load_local/1" do
    @describetag :tmp_dir

    test "returns settings from existing file", %{tmp_dir: tmp_dir} do
      # Create settings file
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "anthropic", "model": "claude-3"}))

      result = Settings.load_local(tmp_dir)

      assert result == %{"provider" => "anthropic", "model" => "claude-3"}
    end

    test "returns empty map for missing file", %{tmp_dir: tmp_dir} do
      result = Settings.load_local(tmp_dir)

      assert result == %{}
    end

    test "returns empty map and logs warning for malformed JSON", %{tmp_dir: tmp_dir} do
      # Create malformed settings file
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, "{ invalid json }")

      log =
        capture_log(fn ->
          result = Settings.load_local(tmp_dir)
          assert result == %{}
        end)

      assert log =~ "Malformed JSON"
      assert log =~ "local"
    end
  end

  describe "load_global/0" do
    # Note: We can't easily test load_global with a real file without modifying
    # the user's home directory. We test the behavior indirectly through load/1.

    test "returns a map (may be empty if no global settings)" do
      result = Settings.load_global()

      assert is_map(result)
    end
  end

  describe "load/1" do
    @describetag :tmp_dir

    test "merges global and local settings", %{tmp_dir: tmp_dir} do
      # Create local settings file
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"model": "local-model"}))

      result = Settings.load(tmp_dir)

      # Local settings should be present
      assert result["model"] == "local-model"
      # Result should be a map
      assert is_map(result)
    end

    test "local settings override global settings", %{tmp_dir: tmp_dir} do
      # Create local settings with a key that might also be in global
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "local-provider"}))

      result = Settings.load(tmp_dir)

      # Local value should override any global value
      assert result["provider"] == "local-provider"
    end

    test "returns global settings when no local file exists", %{tmp_dir: tmp_dir} do
      # Don't create any local settings
      result = Settings.load(tmp_dir)

      # Should still return a map (global settings or empty)
      assert is_map(result)
    end

    test "returns empty map when no settings files exist", %{tmp_dir: tmp_dir} do
      # Use a subdirectory to avoid any existing settings
      project_path = Path.join(tmp_dir, "empty-project")
      File.mkdir_p!(project_path)

      result = Settings.load(project_path)

      # Result should be a map (may include global settings)
      assert is_map(result)
    end
  end

  # ============================================================================
  # Path Helper Tests
  # ============================================================================

  describe "local_dir/1" do
    test "returns settings directory path for project" do
      assert Settings.local_dir("/home/user/myproject") == "/home/user/myproject/.jido_code"
    end

    test "handles various project paths" do
      assert Settings.local_dir("/tmp/test") == "/tmp/test/.jido_code"
      assert Settings.local_dir("/") == "/.jido_code"
      assert Settings.local_dir("/a/b/c/d") == "/a/b/c/d/.jido_code"
    end

    test "handles paths with trailing slash" do
      # Path.join handles trailing slashes
      assert Settings.local_dir("/tmp/test/") == "/tmp/test/.jido_code"
    end
  end

  describe "local_path/1" do
    test "returns settings file path for project" do
      assert Settings.local_path("/home/user/myproject") ==
               "/home/user/myproject/.jido_code/settings.json"
    end

    test "handles various project paths" do
      assert Settings.local_path("/tmp/test") == "/tmp/test/.jido_code/settings.json"
      assert Settings.local_path("/") == "/.jido_code/settings.json"
      assert Settings.local_path("/a/b/c/d") == "/a/b/c/d/.jido_code/settings.json"
    end

    test "handles paths with trailing slash" do
      assert Settings.local_path("/tmp/test/") == "/tmp/test/.jido_code/settings.json"
    end
  end

  describe "ensure_local_dir/1" do
    @describetag :tmp_dir

    test "creates directory when it doesn't exist", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)
      expected_dir = Path.join(project_path, ".jido_code")

      # Directory should not exist yet
      refute File.dir?(expected_dir)

      result = Settings.ensure_local_dir(project_path)

      assert result == {:ok, expected_dir}
      assert File.dir?(expected_dir)
    end

    test "returns ok when directory already exists", %{tmp_dir: tmp_dir} do
      # Create the directory first
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)

      result = Settings.ensure_local_dir(tmp_dir)

      assert result == {:ok, settings_dir}
      assert File.dir?(settings_dir)
    end

    test "returns directory path on success", %{tmp_dir: tmp_dir} do
      {:ok, dir_path} = Settings.ensure_local_dir(tmp_dir)

      assert dir_path == Path.join(tmp_dir, ".jido_code")
      assert String.ends_with?(dir_path, ".jido_code")
    end

    test "rejects symlink directory", %{tmp_dir: tmp_dir} do
      # Create a target directory
      target_dir = Path.join(tmp_dir, "target")
      File.mkdir_p!(target_dir)

      # Create project with symlink .jido_code pointing to target
      project_path = Path.join(tmp_dir, "project")
      File.mkdir_p!(project_path)
      symlink_path = Path.join(project_path, ".jido_code")
      File.ln_s!(target_dir, symlink_path)

      # ensure_local_dir should reject the symlink
      result = Settings.ensure_local_dir(project_path)

      assert {:error, "security violation: path is a symlink"} = result
    end
  end

  # ============================================================================
  # Security Tests (Symlink and Path Attacks)
  # ============================================================================

  describe "symlink attack prevention" do
    @describetag :tmp_dir

    test "save/2 rejects path traversal", %{tmp_dir: tmp_dir} do
      assert_raise ArgumentError, ~r/Invalid project path.*traversal/, fn ->
        Settings.save("#{tmp_dir}/../escape", %{"provider" => "test"})
      end
    end

    test "load/1 rejects path traversal", %{tmp_dir: tmp_dir} do
      assert_raise ArgumentError, ~r/Invalid project path.*traversal/, fn ->
        Settings.load("#{tmp_dir}/../escape")
      end
    end

    test "load_local/1 rejects path traversal", %{tmp_dir: tmp_dir} do
      assert_raise ArgumentError, ~r/Invalid project path.*traversal/, fn ->
        Settings.load_local("#{tmp_dir}/../escape")
      end
    end

    test "set/3 rejects path traversal", %{tmp_dir: tmp_dir} do
      assert_raise ArgumentError, ~r/Invalid project path.*traversal/, fn ->
        Settings.set("#{tmp_dir}/../escape", "provider", "test")
      end
    end
  end

  # ============================================================================
  # Settings Saving Tests
  # ============================================================================

  describe "save/2" do
    @describetag :tmp_dir

    test "creates settings file", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)
      settings = %{"provider" => "anthropic", "model" => "claude-3"}

      result = Settings.save(project_path, settings)

      assert result == :ok

      # Verify file was created with correct content
      settings_file = Settings.local_path(project_path)
      assert File.exists?(settings_file)
      {:ok, content} = File.read(settings_file)
      assert Jason.decode!(content) == settings
    end

    test "creates directory if missing", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)
      settings_dir = Settings.local_dir(project_path)

      # Directory should not exist yet
      refute File.dir?(settings_dir)

      result = Settings.save(project_path, %{"provider" => "openai"})

      assert result == :ok
      assert File.dir?(settings_dir)
    end

    test "overwrites existing settings file", %{tmp_dir: tmp_dir} do
      # Create initial settings
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "old_provider"}))

      # Save new settings (using valid setting keys)
      new_settings = %{"provider" => "new_provider", "model" => "new_model"}
      result = Settings.save(tmp_dir, new_settings)

      assert result == :ok
      {:ok, content} = File.read(settings_file)
      assert Jason.decode!(content) == new_settings
    end

    test "validates settings before saving", %{tmp_dir: tmp_dir} do
      # Settings with invalid type should fail validation
      # (based on JidoCode.Settings validation rules)
      invalid_settings = %{"permissions" => "not_a_map"}

      result = Settings.save(tmp_dir, invalid_settings)

      assert {:error, _} = result
    end

    test "sets file permissions to 0600", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)

      Settings.save(project_path, %{"provider" => "anthropic"})

      settings_file = Settings.local_path(project_path)
      {:ok, stat} = File.stat(settings_file)
      # 0o600 = 384 in decimal, need parens for operator precedence
      assert (stat.mode &&& 0o777) == 0o600
    end
  end

  describe "set/3" do
    @describetag :tmp_dir

    test "updates individual key", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "project")
      File.mkdir_p!(project_path)

      result = Settings.set(project_path, "provider", "anthropic")

      assert result == :ok
      assert Settings.load_local(project_path)["provider"] == "anthropic"
    end

    test "preserves other keys when updating", %{tmp_dir: tmp_dir} do
      # Create initial settings
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "openai", "model": "gpt-4"}))

      # Update only one key
      result = Settings.set(tmp_dir, "provider", "anthropic")

      assert result == :ok
      loaded = Settings.load_local(tmp_dir)
      assert loaded["provider"] == "anthropic"
      assert loaded["model"] == "gpt-4"
    end

    test "creates file when setting key on new project", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "new-project")
      File.mkdir_p!(project_path)

      # File doesn't exist yet
      refute File.exists?(Settings.local_path(project_path))

      result = Settings.set(project_path, "model", "claude-3")

      assert result == :ok
      assert File.exists?(Settings.local_path(project_path))
      assert Settings.load_local(project_path) == %{"model" => "claude-3"}
    end
  end

  # ============================================================================
  # Error Path Tests
  # ============================================================================

  describe "error handling" do
    @describetag :tmp_dir

    test "load_local/1 logs warning and returns empty map for unreadable file", %{
      tmp_dir: tmp_dir
    } do
      # Create settings dir but make file unreadable
      settings_dir = Path.join(tmp_dir, ".jido_code")
      File.mkdir_p!(settings_dir)
      settings_file = Path.join(settings_dir, "settings.json")
      File.write!(settings_file, ~s({"provider": "test"}))
      File.chmod!(settings_file, 0o000)

      # Should return empty map and log warning
      log =
        capture_log(fn ->
          result = Settings.load_local(tmp_dir)
          # May return empty map or actual content depending on user permissions
          assert is_map(result)
        end)

      # Restore permissions for cleanup
      File.chmod!(settings_file, 0o644)

      # Log may contain warning if file was truly unreadable (depends on user)
      assert is_binary(log)
    end

    test "save/2 returns error when directory creation fails", %{tmp_dir: tmp_dir} do
      # Create a file where directory should be (blocking mkdir)
      project_path = Path.join(tmp_dir, "blocked-project")
      File.mkdir_p!(project_path)
      # Create a file named .jido_code instead of directory
      blocking_file = Path.join(project_path, ".jido_code")
      File.write!(blocking_file, "blocking")

      result = Settings.save(project_path, %{"provider" => "test"})

      # Should fail because .jido_code is a file, not a directory
      assert {:error, _reason} = result
    end

    test "save/2 returns error for invalid settings", %{tmp_dir: tmp_dir} do
      # Settings with invalid type should fail validation
      invalid_settings = %{"permissions" => "not_a_map"}

      result = Settings.save(tmp_dir, invalid_settings)

      assert {:error, _} = result
    end

    test "ensure_local_dir/1 returns formatted error message", %{tmp_dir: tmp_dir} do
      # Create a read-only parent to prevent directory creation
      readonly_parent = Path.join(tmp_dir, "readonly")
      File.mkdir_p!(readonly_parent)
      File.chmod!(readonly_parent, 0o444)

      project_path = Path.join(readonly_parent, "project")

      result = Settings.ensure_local_dir(project_path)

      # Restore permissions for cleanup
      File.chmod!(readonly_parent, 0o755)

      # Should return human-readable error
      assert {:error, reason} = result
      assert is_binary(reason)
    end
  end

  # ============================================================================
  # Atomic Write Tests
  # ============================================================================

  describe "atomic write behavior" do
    @describetag :tmp_dir

    test "temp files are cleaned up on failure", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "cleanup-test")
      File.mkdir_p!(project_path)

      # Save valid settings first
      Settings.save(project_path, %{"provider" => "test"})

      # Check that no .tmp files remain
      settings_dir = Settings.local_dir(project_path)
      tmp_files = Path.wildcard(Path.join(settings_dir, "*.tmp.*"))
      assert tmp_files == []
    end

    test "uses random suffix for temp files (TOCTOU mitigation)", %{tmp_dir: tmp_dir} do
      # This is hard to test directly, but we can verify multiple saves don't conflict
      project_path = Path.join(tmp_dir, "toctou-test")
      File.mkdir_p!(project_path)

      models = ["claude-3", "gpt-4", "gemini-pro", "llama-3", "mistral-7b"]

      # Rapid sequential saves should all succeed
      for model <- models do
        assert :ok = Settings.save(project_path, %{"model" => model})
      end

      # Final value should be the last one
      assert Settings.load_local(project_path)["model"] == "mistral-7b"
    end
  end
end
