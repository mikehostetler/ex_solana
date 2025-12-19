defmodule JidoCode.Tools.Handlers.ShellTest do
  # async: false because we're modifying the shared Manager state
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Handlers.Shell
  alias JidoCode.Tools.Handlers.Shell.RunCommand

  @moduletag :tmp_dir

  # Set up Manager with tmp_dir as project root for sandboxed operations
  setup %{tmp_dir: tmp_dir} do
    JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)
    :ok
  end

  # ============================================================================
  # Shell Module Tests
  # ============================================================================

  describe "validate_command/1" do
    test "allows safe commands" do
      assert {:ok, "echo"} = Shell.validate_command("echo")
      assert {:ok, "ls"} = Shell.validate_command("ls")
      assert {:ok, "cat"} = Shell.validate_command("cat")
      assert {:ok, "mix"} = Shell.validate_command("mix")
      assert {:ok, "git"} = Shell.validate_command("git")
      assert {:ok, "npm"} = Shell.validate_command("npm")
    end

    test "blocks shell interpreters" do
      assert {:error, :shell_interpreter_blocked} = Shell.validate_command("bash")
      assert {:error, :shell_interpreter_blocked} = Shell.validate_command("sh")
      assert {:error, :shell_interpreter_blocked} = Shell.validate_command("zsh")
      assert {:error, :shell_interpreter_blocked} = Shell.validate_command("fish")
      assert {:error, :shell_interpreter_blocked} = Shell.validate_command("dash")
      assert {:error, :shell_interpreter_blocked} = Shell.validate_command("ksh")
    end

    test "blocks unknown commands" do
      assert {:error, :command_not_allowed} = Shell.validate_command("unknown_cmd")
      assert {:error, :command_not_allowed} = Shell.validate_command("malicious")
      assert {:error, :command_not_allowed} = Shell.validate_command("rm_rf_everything")
    end
  end

  describe "format_error/2" do
    test "formats common errors" do
      assert Shell.format_error(:enoent, "foo") == "Command not found: foo"
      assert Shell.format_error(:eacces, "bar") == "Permission denied: bar"
      assert Shell.format_error(:enomem, "baz") == "Out of memory"
      assert Shell.format_error(:command_not_allowed, "evil") == "Command not allowed: evil"

      assert Shell.format_error(:shell_interpreter_blocked, "bash") ==
               "Shell interpreters are blocked: bash"
    end

    test "formats path errors" do
      assert Shell.format_error(:path_traversal_blocked, "../etc") ==
               "Path traversal not allowed in argument: ../etc"

      assert Shell.format_error(:absolute_path_blocked, "/etc") ==
               "Absolute paths outside project not allowed: /etc"
    end

    test "formats generic errors" do
      assert Shell.format_error({:error, :something}, "cmd") =~ "Shell error executing cmd"
      assert Shell.format_error(:unknown_atom, "cmd") == "Error (unknown_atom): cmd"
    end
  end

  describe "allowed_commands/0" do
    test "returns list of allowed commands" do
      commands = Shell.allowed_commands()
      assert is_list(commands)
      assert "echo" in commands
      assert "ls" in commands
      assert "mix" in commands
      assert "git" in commands
    end
  end

  describe "shell_interpreters/0" do
    test "returns list of blocked shell interpreters" do
      interpreters = Shell.shell_interpreters()
      assert is_list(interpreters)
      assert "bash" in interpreters
      assert "sh" in interpreters
      assert "zsh" in interpreters
    end
  end

  # ============================================================================
  # RunCommand Tests
  # ============================================================================

  describe "RunCommand.execute/2" do
    test "executes allowed command", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "echo", "args" => ["hello"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert String.trim(result["stdout"]) == "hello"
    end

    test "captures exit code", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "false"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] != 0
    end

    test "runs in project directory", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "pwd"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      # pwd may return with trailing newline
      assert String.contains?(result["stdout"], tmp_dir)
    end

    test "handles command with multiple arguments", %{tmp_dir: tmp_dir} do
      # Create a test file
      File.write!(Path.join(tmp_dir, "test.txt"), "hello world")

      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "cat", "args" => ["test.txt"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["stdout"] == "hello world"
    end

    test "returns error for non-existent command", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      # nonexistent_cmd_xyz is not in allowlist, so gets blocked first
      {:error, error} = RunCommand.execute(%{"command" => "nonexistent_cmd_xyz"}, context)
      assert error =~ "not allowed"
    end

    test "handles empty args", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "true", "args" => []}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    test "handles missing args key", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "true"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end

    @tag :skip
    # TODO: Timeout support needs to be implemented in Manager.shell/Bridge.lua_shell
    test "respects timeout", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # Use a very short timeout
      {:ok, json} =
        RunCommand.execute(
          %{"command" => "sleep", "args" => ["5"], "timeout" => 100},
          context
        )

      result = Jason.decode!(json)
      assert result["exit_code"] == -1
      assert result["stderr"] =~ "timed out"
    end

    test "returns error for missing command", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:error, error} = RunCommand.execute(%{}, context)
      assert error =~ "requires a command"
    end

    test "converts non-string args to strings", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "echo", "args" => [123, "test"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert String.trim(result["stdout"]) == "123 test"
    end

    test "creates file in project directory", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:ok, json} =
        RunCommand.execute(%{"command" => "touch", "args" => ["newfile.txt"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert File.exists?(Path.join(tmp_dir, "newfile.txt"))
    end

    test "lists files in project directory", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "a.txt"), "")
      File.write!(Path.join(tmp_dir, "b.txt"), "")

      context = %{project_root: tmp_dir}
      {:ok, json} = RunCommand.execute(%{"command" => "ls"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["stdout"] =~ "a.txt"
      assert result["stdout"] =~ "b.txt"
    end

    test "handles non-list args parameter", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}
      # Non-list args should be treated as empty list
      {:ok, json} = RunCommand.execute(%{"command" => "true", "args" => "not_a_list"}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
    end
  end

  # ============================================================================
  # Security Tests
  # ============================================================================

  describe "command allowlist security" do
    test "blocks shell interpreters", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:error, error} =
        RunCommand.execute(%{"command" => "bash", "args" => ["-c", "echo hi"]}, context)

      assert error =~ "Shell interpreters are blocked"

      {:error, error} =
        RunCommand.execute(%{"command" => "sh", "args" => ["-c", "echo hi"]}, context)

      assert error =~ "Shell interpreters are blocked"

      {:error, error} = RunCommand.execute(%{"command" => "zsh"}, context)
      assert error =~ "Shell interpreters are blocked"
    end

    test "blocks unknown commands", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:error, error} = RunCommand.execute(%{"command" => "evil_command"}, context)
      assert error =~ "not allowed"

      {:error, error} = RunCommand.execute(%{"command" => "malware"}, context)
      assert error =~ "not allowed"
    end

    test "allows common development commands", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # These should all succeed (or fail for non-command reasons, not allowlist)
      {:ok, _} = RunCommand.execute(%{"command" => "echo", "args" => ["test"]}, context)
      {:ok, _} = RunCommand.execute(%{"command" => "ls"}, context)
      {:ok, _} = RunCommand.execute(%{"command" => "cat", "args" => ["/dev/null"]}, context)
      {:ok, _} = RunCommand.execute(%{"command" => "true"}, context)
      {:ok, _} = RunCommand.execute(%{"command" => "false"}, context)
    end
  end

  describe "path argument security" do
    test "blocks path traversal in arguments", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:error, error} =
        RunCommand.execute(%{"command" => "cat", "args" => ["../../../etc/passwd"]}, context)

      assert error =~ "path traversal not allowed"

      {:error, error} =
        RunCommand.execute(%{"command" => "ls", "args" => ["foo/../../../bar"]}, context)

      assert error =~ "path traversal not allowed"
    end

    test "blocks absolute paths outside project", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:error, error} =
        RunCommand.execute(%{"command" => "cat", "args" => ["/etc/passwd"]}, context)

      assert error =~ "absolute paths outside project not allowed"

      {:error, error} = RunCommand.execute(%{"command" => "ls", "args" => ["/home"]}, context)
      assert error =~ "absolute paths outside project not allowed"
    end

    test "allows absolute paths inside project", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test.txt"), "content")
      context = %{project_root: tmp_dir}

      abs_path = Path.join(tmp_dir, "test.txt")
      {:ok, json} = RunCommand.execute(%{"command" => "cat", "args" => [abs_path]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["stdout"] == "content"
    end

    test "allows relative paths without traversal", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))
      File.write!(Path.join(tmp_dir, "subdir/file.txt"), "nested content")
      context = %{project_root: tmp_dir}

      {:ok, json} =
        RunCommand.execute(%{"command" => "cat", "args" => ["subdir/file.txt"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert result["stdout"] == "nested content"
    end
  end

  describe "output truncation" do
    test "truncates large output", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      # Generate output larger than 1MB using printf with repeat
      # Using yes with head would be cleaner but yes is not in allowlist
      # Instead, create a large file and cat it
      large_content = String.duplicate("x", 2_000_000)
      File.write!(Path.join(tmp_dir, "large.txt"), large_content)

      {:ok, json} = RunCommand.execute(%{"command" => "cat", "args" => ["large.txt"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      assert String.contains?(result["stdout"], "[Output truncated at 1MB]")
      # Output should be around 1MB plus truncation message
      assert byte_size(result["stdout"]) < 1_100_000
    end

    test "does not truncate small output", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:ok, json} =
        RunCommand.execute(%{"command" => "echo", "args" => ["small output"]}, context)

      result = Jason.decode!(json)
      assert result["exit_code"] == 0
      refute String.contains?(result["stdout"], "[Output truncated")
    end
  end
end
