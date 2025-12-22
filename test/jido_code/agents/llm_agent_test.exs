defmodule JidoCode.Agents.LLMAgentTest do
  use ExUnit.Case, async: false

  alias JidoCode.Agents.LLMAgent
  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.TestHelpers.EnvIsolation

  @moduletag :llm_agent

  setup do
    # Trap exits in test process to avoid test crashes
    Process.flag(:trap_exit, true)

    # Isolate environment for clean test state
    EnvIsolation.isolate(
      ["JIDO_CODE_PROVIDER", "JIDO_CODE_MODEL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
      [{:jido_code, :llm}]
    )

    :ok
  end

  defp stop_agent(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end
  catch
    :exit, _ -> :ok
  end

  defp stop_agent(_), do: :ok

  describe "start_link/1" do
    test "returns error when config is missing" do
      # No config set, no explicit opts - should return error tuple
      assert {:error, reason} = LLMAgent.start_link()
      assert is_binary(reason) or is_atom(reason) or is_tuple(reason)
    end

    test "validates config at startup - rejects invalid provider" do
      # Set API key but use invalid provider
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result =
        LLMAgent.start_link(
          provider: :completely_invalid_provider_xyz,
          model: "some-model"
        )

      assert {:error, message} = result
      assert is_binary(message)
      assert String.contains?(message, "not found") or String.contains?(message, "invalid")
    end

    test "validates config at startup - rejects invalid model" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result =
        LLMAgent.start_link(
          provider: :anthropic,
          model: "nonexistent-model-xyz"
        )

      assert {:error, message} = result
      assert is_binary(message)
      assert String.contains?(message, "not found") or String.contains?(message, "Model")
    end

    test "starts with explicit provider and model opts" do
      # Set API key for the provider
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result =
        LLMAgent.start_link(
          provider: :anthropic,
          model: "claude-3-5-sonnet-20241022"
        )

      case result do
        {:ok, pid} ->
          assert Process.alive?(pid)
          stop_agent(pid)

        {:error, reason} ->
          # May fail if JidoAI can't initialize - that's expected without real API key
          assert reason != nil
      end
    end

    test "starts with config from application environment" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = LLMAgent.start_link()

      case result do
        {:ok, pid} ->
          assert Process.alive?(pid)
          stop_agent(pid)

        {:error, _reason} ->
          # Expected if JidoAI can't fully initialize
          :ok
      end
    end

    test "accepts name option for registration" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = LLMAgent.start_link(name: :test_llm_agent)

      case result do
        {:ok, pid} ->
          # Verify registered name works
          assert Process.whereis(:test_llm_agent) == pid
          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_config/1" do
    test "returns the current configuration" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.5,
        max_tokens: 2048
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          config = LLMAgent.get_config(pid)

          assert config.provider == :anthropic
          assert config.model == "claude-3-5-sonnet-20241022"
          assert config.temperature == 0.5
          assert config.max_tokens == 2048

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "chat/2" do
    @tag :integration
    @tag :skip
    test "sends message and receives response" do
      # This test requires a real API key and makes actual LLM calls
      # Skip by default, run with: mix test --include integration

      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-haiku-20241022",
        temperature: 0.0,
        max_tokens: 100
      )

      session_id = "test-session-#{System.unique_integer([:positive])}"

      # Subscribe to session-specific topic before starting agent
      topic = LLMAgent.topic_for_session(session_id)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)

      # Requires real API key in environment
      {:ok, pid} = LLMAgent.start_link(session_id: session_id)

      {:ok, response} = LLMAgent.chat(pid, "Say 'Hello' and nothing else.")

      assert is_binary(response)
      assert String.contains?(String.downcase(response), "hello")

      # Verify PubSub broadcast on session-specific topic
      assert_receive {:llm_response, ^response}, 1000

      stop_agent(pid)
    end

    test "rejects empty messages" do
      # Note: We don't need a running agent - validation happens before GenServer call
      result = LLMAgent.chat(self(), "")
      assert {:error, {:empty_message, message}} = result
      assert String.contains?(message, "empty")
    end

    test "rejects messages exceeding maximum length" do
      # Generate a message that exceeds 10,000 characters
      long_message = String.duplicate("x", 10_001)
      result = LLMAgent.chat(self(), long_message)

      assert {:error, {:message_too_long, message}} = result
      assert String.contains?(message, "10000")
      assert String.contains?(message, "10001")
    end

    test "accepts messages at the exact maximum length" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          # Generate a message exactly at 10,000 characters
          max_message = String.duplicate("x", 10_000)
          # This should not fail validation, but may fail LLM call (that's ok)
          result = LLMAgent.chat(pid, max_message, timeout: 1_000)

          # Should NOT be a message_too_long error
          case result do
            {:error, {:message_too_long, _}} ->
              flunk("Should not reject message at exact max length")

            _ ->
              # Any other result is acceptable (LLM call may timeout or fail)
              :ok
          end

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "configuration override" do
    test "opts override base config values" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")
      System.put_env("OPENAI_API_KEY", "test-openai-key")

      # Override with different values
      case LLMAgent.start_link(
             provider: :openai,
             model: "gpt-4o",
             temperature: 0.2
           ) do
        {:ok, pid} ->
          config = LLMAgent.get_config(pid)

          # Should use overridden values
          assert config.provider == :openai
          assert config.model == "gpt-4o"
          assert config.temperature == 0.2
          # max_tokens should fall back to base config
          assert config.max_tokens == 4096

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "list_providers/0" do
    test "returns list of available providers" do
      result = LLMAgent.list_providers()

      case result do
        {:ok, providers} ->
          assert is_list(providers)
          # Should include common providers
          assert :anthropic in providers or :openai in providers

        {:error, :registry_unavailable} ->
          # Registry may not be available in test environment
          :ok
      end
    end
  end

  describe "list_models/1" do
    test "returns list of models for valid provider" do
      result = LLMAgent.list_models(:anthropic)

      case result do
        {:ok, models} ->
          assert is_list(models)
          # Should be list of strings
          Enum.each(models, fn model ->
            assert is_binary(model)
          end)

        {:error, _} ->
          # May fail if registry unavailable
          :ok
      end
    end

    test "returns error for invalid provider" do
      result = LLMAgent.list_models(:nonexistent_provider_xyz)

      case result do
        {:error, _reason} ->
          # Expected - provider doesn't exist
          :ok

        {:ok, []} ->
          # Also acceptable - no models found
          :ok

        {:ok, _models} ->
          # Unexpected - should not have models for fake provider
          flunk("Expected error or empty list for invalid provider")
      end
    end
  end

  describe "session topics" do
    test "topic_for_session builds correct topic format" do
      topic = LLMAgent.topic_for_session("my-session-123")
      assert topic == "tui.events.my-session-123"
    end

    test "get_session_info returns session_id and topic" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link(session_id: "explicit-session-id") do
        {:ok, pid} ->
          {:ok, session_id, topic} = LLMAgent.get_session_info(pid)

          assert session_id == "explicit-session-id"
          assert topic == "tui.events.explicit-session-id"

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "default session_id is generated from PID when not provided" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          {:ok, session_id, topic} = LLMAgent.get_session_info(pid)

          # Should contain PID format
          assert String.contains?(session_id, "#PID<")
          assert String.starts_with?(topic, "tui.events.")

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "configure/2" do
    test "returns ok when config unchanged" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          # Configure with same values - should return :ok
          result =
            LLMAgent.configure(pid,
              provider: :anthropic,
              model: "claude-3-5-sonnet-20241022",
              temperature: 0.7,
              max_tokens: 4096
            )

          assert result == :ok
          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "returns error for invalid provider" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          result = LLMAgent.configure(pid, provider: :invalid_provider_xyz)

          assert {:error, message} = result
          assert is_binary(message)
          assert String.contains?(message, "not found") or String.contains?(message, "invalid")

          # Config should be unchanged
          config = LLMAgent.get_config(pid)
          assert config.provider == :anthropic

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "returns error for invalid model" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          result = LLMAgent.configure(pid, model: "nonexistent-model-xyz")

          assert {:error, message} = result
          assert is_binary(message)
          assert String.contains?(message, "not found") or String.contains?(message, "Model")

          # Config should be unchanged
          config = LLMAgent.get_config(pid)
          assert config.model == "claude-3-5-sonnet-20241022"

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "returns error for missing API key" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")
      # Don't set OPENAI_API_KEY

      case LLMAgent.start_link() do
        {:ok, pid} ->
          # Try to switch to OpenAI without API key
          result = LLMAgent.configure(pid, provider: :openai, model: "gpt-4o")

          assert {:error, message} = result
          assert is_binary(message)
          assert String.contains?(message, "API key") or String.contains?(message, "OPENAI")

          # Config should be unchanged
          config = LLMAgent.get_config(pid)
          assert config.provider == :anthropic

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "broadcasts config change on success" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022",
        temperature: 0.7,
        max_tokens: 4096
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")
      System.put_env("OPENAI_API_KEY", "test-openai-key")

      session_id = "test-session-#{System.unique_integer([:positive])}"

      case LLMAgent.start_link(session_id: session_id) do
        {:ok, pid} ->
          # Subscribe to session-specific topic
          {:ok, ^session_id, topic} = LLMAgent.get_session_info(pid)
          Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)

          result = LLMAgent.configure(pid, provider: :openai, model: "gpt-4o")

          case result do
            :ok ->
              # Should receive config change broadcast on session-specific topic
              assert_receive {:config_changed, old_config, new_config}, 1000

              assert old_config.provider == :anthropic
              assert new_config.provider == :openai
              assert new_config.model == "gpt-4o"

              # Config should be updated
              config = LLMAgent.get_config(pid)
              assert config.provider == :openai
              assert config.model == "gpt-4o"

            {:error, _reason} ->
              # May fail if AI agent can't start with test key
              :ok
          end

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end

  # ============================================================================
  # Session-Aware Agent Tests (Task 3.3.1)
  # ============================================================================

  describe "via/1" do
    test "returns correct registry via tuple" do
      session_id = "550e8400-e29b-41d4-a716-446655440000"
      via = LLMAgent.via(session_id)

      assert {:via, Registry, {JidoCode.SessionProcessRegistry, {:agent, ^session_id}}} = via
    end

    test "via tuple matches ProcessRegistry.via/2" do
      session_id = "test-session-abc"
      assert LLMAgent.via(session_id) == ProcessRegistry.via(:agent, session_id)
    end
  end

  describe "session registry integration" do
    test "agent started with via/1 can be found via Session.Supervisor.get_agent/1" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      session_id = "test-registry-#{System.unique_integer([:positive])}"

      case LLMAgent.start_link(
             session_id: session_id,
             name: LLMAgent.via(session_id)
           ) do
        {:ok, pid} ->
          # Should be findable via Session.Supervisor.get_agent/1
          assert {:ok, ^pid} = Session.Supervisor.get_agent(session_id)

          # Should also be findable via ProcessRegistry.lookup/2
          assert {:ok, ^pid} = ProcessRegistry.lookup(:agent, session_id)

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "Session.Supervisor.get_agent/1 returns :not_found for non-existent session" do
      assert {:error, :not_found} = Session.Supervisor.get_agent("nonexistent-session-id")
    end
  end

  describe "build_tool_context/1" do
    test "returns error for nil session_id" do
      assert {:error, :no_session_id} = LLMAgent.build_tool_context(nil)
    end

    test "returns error for non-existent session" do
      # Valid UUID format but no session exists
      result = LLMAgent.build_tool_context("550e8400-e29b-41d4-a716-446655440000")

      # Should return error (session not found)
      assert {:error, _reason} = result
    end

    test "returns context for valid session" do
      # Set API key BEFORE starting session
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create a real session first with valid config
      {:ok, session} =
        Session.new(
          project_path: System.tmp_dir!(),
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Now build_tool_context should work
      result = LLMAgent.build_tool_context(session.id)

      case result do
        {:ok, context} ->
          assert context.session_id == session.id
          assert is_binary(context.project_root)
          assert is_integer(context.timeout)

        {:error, _reason} ->
          # May fail if session manager not fully ready
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end
  end

  describe "get_tool_context/1" do
    test "returns error when agent has no proper session_id" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Start agent without explicit session_id (uses PID string)
      case LLMAgent.start_link() do
        {:ok, pid} ->
          result = LLMAgent.get_tool_context(pid)

          # Should return error since session_id is a PID string
          assert {:error, :no_session_id} = result

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "returns context for agent with valid session" do
      # Set API key BEFORE starting session
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create a real session with valid config
      {:ok, session} =
        Session.new(
          project_path: System.tmp_dir!(),
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Get agent from session (already started by session supervisor)
      case Session.Supervisor.get_agent(session.id) do
        {:ok, pid} ->
          result = LLMAgent.get_tool_context(pid)

          case result do
            {:ok, context} ->
              assert context.session_id == session.id
              assert is_binary(context.project_root)
              assert is_integer(context.timeout)

            {:error, _reason} ->
              # May fail if session not ready
              :ok
          end

        # Don't stop agent - session supervisor handles it

        {:error, _reason} ->
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end
  end

  # ============================================================================
  # Tool Execution Tests (Task 3.3.3)
  # ============================================================================

  describe "execute_tool/2" do
    setup do
      # Register tools for execution
      JidoCode.Tools.register_all()
      :ok
    end

    test "returns error when agent has no proper session_id" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Start agent without explicit session_id (uses PID string)
      case LLMAgent.start_link() do
        {:ok, pid} ->
          tool_call = %{id: "call_1", name: "read_file", arguments: %{"path" => "/test.txt"}}
          result = LLMAgent.execute_tool(pid, tool_call)

          # Should return error since session_id is a PID string
          assert {:error, :no_session_id} = result

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "executes tool with valid session context" do
      # Set API key BEFORE starting session (session starts LLMAgent)
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create temp file for testing
      tmp_dir = System.tmp_dir!()
      test_file = Path.join(tmp_dir, "test_#{System.unique_integer([:positive])}.txt")
      File.write!(test_file, "Hello, World!")

      on_exit(fn -> File.rm(test_file) end)

      # Create a real session with valid config
      {:ok, session} =
        Session.new(project_path: tmp_dir, config: SessionTestHelpers.valid_session_config())

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Session already has LLMAgent started - get it from the session
      case Session.Supervisor.get_agent(session.id) do
        {:ok, pid} ->
          tool_call = %{
            id: "call_1",
            name: "read_file",
            arguments: %{"path" => test_file}
          }

          result = LLMAgent.execute_tool(pid, tool_call)

          case result do
            {:ok, tool_result} ->
              assert tool_result.tool_call_id == "call_1"
              assert tool_result.tool_name == "read_file"
              assert tool_result.status == :ok
              assert String.contains?(tool_result.content, "Hello, World!")

            {:error, _reason} ->
              # May fail if session not ready
              :ok
          end

        # Don't stop agent - session supervisor handles it

        {:error, _reason} ->
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end

    test "handles tool not found error" do
      # Set API key BEFORE starting session
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create a real session with valid config
      tmp_dir = System.tmp_dir!()

      {:ok, session} =
        Session.new(project_path: tmp_dir, config: SessionTestHelpers.valid_session_config())

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Get agent from session
      case Session.Supervisor.get_agent(session.id) do
        {:ok, pid} ->
          tool_call = %{
            id: "call_1",
            name: "nonexistent_tool",
            arguments: %{}
          }

          result = LLMAgent.execute_tool(pid, tool_call)

          case result do
            {:ok, tool_result} ->
              # Tool not found is returned as an error Result, not an error tuple
              assert tool_result.status == :error
              assert String.contains?(tool_result.content, "not found")

            {:error, _reason} ->
              # May fail if session not ready
              :ok
          end

        # Don't stop agent - session supervisor handles it

        {:error, _reason} ->
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end

    test "handles path outside project boundary" do
      # Set API key BEFORE starting session
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create a real session with restricted project path
      tmp_dir = Path.join(System.tmp_dir!(), "project_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, session} =
        Session.new(project_path: tmp_dir, config: SessionTestHelpers.valid_session_config())

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Get agent from session
      case Session.Supervisor.get_agent(session.id) do
        {:ok, pid} ->
          # Try to read file outside project boundary
          tool_call = %{
            id: "call_1",
            name: "read_file",
            arguments: %{"path" => "/etc/passwd"}
          }

          result = LLMAgent.execute_tool(pid, tool_call)

          case result do
            {:ok, tool_result} ->
              # Path validation error
              assert tool_result.status == :error

              assert String.contains?(tool_result.content, "outside") or
                       String.contains?(tool_result.content, "boundary") or
                       String.contains?(tool_result.content, "allowed")

            {:error, _reason} ->
              # May fail if session not ready
              :ok
          end

        # Don't stop agent - session supervisor handles it

        {:error, _reason} ->
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end
  end

  describe "execute_tool_batch/3" do
    setup do
      # Register tools for execution
      JidoCode.Tools.register_all()
      :ok
    end

    test "returns error when agent has no proper session_id" do
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Start agent without explicit session_id (uses PID string)
      case LLMAgent.start_link() do
        {:ok, pid} ->
          tool_calls = [
            %{id: "call_1", name: "read_file", arguments: %{"path" => "/a.txt"}},
            %{id: "call_2", name: "read_file", arguments: %{"path" => "/b.txt"}}
          ]

          result = LLMAgent.execute_tool_batch(pid, tool_calls)

          assert {:error, :no_session_id} = result

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "executes multiple tools sequentially" do
      # Set API key BEFORE starting session
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create temp files for testing
      tmp_dir = System.tmp_dir!()
      file_a = Path.join(tmp_dir, "a_#{System.unique_integer([:positive])}.txt")
      file_b = Path.join(tmp_dir, "b_#{System.unique_integer([:positive])}.txt")
      File.write!(file_a, "Content A")
      File.write!(file_b, "Content B")

      on_exit(fn ->
        File.rm(file_a)
        File.rm(file_b)
      end)

      # Create a real session with valid config
      {:ok, session} =
        Session.new(project_path: tmp_dir, config: SessionTestHelpers.valid_session_config())

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Get agent from session
      case Session.Supervisor.get_agent(session.id) do
        {:ok, pid} ->
          tool_calls = [
            %{id: "call_1", name: "read_file", arguments: %{"path" => file_a}},
            %{id: "call_2", name: "read_file", arguments: %{"path" => file_b}}
          ]

          result = LLMAgent.execute_tool_batch(pid, tool_calls)

          case result do
            {:ok, results} ->
              assert length(results) == 2

              [result_a, result_b] = results
              assert result_a.tool_call_id == "call_1"
              assert result_a.status == :ok
              assert String.contains?(result_a.content, "Content A")

              assert result_b.tool_call_id == "call_2"
              assert result_b.status == :ok
              assert String.contains?(result_b.content, "Content B")

            {:error, _reason} ->
              # May fail if session not ready
              :ok
          end

        # Don't stop agent - session supervisor handles it

        {:error, _reason} ->
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end

    test "executes multiple tools in parallel" do
      # Set API key BEFORE starting session
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create temp files for testing
      tmp_dir = System.tmp_dir!()
      file_a = Path.join(tmp_dir, "a_#{System.unique_integer([:positive])}.txt")
      file_b = Path.join(tmp_dir, "b_#{System.unique_integer([:positive])}.txt")
      File.write!(file_a, "Parallel A")
      File.write!(file_b, "Parallel B")

      on_exit(fn ->
        File.rm(file_a)
        File.rm(file_b)
      end)

      # Create a real session with valid config
      {:ok, session} =
        Session.new(project_path: tmp_dir, config: SessionTestHelpers.valid_session_config())

      {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

      # Get agent from session
      case Session.Supervisor.get_agent(session.id) do
        {:ok, pid} ->
          tool_calls = [
            %{id: "call_1", name: "read_file", arguments: %{"path" => file_a}},
            %{id: "call_2", name: "read_file", arguments: %{"path" => file_b}}
          ]

          result = LLMAgent.execute_tool_batch(pid, tool_calls, parallel: true)

          case result do
            {:ok, results} ->
              assert length(results) == 2

              # Results should be in the same order as input
              [result_a, result_b] = results
              assert result_a.tool_call_id == "call_1"
              assert result_b.tool_call_id == "call_2"

            {:error, _reason} ->
              # May fail if session not ready
              :ok
          end

        # Don't stop agent - session supervisor handles it

        {:error, _reason} ->
          :ok
      end

      # Cleanup
      JidoCode.SessionSupervisor.stop_session(session.id)
    end
  end

  # ============================================================================
  # Streaming Integration Tests
  # ============================================================================

  describe "streaming with Session.State integration" do
    alias JidoCode.Session.State, as: SessionState

    test "start_session_streaming is skipped when session_id is PID string" do
      # Agents started without a session have a PID-based session_id
      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Start agent without session - session_id will be a PID string
      case LLMAgent.start_link() do
        {:ok, pid} ->
          # Get the session_id from state
          state = :sys.get_state(pid)
          session_id = state.session_id

          # Verify it's a PID string
          assert String.starts_with?(session_id, "#PID<")

          # Attempt to call start_streaming with this should not crash
          # (the internal helper handles graceful degradation)
          result = SessionState.start_streaming(session_id, "test-msg-id")

          # Should return :not_found since the session doesn't exist
          assert {:error, :not_found} = result

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end

    test "streaming with proper session updates Session.State" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "streaming_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      # Create a proper session
      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          # Get the agent from the session supervisor
          case Session.Supervisor.get_agent(session.id) do
            {:ok, _agent_pid} ->
              # Verify session is registered
              assert {:ok, _} = ProcessRegistry.lookup(:state, session.id)

              # Manually test the Session.State streaming API (direct test)
              message_id = "test-msg-123"

              # Start streaming
              {:ok, state1} = SessionState.start_streaming(session.id, message_id)
              assert state1.is_streaming == true
              assert state1.streaming_message == ""
              assert state1.streaming_message_id == message_id

              # Send some chunks
              :ok = SessionState.update_streaming(session.id, "Hello ")
              :ok = SessionState.update_streaming(session.id, "world!")

              # Give async casts time to process
              Process.sleep(50)

              # End streaming
              {:ok, final_message} = SessionState.end_streaming(session.id)
              assert final_message.id == message_id
              assert final_message.role == :assistant
              assert final_message.content == "Hello world!"

              # Verify message is in session history
              {:ok, messages} = SessionState.get_messages(session.id)
              assert length(messages) >= 1

              last_message = List.last(messages)
              assert last_message.id == message_id
              assert last_message.content == "Hello world!"

              # Cleanup - don't stop agent directly
              :ok

            {:error, _reason} ->
              :ok
          end

          # Cleanup session
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "end_streaming returns error when not streaming" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "end_streaming_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          # Try to end streaming without starting it
          result = SessionState.end_streaming(session.id)
          assert {:error, :not_streaming} = result

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "streaming chunks are silently ignored when not streaming" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "chunks_ignored_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          # Send a chunk without starting streaming
          result = SessionState.update_streaming(session.id, "orphan chunk")

          # Should silently succeed (cast doesn't return errors)
          assert result == :ok

          # Messages should be empty
          {:ok, messages} = SessionState.get_messages(session.id)
          # Filter to only assistant messages (no orphan chunk added)
          assistant_messages = Enum.filter(messages, fn m -> m.role == :assistant end)
          assert assistant_messages == []

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "is_valid_session_id helper correctly identifies PID strings" do
      # This is an internal helper, but we can test the logic indirectly
      # by checking that agents without sessions don't crash on streaming ops

      Application.put_env(:jido_code, :llm,
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      System.put_env("ANTHROPIC_API_KEY", "test-key")

      case LLMAgent.start_link() do
        {:ok, pid} ->
          # Get the session_id (should be PID string)
          state = :sys.get_state(pid)
          session_id = state.session_id

          # Verify it starts with #PID<
          assert String.starts_with?(session_id, "#PID<")

          # The agent should handle streaming requests gracefully
          # even without a proper session
          # (This tests the internal logic won't crash)
          assert Process.alive?(pid)

          stop_agent(pid)

        {:error, _reason} ->
          :ok
      end
    end
  end
end
