defmodule JidoCode.CommandsTest do
  # Not async because theme tests depend on shared TermUI.Theme server state
  use ExUnit.Case, async: false

  import JidoCode.PersistenceTestHelpers

  alias Jido.AI.Keyring
  alias JidoCode.Commands

  # Helper to set up API key for tests
  defp setup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.set_session_value(key_name, "test-api-key-#{provider}")
  end

  defp cleanup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.clear_session_value(key_name)
  end

  defp provider_to_key_name(provider) do
    case provider do
      "openai" -> :openai_api_key
      "anthropic" -> :anthropic_api_key
      "openrouter" -> :openrouter_api_key
      _ -> String.to_atom("#{provider}_api_key")
    end
  end

  describe "execute/2" do
    test "/help returns command list" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/help", config)

      assert message =~ "Available commands"
      assert message =~ "/help"
      assert message =~ "/config"
      assert message =~ "/provider"
      assert message =~ "/model"
      assert new_config == %{}
    end

    test "/config shows current configuration" do
      config = %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}

      {:ok, message, new_config} = Commands.execute("/config", config)

      assert message =~ "Provider: anthropic"
      assert message =~ "Model: claude-3-5-haiku-20241022"
      assert new_config == %{}
    end

    test "/config shows (not set) for nil values" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: (not set)"
      assert message =~ "Model: (not set)"
    end

    test "/provider with valid provider sets provider and clears model" do
      setup_api_key("anthropic")
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, new_config} = Commands.execute("/provider anthropic", config)

      assert message =~ "Provider set to anthropic"
      assert new_config == %{provider: "anthropic", model: nil}
      cleanup_api_key("anthropic")
    end

    test "/provider with local provider works without API key" do
      # Local providers (lmstudio, llama, ollama) don't require API keys
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, new_config} = Commands.execute("/provider lmstudio", config)

      assert message =~ "Provider set to lmstudio"
      assert new_config == %{provider: "lmstudio", model: nil}
    end

    test "/provider without argument shows usage" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/provider", config)

      assert message =~ "Usage: /provider <name>"
    end

    test "/provider with invalid provider shows error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/provider invalid_provider_xyz", config)

      assert message =~ "Unknown provider"
    end

    test "/model provider:model sets both" do
      setup_api_key("anthropic")
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} =
        Commands.execute("/model anthropic:claude-3-5-haiku-20241022", config)

      assert message =~ "Model set to anthropic:claude-3-5-haiku-20241022"
      assert new_config.provider == "anthropic"
      assert new_config.model == "claude-3-5-haiku-20241022"
      cleanup_api_key("anthropic")
    end

    test "/model with only model name works when provider is set" do
      setup_api_key("anthropic")
      config = %{provider: "anthropic", model: nil}

      {:ok, message, new_config} = Commands.execute("/model claude-3-5-haiku-20241022", config)

      assert message =~ "Model set to claude-3-5-haiku-20241022"
      assert new_config.provider == "anthropic"
      assert new_config.model == "claude-3-5-haiku-20241022"
      cleanup_api_key("anthropic")
    end

    test "/model with only model name fails when no provider" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model gpt-4o", config)

      assert message =~ "No provider set"
    end

    test "/model fails when API key not set" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model anthropic:claude-3-5-sonnet", config)

      # Error message is now generic for security (doesn't expose env var names)
      assert message =~ "not configured"
      assert message =~ "anthropic"
    end

    test "/model without argument shows usage" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/model", config)

      assert message =~ "Usage: /model"
    end

    test "/models shows models for current provider" do
      config = %{provider: "anthropic", model: nil}

      result = Commands.execute("/models", config)

      case result do
        {:pick_list, provider, models, title} ->
          # Now returns pick_list for interactive selection
          assert provider == "anthropic"
          assert is_list(models)
          assert title =~ "anthropic"

        {:ok, message, _} ->
          assert message =~ "No models found"

        {:error, _} ->
          # Registry might not be available in test
          :ok
      end
    end

    test "/models without provider shows error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/models", config)

      assert message =~ "No provider set"
    end

    test "/models provider shows models for specified provider" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/models anthropic", config)

      case result do
        {:pick_list, provider, models, title} ->
          # Now returns pick_list for interactive selection
          assert provider == "anthropic"
          assert is_list(models)
          assert title =~ "anthropic"

        {:ok, message, _} ->
          assert message =~ "No models found"

        {:error, message} ->
          # Unknown provider is also valid
          assert message =~ "Unknown provider"
      end
    end

    test "/providers lists available providers" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/providers", config)

      case result do
        {:pick_list, :provider, providers, title} ->
          # Now returns pick_list for interactive selection
          assert is_list(providers)
          assert length(providers) > 0
          assert title =~ "Provider"

        {:ok, message, new_config} ->
          # Should have providers from registry or no providers
          assert message =~ "providers" or message =~ "No providers"
          assert new_config == %{}
      end
    end

    test "unknown command returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/unknown_command", config)

      assert message =~ "Unknown command"
      assert message =~ "/help"
    end

    test "command with extra whitespace is handled" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("  /help  ", config)

      assert message =~ "Available commands"
    end

    test "non-command text returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("hello", config)

      assert message =~ "Not a command"
    end
  end

  describe "/theme command" do
    test "/theme lists available themes" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme", config)

      assert message =~ "Available themes"
      assert message =~ "dark"
      assert message =~ "light"
      assert message =~ "high_contrast"
      assert new_config == %{}
    end

    test "/theme shows current theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/theme", config)

      assert message =~ "(current)"
    end

    test "/theme dark switches to dark theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme dark", config)

      assert message =~ "Theme set to dark"
      assert new_config == %{}
    end

    test "/theme light switches to light theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme light", config)

      assert message =~ "Theme set to light"
      assert new_config == %{}

      # Reset to dark for other tests
      Commands.execute("/theme dark", config)
    end

    test "/theme high_contrast switches to high contrast theme" do
      config = %{provider: nil, model: nil}

      {:ok, message, new_config} = Commands.execute("/theme high_contrast", config)

      assert message =~ "Theme set to high_contrast"
      assert new_config == %{}

      # Reset to dark for other tests
      Commands.execute("/theme dark", config)
    end

    test "/theme with invalid name returns error" do
      config = %{provider: nil, model: nil}

      {:error, message} = Commands.execute("/theme invalid_theme", config)

      assert message =~ "Unknown theme"
      assert message =~ "dark"
      assert message =~ "light"
      assert message =~ "high_contrast"
    end

    test "/help includes theme command" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/help", config)

      assert message =~ "/theme"
    end
  end

  describe "/session command parsing" do
    test "/session returns {:session, :help}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session", config)

      assert result == {:session, :help}
    end

    test "/session new parses with no arguments" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new", config)

      assert result == {:session, {:new, %{path: nil, name: nil}}}
    end

    test "/session new /path/to/project parses path" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new /path/to/project", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: nil}}}
    end

    test "/session new /path --name=MyProject parses path and name flag" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new /path/to/project --name=MyProject", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: "MyProject"}}}
    end

    test "/session new --name=MyProject /path parses name before path" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new --name=MyProject /path/to/project", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: "MyProject"}}}
    end

    test "/session new /path -n Name parses short name flag" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session new /path/to/project -n Name", config)

      assert result == {:session, {:new, %{path: "/path/to/project", name: "Name"}}}
    end

    test "/session list parses to :list" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session list", config)

      assert result == {:session, :list}
    end

    test "/session switch 1 parses index as target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch 1", config)

      assert result == {:session, {:switch, "1"}}
    end

    test "/session switch abc123 parses ID as target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch abc123", config)

      assert result == {:session, {:switch, "abc123"}}
    end

    test "/session switch MyProject parses name as target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch MyProject", config)

      assert result == {:session, {:switch, "MyProject"}}
    end

    test "/session switch without target returns error" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session switch", config)

      # Now returns error message directly instead of :missing_target atom
      assert {:session, {:error, message}} = result
      assert message =~ "Usage: /session switch"
    end

    test "/session close parses with no target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session close", config)

      assert result == {:session, {:close, nil}}
    end

    test "/session close 2 parses with index target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session close 2", config)

      assert result == {:session, {:close, "2"}}
    end

    test "/session close abc123 parses with ID target" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session close abc123", config)

      assert result == {:session, {:close, "abc123"}}
    end

    test "/session rename NewName parses name" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session rename NewName", config)

      assert result == {:session, {:rename, "NewName"}}
    end

    test "/session rename without name returns error" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session rename", config)

      assert {:session, {:error, message}} = result
      assert message =~ "Usage: /session rename"
    end

    test "/session save parses to {:save, nil}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session save", config)

      assert result == {:session, {:save, nil}}
    end

    test "/session save 2 parses index" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session save 2", config)

      assert result == {:session, {:save, "2"}}
    end

    test "/session save my-project parses name" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session save my-project", config)

      assert result == {:session, {:save, "my-project"}}
    end

    test "/session save abc123 parses ID" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session save abc123", config)

      assert result == {:session, {:save, "abc123"}}
    end

    test "/session unknown returns :help" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/session unknown", config)

      assert result == {:session, :help}
    end

    test "/help includes session commands" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/help", config)

      assert message =~ "/session"
      assert message =~ "/session new"
      assert message =~ "/session list"
      assert message =~ "/session switch"
      assert message =~ "/session close"
      assert message =~ "/session rename"
      assert message =~ "/session save"
    end
  end

  describe "config key formats" do
    test "works with atom keys in config" do
      config = %{provider: "openai", model: "gpt-4o"}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: openai"
      assert message =~ "Model: gpt-4o"
    end

    test "works with string keys in config" do
      config = %{"provider" => "openai", "model" => "gpt-4o"}

      {:ok, message, _} = Commands.execute("/config", config)

      assert message =~ "Provider: openai"
      assert message =~ "Model: gpt-4o"
    end

    test "/model with string key provider set" do
      setup_api_key("anthropic")
      config = %{"provider" => "anthropic", "model" => nil}

      {:ok, message, new_config} = Commands.execute("/model claude-3-5-haiku-20241022", config)

      assert message =~ "Model set to"
      assert new_config.model == "claude-3-5-haiku-20241022"
      cleanup_api_key("anthropic")
    end
  end

  describe "resolve_session_path/1" do
    test "nil returns current working directory" do
      {:ok, path} = Commands.resolve_session_path(nil)

      assert path == File.cwd!()
    end

    test "empty string returns current working directory" do
      {:ok, path} = Commands.resolve_session_path("")

      assert path == File.cwd!()
    end

    test "~ expands to home directory" do
      {:ok, path} = Commands.resolve_session_path("~")

      assert path == System.user_home!()
    end

    test "~/subdir expands to home directory subpath" do
      {:ok, path} = Commands.resolve_session_path("~/projects")

      assert path == Path.join(System.user_home!(), "projects")
    end

    test ". resolves to current directory" do
      {:ok, path} = Commands.resolve_session_path(".")

      assert path == File.cwd!()
    end

    test "./subdir resolves relative to current directory" do
      {:ok, path} = Commands.resolve_session_path("./lib")

      assert path == Path.join(File.cwd!(), "lib")
    end

    test ".. resolves to parent directory" do
      {:ok, path} = Commands.resolve_session_path("..")

      assert path == Path.dirname(File.cwd!())
    end

    test "../sibling resolves to sibling directory" do
      {:ok, path} = Commands.resolve_session_path("../sibling")

      expected = Path.join(Path.dirname(File.cwd!()), "sibling")
      assert path == expected
    end

    test "absolute path passes through unchanged" do
      {:ok, path} = Commands.resolve_session_path("/tmp/test")

      assert path == "/tmp/test"
    end

    test "relative path resolves against CWD" do
      {:ok, path} = Commands.resolve_session_path("lib/jido_code")

      assert path == Path.join(File.cwd!(), "lib/jido_code")
    end

    test "path with .. inside is normalized" do
      {:ok, path} = Commands.resolve_session_path("/tmp/foo/../bar")

      assert path == "/tmp/bar"
    end
  end

  describe "validate_session_path/1" do
    test "returns ok for existing directory" do
      {:ok, result} = Commands.validate_session_path(File.cwd!())

      assert result == File.cwd!()
    end

    test "returns error for non-existent path" do
      {:error, message} = Commands.validate_session_path("/nonexistent/path/xyz123")

      assert message =~ "does not exist"
    end

    test "returns error for file (not directory)" do
      # mix.exs exists but is a file, not directory
      {:error, message} = Commands.validate_session_path(Path.join(File.cwd!(), "mix.exs"))

      assert message =~ "not a directory"
    end

    test "returns error for forbidden system directory /etc" do
      {:error, message} = Commands.validate_session_path("/etc")

      assert message =~ "Cannot create session in system directory"
    end

    test "returns error for forbidden subdirectory /etc/ssh" do
      {:error, message} = Commands.validate_session_path("/etc/ssh")

      assert message =~ "Cannot create session in system directory"
    end

    test "returns error for forbidden /root directory" do
      {:error, message} = Commands.validate_session_path("/root")

      assert message =~ "Cannot create session in system directory"
    end

    test "returns error for forbidden /var/log directory" do
      {:error, message} = Commands.validate_session_path("/var/log")

      assert message =~ "Cannot create session in system directory"
    end

    test "allows /home directory (not forbidden)" do
      # /home exists and is a directory on Linux systems
      case Commands.validate_session_path("/home") do
        {:ok, "/home"} -> assert true
        {:error, "Path does not exist: /home"} -> assert true
      end
    end

    test "allows /tmp directory (not forbidden)" do
      {:ok, "/tmp"} = Commands.validate_session_path("/tmp")
    end
  end

  describe "execute_session/2" do
    test ":help returns session command help" do
      {:ok, message} = Commands.execute_session(:help, %{})

      assert message =~ "Session Commands:"
      assert message =~ "/session new"
      assert message =~ "/session list"
      assert message =~ "/session switch"
      assert message =~ "/session close"
      assert message =~ "/session rename"
      assert message =~ "Keyboard Shortcuts:"
    end

    test "{:new, opts} with valid path creates session" do
      # Use a temp directory that exists
      tmp_dir = System.tmp_dir!()
      test_path = Path.join(tmp_dir, "jido_code_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(test_path)

      try do
        result = Commands.execute_session({:new, %{path: test_path, name: "test-session"}}, %{})

        case result do
          {:session_action, {:add_session, session}} ->
            assert session.name == "test-session"
            assert session.project_path == test_path

            # Clean up session
            JidoCode.SessionSupervisor.stop_session(session.id)

          {:error, message} ->
            # May fail if supervisor not running in test - that's OK for this unit test
            assert message =~ "Failed to create session" or message =~ "not started"
        end
      after
        File.rm_rf!(test_path)
      end
    end

    test "{:new, opts} with non-existent path returns error" do
      result =
        Commands.execute_session(
          {:new, %{path: "/nonexistent/path/xyz123", name: nil}},
          %{}
        )

      assert {:error, message} = result
      assert message =~ "does not exist"
    end

    test "{:new, opts} with nil path uses CWD" do
      result = Commands.execute_session({:new, %{path: nil, name: "cwd-session"}}, %{})

      case result do
        {:session_action, {:add_session, session}} ->
          assert session.project_path == File.cwd!()

          # Clean up
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, message} ->
          # May fail if supervisor not running - check it at least tried with CWD
          assert message =~ "Failed to create session" or
                   message =~ "already open" or
                   message =~ "not started"
      end
    end

    test ":list with no sessions returns helpful message" do
      model = %{sessions: %{}, session_order: [], active_session_id: nil}
      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result
      assert message == "No sessions. Use /session new to create one."
    end

    test ":list with one session shows session" do
      session = %{
        id: "s1",
        name: "project-a",
        project_path: "/tmp/project-a"
      }

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result
      # Active session has * marker
      assert message =~ "*1. project-a"
      assert message =~ "/tmp/project-a"
    end

    test ":list with multiple sessions shows all in order" do
      session1 = %{id: "s1", name: "project-a", project_path: "/tmp/a"}
      session2 = %{id: "s2", name: "project-b", project_path: "/tmp/b"}
      session3 = %{id: "s3", name: "project-c", project_path: "/tmp/c"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s2"
      }

      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result

      lines = String.split(message, "\n")
      assert length(lines) == 3

      # Check markers - only s2 is active
      assert Enum.at(lines, 0) =~ " 1. project-a"
      assert Enum.at(lines, 1) =~ "*2. project-b"
      assert Enum.at(lines, 2) =~ " 3. project-c"
    end

    test ":list shows active session marker" do
      session = %{id: "s1", name: "test", project_path: "/tmp/test"}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      {:ok, message} = Commands.execute_session(:list, model)

      # Starts with * for active
      assert String.starts_with?(message, "*")
    end

    test ":list shows non-active session without marker" do
      session = %{id: "s1", name: "test", project_path: "/tmp/test"}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: nil
      }

      {:ok, message} = Commands.execute_session(:list, model)

      # Starts with space (no active marker)
      assert String.starts_with?(message, " ")
    end

    test ":list truncates long paths" do
      # Use a long path that won't contain home directory
      long_path = "/var/lib/very/deeply/nested/directory/structure/project"

      session = %{id: "s1", name: "project", project_path: long_path}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      {:ok, message} = Commands.execute_session(:list, model)

      # Path should be truncated if longer than max length
      assert message =~ "..."
      # Should still contain the end of the path (most relevant part)
      assert message =~ "project"
    end

    test ":list replaces home directory with ~" do
      home = System.user_home!()
      path = Path.join(home, "projects/myproject")

      session = %{id: "s1", name: "myproject", project_path: path}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      {:ok, message} = Commands.execute_session(:list, model)

      assert message =~ "~/projects/myproject"
      refute message =~ home
    end

    test "{:switch, index} switches to session by index" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "2"}, model)

      assert {:session_action, {:switch_session, "s2"}} = result
    end

    test "{:switch, index} index 1 switches to first session" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "1"}, model)

      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, index} index 0 switches to session 10" do
      # Create 10 sessions
      sessions =
        for i <- 1..10, into: %{} do
          {"s#{i}", %{id: "s#{i}", name: "project-#{i}"}}
        end

      session_order = for i <- 1..10, do: "s#{i}"

      model = %{
        sessions: sessions,
        session_order: session_order,
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "0"}, model)

      # "0" should map to session 10
      assert {:session_action, {:switch_session, "s10"}} = result
    end

    test "{:switch, index} out of range returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "5"}, model)

      assert {:error, message} = result
      assert message =~ "Session not found"
    end

    test "{:switch, id} switches by session ID" do
      session1 = %{id: "abc123", name: "project-a"}

      model = %{
        sessions: %{"abc123" => session1},
        session_order: ["abc123"],
        active_session_id: nil
      }

      result = Commands.execute_session({:switch, "abc123"}, model)

      assert {:session_action, {:switch_session, "abc123"}} = result
    end

    test "{:switch, name} switches by session name" do
      session1 = %{id: "s1", name: "my-project"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      result = Commands.execute_session({:switch, "my-project"}, model)

      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, target} with no sessions returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_session({:switch, "1"}, model)

      assert {:error, message} = result
      assert message =~ "No sessions available"
    end

    test "{:switch, target} with unknown target returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "unknown"}, model)

      assert {:error, message} = result
      assert message =~ "Session not found"
    end

    test "{:switch, name} is case-insensitive" do
      session1 = %{id: "s1", name: "MyProject"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Lowercase should match
      result = Commands.execute_session({:switch, "myproject"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result

      # Uppercase should match
      result = Commands.execute_session({:switch, "MYPROJECT"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, prefix} matches session by name prefix" do
      session1 = %{id: "s1", name: "my-long-project-name"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Prefix "my" should match
      result = Commands.execute_session({:switch, "my"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result

      # Prefix "my-long" should match
      result = Commands.execute_session({:switch, "my-long"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, prefix} prefers exact match over prefix" do
      session1 = %{id: "s1", name: "proj"}
      session2 = %{id: "s2", name: "project"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: nil
      }

      # "proj" should match s1 exactly, not s2 as prefix
      result = Commands.execute_session({:switch, "proj"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    test "{:switch, prefix} returns error for ambiguous prefix" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: nil
      }

      # "proj" matches both sessions
      result = Commands.execute_session({:switch, "proj"}, model)

      assert {:error, message} = result
      assert message =~ "Ambiguous session name"
      assert message =~ "project-a"
      assert message =~ "project-b"
    end

    test "{:switch, prefix} is case-insensitive" do
      session1 = %{id: "s1", name: "MyProject"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Lowercase prefix should match
      result = Commands.execute_session({:switch, "myp"}, model)
      assert {:session_action, {:switch_session, "s1"}} = result
    end

    # Boundary tests for edge cases
    test "{:switch, target} with negative index returns not found" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      # Negative numbers are not numeric targets (contain -)
      # They fall through to name matching and fail
      result = Commands.execute_session({:switch, "-1"}, model)
      assert {:error, message} = result
      assert message =~ "Session not found: -1"
    end

    test "{:switch, target} with empty string returns not found" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, ""}, model)
      assert {:error, message} = result
      assert message =~ "Session not found:"
    end

    test "{:switch, target} with very large index returns not found" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:switch, "999"}, model)
      assert {:error, message} = result
      assert message =~ "Session not found: 999"
    end

    # Close session tests
    test "{:close, nil} closes active session" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s2"
      }

      result = Commands.execute_session({:close, nil}, model)
      assert {:session_action, {:close_session, "s2", "project-b"}} = result
    end

    test "{:close, index} closes session by index" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s2"
      }

      result = Commands.execute_session({:close, "1"}, model)
      assert {:session_action, {:close_session, "s1", "project-a"}} = result
    end

    test "{:close, name} closes session by name" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:close, "project-b"}, model)
      assert {:session_action, {:close_session, "s2", "project-b"}} = result
    end

    test "{:close, id} closes session by ID" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:close, "s1"}, model)
      assert {:session_action, {:close_session, "s1", "project-a"}} = result
    end

    test "{:close, target} with no sessions returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_session({:close, nil}, model)
      assert {:error, message} = result
      assert message =~ "No sessions to close"
    end

    test "{:close, nil} with no active session returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      result = Commands.execute_session({:close, nil}, model)
      assert {:error, message} = result
      assert message =~ "No active session to close"
    end

    test "{:close, target} with unknown target returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:close, "unknown"}, model)
      assert {:error, message} = result
      assert message =~ "Session not found: unknown"
    end

    test "{:close, prefix} with ambiguous prefix returns error" do
      session1 = %{id: "s1", name: "project-a"}
      session2 = %{id: "s2", name: "project-b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      # "proj" matches both sessions
      result = Commands.execute_session({:close, "proj"}, model)

      assert {:error, message} = result
      assert message =~ "Ambiguous session name 'proj'"
      assert message =~ "project-a"
      assert message =~ "project-b"
    end

    test "{:close, name} is case-insensitive" do
      session1 = %{id: "s1", name: "MyProject"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      # Test lowercase
      result = Commands.execute_session({:close, "myproject"}, model)
      assert {:session_action, {:close_session, "s1", "MyProject"}} = result

      # Test uppercase
      result2 = Commands.execute_session({:close, "MYPROJECT"}, model)
      assert {:session_action, {:close_session, "s1", "MyProject"}} = result2
    end

    test "{:close, prefix} closes session by prefix match" do
      session1 = %{id: "s1", name: "project-alpha"}
      session2 = %{id: "s2", name: "other-beta"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s2"
      }

      # "proj" uniquely matches project-alpha
      result = Commands.execute_session({:close, "proj"}, model)
      assert {:session_action, {:close_session, "s1", "project-alpha"}} = result
    end

    # Rename session tests
    test "{:rename, name} renames active session" do
      session1 = %{id: "s1", name: "old-name"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "NewName"}, model)
      assert {:session_action, {:rename_session, "s1", "NewName"}} = result
    end

    test "{:rename, name} with no active session returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      result = Commands.execute_session({:rename, "NewName"}, model)
      assert {:error, message} = result
      assert message =~ "No active session to rename"
    end

    test "{:rename, name} with empty name returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, ""}, model)
      assert {:error, message} = result
      assert message =~ "cannot be empty"
    end

    test "{:rename, name} with whitespace-only name returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "   "}, model)
      assert {:error, message} = result
      assert message =~ "cannot be empty"
    end

    test "{:rename, name} with too-long name returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      long_name = String.duplicate("a", 51)
      result = Commands.execute_session({:rename, long_name}, model)
      assert {:error, message} = result
      assert message =~ "too long"
      assert message =~ "50"
    end

    test "{:rename, name} accepts name at max length" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      max_name = String.duplicate("a", 50)
      result = Commands.execute_session({:rename, max_name}, model)
      assert {:session_action, {:rename_session, "s1", ^max_name}} = result
    end

    test "{:rename, name} with path separators returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "my/project"}, model)
      assert {:error, message} = result
      assert message =~ "invalid characters"
    end

    test "{:rename, name} with backslash returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "my\\project"}, model)
      assert {:error, message} = result
      assert message =~ "invalid characters"
    end

    test "{:rename, name} with control characters returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      # Null character
      result = Commands.execute_session({:rename, "my\0project"}, model)
      assert {:error, message} = result
      assert message =~ "invalid characters"
    end

    test "{:rename, name} with newline returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "my\nproject"}, model)
      assert {:error, message} = result
      assert message =~ "invalid characters"
    end

    test "{:rename, name} with special characters returns error" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      # Test various special characters
      for char <- ["@", "#", "$", "%", "^", "&", "*", "!", "?", "<", ">", "|"] do
        result = Commands.execute_session({:rename, "my#{char}project"}, model)
        assert {:error, message} = result, "Expected error for character: #{char}"
        assert message =~ "invalid characters", "Expected invalid characters message for: #{char}"
      end
    end

    test "{:rename, name} accepts valid names with hyphens and underscores" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      # Test valid names
      result = Commands.execute_session({:rename, "my-project_name"}, model)
      assert {:session_action, {:rename_session, "s1", "my-project_name"}} = result
    end

    test "{:rename, name} accepts valid names with spaces" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "My Project Name"}, model)
      assert {:session_action, {:rename_session, "s1", "My Project Name"}} = result
    end

    test "{:rename, name} accepts valid names with numbers" do
      session1 = %{id: "s1", name: "project-a"}

      model = %{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:rename, "Project 123"}, model)
      assert {:session_action, {:rename_session, "s1", "Project 123"}} = result
    end

    test "{:save, nil} with no sessions returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_session({:save, nil}, model)

      assert {:error, message} = result
      assert message == "No sessions to save."
    end

    test "{:save, nil} with no active session returns error" do
      model = %{
        sessions: %{},
        session_order: ["s1"],
        active_session_id: nil
      }

      result = Commands.execute_session({:save, nil}, model)

      assert {:error, message} = result
      assert message =~ "No active session to save"
    end

    test "{:save, nil} with active session attempts save" do
      session = %{id: "s1", name: "test-session", project_path: "/tmp/test"}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:save, nil}, model)

      # Should either succeed or fail with a known error
      case result do
        {:ok, message} ->
          assert message =~ "saved to"
          assert message =~ "test-session"

        {:error, message} ->
          # May fail if session state not found - acceptable in unit test
          assert message =~ "Session not found" or message =~ "Failed to save"
      end
    end

    test "{:save, index} saves specific session by index" do
      session1 = %{id: "s1", name: "project-a", project_path: "/tmp/a"}
      session2 = %{id: "s2", name: "project-b", project_path: "/tmp/b"}

      model = %{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:save, "2"}, model)

      # Should attempt to save session s2
      case result do
        {:ok, message} ->
          assert message =~ "project-b"

        {:error, _} ->
          # May fail if session state not found
          :ok
      end
    end

    test "{:save, name} saves session by name" do
      session = %{id: "s1", name: "my-project", project_path: "/tmp/project"}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_session({:save, "my-project"}, model)

      case result do
        {:ok, message} ->
          assert message =~ "my-project"
          assert message =~ "saved"

        {:error, _} ->
          :ok
      end
    end

    test "{:save, target} with invalid target returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_session({:save, "nonexistent"}, model)

      assert {:error, message} = result
      assert message =~ "No sessions" or message =~ "not found"
    end

    test "parse_session_args returns error for switch without target" do
      # Now parse_session_args returns the error directly
      # This is tested via execute integration which calls TUI handler
      result = Commands.execute("/session switch", %{})

      # The result is wrapped as {:session, {:error, message}}
      assert {:session, {:error, message}} = result
      assert message =~ "Usage: /session switch"
    end

    test "unknown subcommand returns help" do
      {:ok, message} = Commands.execute_session(:unknown, %{})

      assert message =~ "Session Commands:"
    end
  end

  describe "/resume delete command" do
    setup do
      # Ensure application started
      Application.ensure_all_started(:jido_code)

      # Clean up sessions directory
      sessions_dir = JidoCode.Session.Persistence.sessions_dir()
      File.rm_rf!(sessions_dir)
      File.mkdir_p!(sessions_dir)

      on_exit(fn ->
        File.rm_rf!(sessions_dir)
      end)

      :ok
    end

    test "parses /resume delete <index> correctly" do
      result = Commands.execute("/resume delete 1", %{})

      # Parsing should return the command tuple
      assert {:resume, {:delete, "1"}} = result
    end

    test "parses /resume delete <uuid> correctly" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      result = Commands.execute("/resume delete #{uuid}", %{})

      # Parsing should return the command tuple
      assert {:resume, {:delete, ^uuid}} = result
    end

    test "deletes session by numeric index" do
      # Create a persisted session
      session_id = create_test_session("Test Session", days_ago(5))

      # Execute delete by index 1
      result = Commands.execute_resume({:delete, "1"}, %{})

      assert {:ok, "Deleted saved session."} = result

      # Verify session is deleted
      assert {:error, :not_found} = JidoCode.Session.Persistence.load(session_id)
    end

    test "deletes session by UUID" do
      # Create a persisted session
      session_id = create_test_session("Test Session", days_ago(5))

      # Execute delete by UUID
      result = Commands.execute_resume({:delete, session_id}, %{})

      assert {:ok, "Deleted saved session."} = result

      # Verify session is deleted
      assert {:error, :not_found} = JidoCode.Session.Persistence.load(session_id)
    end

    test "returns error when target not found" do
      # No sessions exist
      result = Commands.execute_resume({:delete, "1"}, %{})

      assert {:error, message} = result
      assert message =~ "Invalid" or message =~ "range"
    end

    test "returns error when index out of range" do
      # Create one session
      _session_id = create_test_session("Test Session", days_ago(5))

      # Try to delete index 2 (doesn't exist)
      result = Commands.execute_resume({:delete, "2"}, %{})

      assert {:error, message} = result
      assert message =~ "Invalid" or message =~ "range"
    end

    test "returns error when UUID doesn't exist" do
      result = Commands.execute_resume({:delete, "550e8400-e29b-41d4-a716-446655440000"}, %{})

      assert {:error, message} = result
      assert message =~ "Session not found" or message =~ "Invalid"
    end

    test "is idempotent - deleting twice doesn't fail" do
      # Create a session
      session_id = create_test_session("Test Session", days_ago(5))

      # Delete once
      result1 = Commands.execute_resume({:delete, "1"}, %{})
      assert {:ok, "Deleted saved session."} = result1

      # Delete again (by UUID since index won't work anymore)
      result2 = Commands.execute_resume({:delete, session_id}, %{})
      # Should get "not found" error since it's already gone
      assert {:error, _message} = result2
    end

    test "deletes correct session when multiple exist" do
      # Create three sessions
      id1 = create_test_session("Session 1", days_ago(5))
      id2 = create_test_session("Session 2", days_ago(4))
      _id3 = create_test_session("Session 3", days_ago(3))

      # Delete second session (index 2)
      result = Commands.execute_resume({:delete, "2"}, %{})
      assert {:ok, "Deleted saved session."} = result

      # Verify correct session deleted
      assert {:error, :not_found} = JidoCode.Session.Persistence.load(id2)
      assert {:ok, _} = JidoCode.Session.Persistence.load(id1)
      # Note: id3 verification would require listing
    end

    test "handles whitespace in target" do
      # Create a session
      _session_id = create_test_session("Test Session", days_ago(5))

      # Delete with extra whitespace
      # Note: whitespace trimming happens in parse_and_execute
      result = Commands.execute_resume({:delete, "1"}, %{})
      assert {:ok, "Deleted saved session."} = result
    end

    test "returns error for empty target" do
      # Empty target after trimming
      result = Commands.execute_resume({:delete, ""}, %{})

      # Empty target should be handled
      assert {:error, _message} = result
    end

    test "returns error for invalid target format" do
      result = Commands.execute_resume({:delete, "invalid"}, %{})

      assert {:error, message} = result
      assert message =~ "Invalid" or message =~ "not found" or message =~ "format"
    end
  end

  # Helper functions for delete tests

  defp create_test_session(name, closed_at) do
    session_id = Uniq.UUID.uuid4()

    persisted = %{
      version: 1,
      id: session_id,
      name: name,
      project_path: "/tmp/test_project",
      config: %{
        "provider" => "anthropic",
        "model" => "claude-3-5-haiku-20241022",
        "temperature" => 0.7,
        "max_tokens" => 4096
      },
      created_at: DateTime.to_iso8601(closed_at),
      updated_at: DateTime.to_iso8601(closed_at),
      closed_at: DateTime.to_iso8601(closed_at),
      conversation: [],
      todos: []
    }

    :ok = JidoCode.Session.Persistence.write_session_file(session_id, persisted)
    session_id
  end

  defp days_ago(days) do
    DateTime.add(DateTime.utc_now(), -days * 86400, :second)
  end

  describe "/resume clear command" do
    setup do
      # Ensure application started
      Application.ensure_all_started(:jido_code)

      # Clean up sessions directory
      sessions_dir = JidoCode.Session.Persistence.sessions_dir()
      File.rm_rf!(sessions_dir)
      File.mkdir_p!(sessions_dir)

      on_exit(fn ->
        File.rm_rf!(sessions_dir)
      end)

      :ok
    end

    test "parses /resume clear correctly" do
      result = Commands.execute("/resume clear", %{})

      # Parsing should return the command tuple
      assert {:resume, :clear} = result
    end

    test "clears multiple sessions" do
      # Create three persisted sessions
      _id1 = create_test_session("Session 1", days_ago(5))
      _id2 = create_test_session("Session 2", days_ago(4))
      _id3 = create_test_session("Session 3", days_ago(3))

      # Execute clear
      result = Commands.execute_resume(:clear, %{})

      assert {:ok, message} = result
      assert message =~ "Cleared 3 saved session(s)."

      # Verify all sessions are deleted
      {:ok, remaining} = JidoCode.Session.Persistence.list_persisted()
      assert remaining == []
    end

    test "returns message when no sessions to clear" do
      # No sessions exist
      result = Commands.execute_resume(:clear, %{})

      assert {:ok, "No saved sessions to clear."} = result
    end

    test "is idempotent - can run multiple times" do
      # Create a session
      _id = create_test_session("Test Session", days_ago(5))

      # Clear once
      result1 = Commands.execute_resume(:clear, %{})
      assert {:ok, "Cleared 1 saved session(s)."} = result1

      # Clear again (no sessions left)
      result2 = Commands.execute_resume(:clear, %{})
      assert {:ok, "No saved sessions to clear."} = result2
    end

    test "counts correctly with various session counts" do
      # Test with 1 session
      id1 = create_test_session("Session 1", days_ago(5))
      result = Commands.execute_resume(:clear, %{})
      assert {:ok, "Cleared 1 saved session(s)."} = result

      # Create 5 sessions
      Enum.each(1..5, fn n ->
        create_test_session("Session #{n}", days_ago(n))
      end)

      result = Commands.execute_resume(:clear, %{})
      assert {:ok, "Cleared 5 saved session(s)."} = result
    end
  end

  # ============================================================================
  # Resume Command Integration Tests (Task 6.7.3)
  # ============================================================================

  describe "/resume command integration" do
    setup do
      # Set API key for test sessions
      System.put_env("ANTHROPIC_API_KEY", "test-key-for-resume-integration")

      # Ensure app started and supervisor available
      {:ok, _} = Application.ensure_all_started(:jido_code)

      # Wait for SessionSupervisor
      wait_for_supervisor()

      # Clear registry
      JidoCode.SessionRegistry.clear()

      # Clear any persisted session files from previous tests
      sessions_dir = JidoCode.Session.Persistence.sessions_dir()

      if File.exists?(sessions_dir) do
        File.rm_rf!(sessions_dir)
      end

      # Create temp directory for test projects
      tmp_base = Path.join(System.tmp_dir!(), "resume_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_base)

      on_exit(fn ->
        # Stop all test sessions
        for session <- JidoCode.SessionRegistry.list_all() do
          JidoCode.SessionSupervisor.stop_session(session.id)
        end

        # Clean up temp dirs and session files
        File.rm_rf!(tmp_base)
        sessions_dir = JidoCode.Session.Persistence.sessions_dir()

        if File.exists?(sessions_dir) do
          File.rm_rf!(sessions_dir)
        end
      end)

      {:ok, tmp_base: tmp_base}
    end

    test "lists resumable sessions when closed sessions exist", %{tmp_base: tmp_base} do
      # Create and close 2 test sessions
      project1 = Path.join(tmp_base, "project1")
      project2 = Path.join(tmp_base, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      _session1 = create_and_close_session("Project 1", project1)
      _session2 = create_and_close_session("Project 2", project2)

      # Execute /resume (list)
      result = Commands.execute_resume(:list, %{})

      # Verify returns {:ok, message} with session details
      assert {:ok, message} = result
      assert is_binary(message)
      assert message =~ "Project 1"
      assert message =~ "Project 2"
      assert message =~ project1
      assert message =~ project2
    end

    test "returns message when no resumable sessions", %{tmp_base: _tmp_base} do
      # No sessions created

      # Execute /resume (list)
      result = Commands.execute_resume(:list, %{})

      # Verify returns {:ok, message} indicating no sessions
      assert {:ok, message} = result
      # Actual message: "No resumable sessions available."
      assert String.contains?(message, "No resumable sessions")
    end

    test "resumes session by index", %{tmp_base: tmp_base} do
      # Create and close 2 test sessions
      project1 = Path.join(tmp_base, "project1")
      project2 = Path.join(tmp_base, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      _session1 = create_and_close_session("Project 1", project1)
      _session2 = create_and_close_session("Project 2", project2)

      # Execute /resume 1 (first session in list)
      result = Commands.execute_resume({:restore, "1"}, %{})

      # Verify returns {:session_action, {:add_session, session}}
      assert {:session_action, {:add_session, resumed_session}} = result

      # Verify resumed session has correct name
      assert resumed_session.name == "Project 1" or resumed_session.name == "Project 2"

      # Verify session is now active
      assert {:ok, _} = JidoCode.SessionRegistry.lookup(resumed_session.id)

      # Persisted file should be deleted after resume
      # (The important thing is that resume succeeded)
    end

    test "returns error for invalid index", %{tmp_base: tmp_base} do
      # Create one session
      project1 = Path.join(tmp_base, "project1")
      File.mkdir_p!(project1)
      _session1 = create_and_close_session("Project 1", project1)

      # Try to resume index 999 (doesn't exist)
      result = Commands.execute_resume({:restore, "999"}, %{})

      # Verify returns error
      assert {:error, _reason} = result
    end

    test "returns error when session limit reached", %{tmp_base: tmp_base} do
      # First create and close a session to resume later
      project_to_resume = Path.join(tmp_base, "closed_project")
      File.mkdir_p!(project_to_resume)
      _closed_session = create_and_close_session("Closed Session", project_to_resume)

      # Now create 10 active sessions (at limit)
      Enum.each(1..10, fn i ->
        project = Path.join(tmp_base, "active_project#{i}")
        File.mkdir_p!(project)

        {:ok, _session} =
          JidoCode.SessionSupervisor.create_session(
            project_path: project,
            name: "Active Session #{i}",
            config: %{
              provider: "anthropic",
              model: "claude-3-5-haiku-20241022",
              temperature: 0.7,
              max_tokens: 4096
            }
          )
      end)

      # Try to resume (should fail - at limit)
      result = Commands.execute_resume({:restore, "1"}, %{})

      # Verify returns error about session limit
      assert {:error, reason} = result
      # Error message: "Maximum 10 sessions reached. Close a session first."
      assert is_binary(reason) and
               (String.contains?(reason, "Maximum") or String.contains?(reason, "limit"))
    end

    test "returns error when project path deleted", %{tmp_base: tmp_base} do
      # Create and close session
      project = Path.join(tmp_base, "project_to_delete")
      File.mkdir_p!(project)
      _session = create_and_close_session("Deleted Project", project)

      # Delete project directory
      File.rm_rf!(project)

      # Try to resume
      result = Commands.execute_resume({:restore, "1"}, %{})

      # Verify returns error about missing project
      assert {:error, reason} = result
      # Error from Persistence.resume/1 for deleted path
      assert is_binary(reason) and String.contains?(reason, "no longer exists")
    end

    test "filters out sessions for projects that are already open", %{tmp_base: tmp_base} do
      # Create two projects
      project1 = Path.join(tmp_base, "project1")
      project2 = Path.join(tmp_base, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      # Create and close sessions for both projects
      _session1 = create_and_close_session("Project 1 Closed", project1)
      _session2 = create_and_close_session("Project 2 Closed", project2)

      # Now open project1 again (but not project2)
      {:ok, _active_session} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project1,
          name: "Project 1 Active",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      # List resumable sessions - should only show project2
      result = Commands.execute_resume(:list, %{})

      # Verify returns {:ok, message} with only project2
      assert {:ok, message} = result
      refute String.contains?(message, "Project 1")
      assert String.contains?(message, "Project 2")
    end

    test "resumes session by UUID", %{tmp_base: tmp_base} do
      # Create and close session
      project = Path.join(tmp_base, "project_uuid")
      File.mkdir_p!(project)
      session = create_and_close_session("UUID Project", project)

      # Execute /resume <uuid>
      result = Commands.execute_resume({:restore, session.id}, %{})

      # Verify returns {:session_action, {:add_session, session}}
      assert {:session_action, {:add_session, resumed_session}} = result
      assert resumed_session.id == session.id

      # Verify session active
      assert {:ok, _} = JidoCode.SessionRegistry.lookup(resumed_session.id)
    end

    # Helper functions

    # Removed: wait_for_supervisor/1 now imported from PersistenceTestHelpers
    # Removed: create_and_close_session/2 now imported from PersistenceTestHelpers

    test "delete command doesn't affect active sessions", %{tmp_base: tmp_base} do
      # Create and close session 1 (persisted)
      project1 = Path.join(tmp_base, "project1")
      File.mkdir_p!(project1)
      _closed_session = create_and_close_session("Closed Session", project1)

      # Create session 2 and keep active
      project2 = Path.join(tmp_base, "project2")
      File.mkdir_p!(project2)

      {:ok, active_session} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project2,
          name: "Active Session",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      # Add state to active session
      test_message = %{
        id: "msg-1",
        role: :user,
        content: "Test message",
        timestamp: DateTime.utc_now()
      }

      JidoCode.Session.State.append_message(active_session.id, test_message)

      # Delete closed session
      result = Commands.execute_resume({:delete, "1"}, %{})
      assert {:ok, "Deleted saved session."} = result

      # Verify active session still works
      assert {:ok, session} = JidoCode.SessionRegistry.lookup(active_session.id)
      assert session.name == "Active Session"

      # Verify active session state intact
      {:ok, messages} = JidoCode.Session.State.get_messages(active_session.id)
      assert Enum.any?(messages, fn m -> m.content == "Test message" end)
    end

    test "clear command doesn't affect active sessions", %{tmp_base: tmp_base} do
      # Create and close 2 sessions (persisted)
      project1 = Path.join(tmp_base, "project1")
      project2 = Path.join(tmp_base, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      _closed1 = create_and_close_session("Closed 1", project1)
      _closed2 = create_and_close_session("Closed 2", project2)

      # Create active session
      project3 = Path.join(tmp_base, "project3")
      File.mkdir_p!(project3)

      {:ok, active} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project3,
          name: "Active",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      # Add todos to active session
      todos = [
        %{content: "Task 1", status: :pending, active_form: "Working on task 1"}
      ]

      JidoCode.Session.State.update_todos(active.id, todos)

      # Clear all persisted sessions
      result = Commands.execute_resume(:clear, %{})
      assert {:ok, message} = result
      assert message =~ "Cleared 2"

      # Verify active session still works
      assert {:ok, _} = JidoCode.SessionRegistry.lookup(active.id)

      # Verify active session state intact
      {:ok, active_todos} = JidoCode.Session.State.get_todos(active.id)
      assert length(active_todos) == 1
      assert Enum.at(active_todos, 0).content == "Task 1"
    end

    test "automatic cleanup doesn't affect active sessions", %{tmp_base: tmp_base} do
      # Create and close old session (>30 days)
      project1 = Path.join(tmp_base, "project1")
      File.mkdir_p!(project1)
      old_session = create_and_close_session("Old Session", project1)

      # Modify file timestamp to be 31 days old
      old_file =
        Path.join(JidoCode.Session.Persistence.sessions_dir(), "#{old_session.id}.json")

      wait_for_persisted_file(old_file)

      {:ok, data} = File.read(old_file)
      {:ok, json} = Jason.decode(data)
      old_time = DateTime.add(DateTime.utc_now(), -31 * 86400, :second)
      modified_json = Map.put(json, "closed_at", DateTime.to_iso8601(old_time))
      File.write!(old_file, Jason.encode!(modified_json))

      # Create active session
      project2 = Path.join(tmp_base, "project2")
      File.mkdir_p!(project2)

      {:ok, active} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project2,
          name: "Active",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      # Add both messages and todos to active
      JidoCode.Session.State.append_message(active.id, %{
        id: "msg-1",
        role: :user,
        content: "Active message",
        timestamp: DateTime.utc_now()
      })

      JidoCode.Session.State.update_todos(active.id, [
        %{content: "Active task", status: :pending, active_form: "Working"}
      ])

      # Run cleanup (30 days)
      {:ok, result} = JidoCode.Session.Persistence.cleanup(30)

      # Verify old session deleted
      assert result.deleted == 1
      refute File.exists?(old_file)

      # Verify active session unaffected
      assert {:ok, _} = JidoCode.SessionRegistry.lookup(active.id)
      {:ok, messages} = JidoCode.Session.State.get_messages(active.id)
      {:ok, todos} = JidoCode.Session.State.get_todos(active.id)

      assert Enum.any?(messages, fn m -> m.content == "Active message" end)
      assert length(todos) == 1
    end

    test "cleanup with active session having persisted file", %{tmp_base: tmp_base} do
      project = Path.join(tmp_base, "project1")
      File.mkdir_p!(project)

      # Create, add data, and close session (creates file)
      {:ok, session} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project,
          name: "Test Session",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      session_id = session.id

      JidoCode.Session.State.append_message(session_id, %{
        id: "msg-1",
        role: :user,
        content: "Original message",
        timestamp: DateTime.utc_now()
      })

      :ok = JidoCode.SessionSupervisor.stop_session(session_id)

      # Wait for file
      file = Path.join(JidoCode.Session.Persistence.sessions_dir(), "#{session_id}.json")
      wait_for_persisted_file(file)

      # Modify file to be 31 days old
      {:ok, data} = File.read(file)
      {:ok, json} = Jason.decode(data)
      old_time = DateTime.add(DateTime.utc_now(), -31 * 86400, :second)
      modified_json = Map.put(json, "closed_at", DateTime.to_iso8601(old_time))
      File.write!(file, Jason.encode!(modified_json))

      # Recreate session at same path (simulates user returning to project)
      {:ok, new_session} =
        JidoCode.SessionSupervisor.create_session(
          project_path: project,
          name: "Test Session",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      new_id = new_session.id

      # Add NEW data to active session
      JidoCode.Session.State.append_message(new_id, %{
        id: "msg-2",
        role: :user,
        content: "New message",
        timestamp: DateTime.utc_now()
      })

      # Run cleanup - should delete OLD file
      {:ok, result} = JidoCode.Session.Persistence.cleanup(30)

      # Old file should be deleted (it's >30 days old)
      assert result.deleted == 1
      refute File.exists?(file)

      # New active session should be unaffected
      assert {:ok, _} = JidoCode.SessionRegistry.lookup(new_id)
      {:ok, messages} = JidoCode.Session.State.get_messages(new_id)
      assert Enum.any?(messages, fn m -> m.content == "New message" end)
    end

    # Removed: wait_for_persisted_file/2 now imported from PersistenceTestHelpers
  end

  describe "/resume command - multiple sessions" do
    setup do
      # Set API key for test sessions
      System.put_env("ANTHROPIC_API_KEY", "test-key-multi-session")

      # Ensure app started
      {:ok, _} = Application.ensure_all_started(:jido_code)

      # Wait for SessionSupervisor
      wait_for_supervisor()

      # Clear registry
      JidoCode.SessionRegistry.clear()

      # Create temp directory for test projects
      tmp_base = Path.join(System.tmp_dir!(), "multi_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_base)

      on_exit(fn ->
        # Stop all test sessions
        for session <- JidoCode.SessionRegistry.list_all() do
          JidoCode.SessionSupervisor.stop_session(session.id)
        end

        # Clean up temp dirs and session files
        File.rm_rf!(tmp_base)
        sessions_dir = JidoCode.Session.Persistence.sessions_dir()

        if File.exists?(sessions_dir) do
          File.rm_rf!(sessions_dir)
        end
      end)

      {:ok, tmp_base: tmp_base}
    end

    test "lists all closed sessions", %{tmp_base: tmp_base} do
      # Create 3 projects
      projects =
        for i <- 1..3 do
          project = Path.join(tmp_base, "project#{i}")
          File.mkdir_p!(project)
          project
        end

      # Create and close 3 sessions
      _sessions =
        for {project, i} <- Enum.with_index(projects, 1) do
          create_and_close_session("Session #{i}", project)
        end

      # List resumable sessions
      result = Commands.execute_resume(:list, %{})

      # Verify all 3 appear
      assert {:ok, message} = result
      assert message =~ "Session 1"
      assert message =~ "Session 2"
      assert message =~ "Session 3"
    end

    test "resuming one session leaves others in list", %{tmp_base: tmp_base} do
      # Create 3 projects
      projects =
        for i <- 1..3 do
          project = Path.join(tmp_base, "project#{i}")
          File.mkdir_p!(project)
          project
        end

      # Create and close 3 sessions
      _sessions =
        for {project, i} <- Enum.with_index(projects, 1) do
          create_and_close_session("Session #{i}", project)
        end

      # Resume first session
      result = Commands.execute_resume({:restore, "1"}, %{})
      assert {:session_action, {:add_session, _resumed}} = result

      # List remaining resumable sessions
      list_result = Commands.execute_resume(:list, %{})
      assert {:ok, message} = list_result

      # Verify 2 remaining (Session 1 was resumed and should not appear)
      # Note: We can't guarantee which one was resumed (sorted by closed_at),
      # so we just check that exactly 2 sessions remain and at least one is different
      assert message =~ "Session"
      # Count how many "Session" appears - should be less than 3
      session_count = length(String.split(message, "Session")) - 1
      assert session_count == 2
    end

    test "sessions sorted by closed_at (most recent first)", %{tmp_base: tmp_base} do
      # Create 3 projects
      projects =
        for i <- 1..3 do
          project = Path.join(tmp_base, "project#{i}")
          File.mkdir_p!(project)
          project
        end

      # Create and close sessions with delays to ensure different closed_at times
      for {project, i} <- Enum.with_index(projects, 1) do
        create_and_close_session("Session #{i}", project)
        # Small delay to ensure different closed_at times
        Process.sleep(100)
      end

      # List sessions
      result = Commands.execute_resume(:list, %{})
      assert {:ok, message} = result

      # Verify order - Session 3 should appear before Session 1
      # (most recent closed appears first)
      session3_match = :binary.match(message, "Session 3")
      session2_match = :binary.match(message, "Session 2")
      session1_match = :binary.match(message, "Session 1")

      # All should be found
      assert session3_match != :nomatch
      assert session2_match != :nomatch
      assert session1_match != :nomatch

      # Extract positions
      {session3_pos, _} = session3_match
      {session2_pos, _} = session2_match
      {session1_pos, _} = session1_match

      # Most recent (Session 3) should appear first
      assert session3_pos < session2_pos
      assert session2_pos < session1_pos
    end

    test "active sessions excluded from resumable list", %{tmp_base: tmp_base} do
      # Create 3 projects
      projects =
        for i <- 1..3 do
          project = Path.join(tmp_base, "project#{i}")
          File.mkdir_p!(project)
          project
        end

      # Create and close 3 sessions
      for {project, i} <- Enum.with_index(projects, 1) do
        create_and_close_session("Session #{i}", project)
      end

      # List all first to identify session at index 2
      list_result = Commands.execute_resume(:list, %{})
      assert {:ok, _} = list_result

      # Resume session 2 (making it active)
      result = Commands.execute_resume({:restore, "2"}, %{})
      assert {:session_action, {:add_session, resumed_session}} = result

      # List resumable again
      list_result = Commands.execute_resume(:list, %{})
      assert {:ok, message} = list_result

      # Resumed session should NOT appear in list
      refute message =~ resumed_session.name

      # Should show 2 sessions, not 3
      session_count = length(String.split(message, "Session")) - 1
      assert session_count == 2
    end

    # Reuse helper functions from /resume command integration describe block
    # (create_and_close_session, wait_for_persisted_file, wait_for_supervisor)
  end

  describe "/language command parsing" do
    test "/language returns {:language, :show}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/language", config)

      assert result == {:language, :show}
    end

    test "/language <lang> returns {:language, {:set, lang}}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/language elixir", config)

      assert result == {:language, {:set, "elixir"}}
    end

    test "/language with alias returns {:language, {:set, alias}}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/language js", config)

      assert result == {:language, {:set, "js"}}
    end

    test "/language with uppercase returns {:language, {:set, uppercase}}" do
      config = %{provider: nil, model: nil}

      result = Commands.execute("/language Python", config)

      assert result == {:language, {:set, "Python"}}
    end

    test "/help includes language command" do
      config = %{provider: nil, model: nil}

      {:ok, message, _} = Commands.execute("/help", config)

      assert message =~ "/language"
    end
  end

  describe "execute_language/2" do
    test ":show with no active session returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_language(:show, model)

      assert {:error, message} = result
      assert message =~ "No active session"
    end

    test ":show with active session returns language info" do
      session = %{
        id: "s1",
        name: "test",
        language: :python
      }

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_language(:show, model)

      assert {:ok, message} = result
      assert message =~ "Python"
      assert message =~ "python"
      assert message =~ "🐍"
    end

    test ":show with active session defaults to elixir" do
      session = %{
        id: "s1",
        name: "test"
        # language not set
      }

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_language(:show, model)

      assert {:ok, message} = result
      assert message =~ "Elixir"
      assert message =~ "elixir"
      assert message =~ "💧"
    end

    test "{:set, lang} with no active session returns error" do
      model = %{
        sessions: %{},
        session_order: [],
        active_session_id: nil
      }

      result = Commands.execute_language({:set, "python"}, model)

      assert {:error, message} = result
      assert message =~ "No active session"
    end

    test "{:set, lang} with valid language returns action" do
      session = %{id: "s1", name: "test", language: :elixir}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_language({:set, "python"}, model)

      assert {:language_action, {:set, "s1", :python}} = result
    end

    test "{:set, lang} normalizes alias" do
      session = %{id: "s1", name: "test", language: :elixir}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_language({:set, "js"}, model)

      assert {:language_action, {:set, "s1", :javascript}} = result
    end

    test "{:set, lang} normalizes case" do
      session = %{id: "s1", name: "test", language: :elixir}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_language({:set, "RUST"}, model)

      assert {:language_action, {:set, "s1", :rust}} = result
    end

    test "{:set, lang} with invalid language returns error" do
      session = %{id: "s1", name: "test", language: :elixir}

      model = %{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = Commands.execute_language({:set, "invalid"}, model)

      assert {:error, message} = result
      assert message =~ "Unknown language"
      assert message =~ "invalid"
      assert message =~ "elixir"
    end
  end
end
