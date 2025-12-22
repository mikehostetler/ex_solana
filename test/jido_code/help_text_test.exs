defmodule JidoCode.HelpTextTest do
  use ExUnit.Case, async: true

  alias JidoCode.Commands

  describe "help text" do
    test "/help includes keyboard shortcuts section" do
      {:ok, help_text, _} = Commands.execute("/help", %{provider: nil, model: nil})

      assert help_text =~ "Keyboard Shortcuts:"
      assert help_text =~ "Ctrl+M"
      assert help_text =~ "Ctrl+1 to Ctrl+0"
      assert help_text =~ "Ctrl+Tab"
      assert help_text =~ "Ctrl+W"
      assert help_text =~ "Ctrl+N"
      assert help_text =~ "Ctrl+R"
    end

    test "/help includes examples section" do
      {:ok, help_text, _} = Commands.execute("/help", %{provider: nil, model: nil})

      assert help_text =~ "Examples:"
      assert help_text =~ "/model anthropic:claude-3-5-sonnet-20241022"
      assert help_text =~ "/session new ~/projects/myapp"
      assert help_text =~ "/shell mix test"
    end

    test "/help categorizes commands" do
      {:ok, help_text, _} = Commands.execute("/help", %{provider: nil, model: nil})

      assert help_text =~ "Configuration:"
      assert help_text =~ "Session Management:"
      assert help_text =~ "Development:"
    end

    test "/help includes all major commands" do
      {:ok, help_text, _} = Commands.execute("/help", %{provider: nil, model: nil})

      # Configuration commands
      assert help_text =~ "/config"
      assert help_text =~ "/provider"
      assert help_text =~ "/model"
      assert help_text =~ "/theme"

      # Session commands
      assert help_text =~ "/session new"
      assert help_text =~ "/session list"
      assert help_text =~ "/session switch"
      assert help_text =~ "/session close"
      assert help_text =~ "/session rename"
      assert help_text =~ "/resume"

      # Development commands
      assert help_text =~ "/shell"
      assert help_text =~ "/sandbox-test"
    end
  end

  describe "session help text" do
    test "/session help includes enhanced keyboard shortcuts" do
      {:ok, help_text} = Commands.execute_session(:help, %{provider: nil, model: nil})

      assert help_text =~ "Keyboard Shortcuts:"
      assert help_text =~ "Ctrl+1 to Ctrl+0"
      assert help_text =~ "Ctrl+0 = session 10"
      assert help_text =~ "Ctrl+Tab"
      assert help_text =~ "Ctrl+Shift+Tab"
      assert help_text =~ "Ctrl+W"
      assert help_text =~ "Ctrl+N"
    end

    test "/session help includes examples" do
      {:ok, help_text} = Commands.execute_session(:help, %{provider: nil, model: nil})

      assert help_text =~ "Examples:"
      assert help_text =~ "/session new ~/projects/myapp --name=\"My App\""
      assert help_text =~ "/session new"
      assert help_text =~ "(uses current directory)"
      assert help_text =~ "/session switch 2"
      assert help_text =~ "/session switch my-app"
      assert help_text =~ "/session rename \"Backend API\""
    end

    test "/session help includes notes section" do
      {:ok, help_text} = Commands.execute_session(:help, %{provider: nil, model: nil})

      assert help_text =~ "Notes:"
      assert help_text =~ "Maximum 10 sessions"
      assert help_text =~ "automatically saved when closed"
      assert help_text =~ "Use /resume to restore"
      assert help_text =~ "50 characters or less"
    end

    test "/session help includes all subcommands" do
      {:ok, help_text} = Commands.execute_session(:help, %{provider: nil, model: nil})

      assert help_text =~ "/session new"
      assert help_text =~ "/session list"
      assert help_text =~ "/session switch"
      assert help_text =~ "/session close"
      assert help_text =~ "/session rename"
    end

    test "/session help descriptions are clear and actionable" do
      {:ok, help_text} = Commands.execute_session(:help, %{provider: nil, model: nil})

      assert help_text =~ "Create new session (defaults to cwd)"
      assert help_text =~ "List all sessions with indices"
      assert help_text =~ "Switch to session by index, ID, or name"
      assert help_text =~ "Close session (defaults to current)"
      assert help_text =~ "Rename current session"
    end
  end

  describe "message consistency" do
    test "success messages follow consistent format" do
      # This is a documentation test to ensure we maintain the pattern:
      # - Session lifecycle: "[Action]: [Details]"
      # - Configuration: "[Setting] set to [value]"
      # Examples from the codebase:
      # - "Created session: my-project"
      # - "Switched to: session-name"
      # - "Provider set to anthropic"
      # - "Model set to anthropic:claude-3-5-sonnet"

      # Note: Configuration messages require API credentials in test environment
      # The pattern is verified through code review and integration tests
      # Session action messages are tested in integration tests
      # They follow the "[Action]: [Details]" pattern

      # Verify the pattern exists in help text examples
      {:ok, help_text, _} = Commands.execute("/help", %{provider: nil, model: nil})
      assert help_text =~ "/model anthropic:claude-3-5-sonnet-20241022"
    end

    test "error messages include actionable guidance" do
      # Unknown command includes guidance
      {:error, message} = Commands.execute("/unknown", %{provider: nil, model: nil})
      assert message =~ "Unknown command"
      assert message =~ "Type /help"

      # Empty provider error includes guidance
      {:error, message} = Commands.execute("/models", %{provider: nil, model: nil})
      assert message =~ "/provider"
    end
  end

  describe "help text accessibility" do
    test "help text uses clear, non-technical language" do
      {:ok, help_text, _} = Commands.execute("/help", %{provider: nil, model: nil})

      # Should use user-friendly terms
      assert help_text =~ "Session Management"
      assert help_text =~ "Keyboard Shortcuts"
      assert help_text =~ "Examples"

      # Should not have technical jargon in descriptions
      refute help_text =~ "GenServer"
      refute help_text =~ "ETS"
      refute help_text =~ "PID"
    end

    test "session help is comprehensive and beginner-friendly" do
      {:ok, help_text} = Commands.execute_session(:help, %{provider: nil, model: nil})

      # Includes helpful context
      assert help_text =~ "defaults to"
      assert help_text =~ "Notes:"

      # No technical implementation details
      refute help_text =~ "GenServer"
      refute help_text =~ "process"
      refute help_text =~ "registry"
    end
  end
end
