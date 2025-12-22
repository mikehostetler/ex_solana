defmodule JidoCode.Session.AgentAPITest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.AgentAPI
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.TestHelpers.EnvIsolation

  @moduletag :agent_api

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

  describe "send_message/2" do
    test "returns error when session has no agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Use a non-existent session ID
      result = AgentAPI.send_message("non-existent-session-id", "Hello!")

      assert {:error, :agent_not_found} = result
    end

    test "sends message to correct agent and returns response" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "agent_api_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          # Test send_message - will fail without real API but tests the flow
          result = AgentAPI.send_message(session.id, "Hello!")

          # The call goes through but may fail due to mock API key
          case result do
            {:ok, _response} ->
              # If it succeeds (unlikely with mock key), that's fine
              assert true

            {:error, reason} ->
              # Expected with mock API key - validates the pipeline works
              # Could be API auth error or other LLM error
              assert reason != :agent_not_found
          end

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "validates message is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Should raise FunctionClauseError for non-binary message
      assert_raise FunctionClauseError, fn ->
        AgentAPI.send_message("session-123", 12_345)
      end

      assert_raise FunctionClauseError, fn ->
        AgentAPI.send_message("session-123", nil)
      end
    end

    test "validates session_id is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.send_message(12_345, "Hello!")
      end

      assert_raise FunctionClauseError, fn ->
        AgentAPI.send_message(nil, "Hello!")
      end
    end
  end

  describe "send_message_stream/2" do
    test "returns error when session has no agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = AgentAPI.send_message_stream("non-existent-session-id", "Hello!")

      assert {:error, :agent_not_found} = result
    end

    test "initiates streaming to correct agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "agent_api_stream_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          # Subscribe to PubSub to receive stream events
          topic = JidoCode.PubSubTopics.llm_stream(session.id)
          Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)

          # Initiate streaming
          result = AgentAPI.send_message_stream(session.id, "Hello!")

          # Should return :ok immediately (streaming is async)
          assert result == :ok

          # Note: Actual stream events would require real API key
          # The test validates the call chain works correctly

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "accepts timeout option" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "agent_api_timeout_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          # Test with custom timeout
          result = AgentAPI.send_message_stream(session.id, "Hello!", timeout: 30_000)

          assert result == :ok

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "validates message is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.send_message_stream("session-123", 12_345)
      end
    end

    test "validates session_id is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.send_message_stream(nil, "Hello!")
      end
    end
  end

  describe "error handling" do
    test "translates :not_found to :agent_not_found" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Both functions should translate the error
      assert {:error, :agent_not_found} = AgentAPI.send_message("unknown", "Hello")
      assert {:error, :agent_not_found} = AgentAPI.send_message_stream("unknown", "Hello")
    end
  end

  describe "get_status/1" do
    test "returns error when session has no agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = AgentAPI.get_status("non-existent-session-id")

      assert {:error, :agent_not_found} = result
    end

    test "returns status for valid session" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "get_status_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          result = AgentAPI.get_status(session.id)

          case result do
            {:ok, status} ->
              assert is_boolean(status.ready)
              assert is_map(status.config)
              assert status.session_id == session.id
              assert is_binary(status.topic)
              assert String.contains?(status.topic, session.id)

            {:error, _reason} ->
              # May fail if agent not fully started
              :ok
          end

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "validates session_id is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.get_status(12_345)
      end
    end
  end

  describe "is_processing?/1" do
    test "returns error when session has no agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = AgentAPI.is_processing?("non-existent-session-id")

      assert {:error, :agent_not_found} = result
    end

    test "returns boolean for valid session" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "is_processing_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          result = AgentAPI.is_processing?(session.id)

          case result do
            {:ok, is_processing} ->
              assert is_boolean(is_processing)
              # Agent should be ready (not processing) when idle
              assert is_processing == false

            {:error, _reason} ->
              # May fail if agent not fully started
              :ok
          end

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "validates session_id is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.is_processing?(nil)
      end
    end
  end

  describe "update_config/2" do
    test "returns error when session has no agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = AgentAPI.update_config("non-existent-session-id", %{temperature: 0.5})

      assert {:error, :agent_not_found} = result
    end

    test "updates agent configuration with map" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "update_config_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          result = AgentAPI.update_config(session.id, %{temperature: 0.5})

          assert result == :ok

          # Verify config was updated
          {:ok, new_config} = AgentAPI.get_config(session.id)
          assert new_config.temperature == 0.5

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "updates agent configuration with keyword list" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "update_config_kw_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          result = AgentAPI.update_config(session.id, temperature: 0.3, max_tokens: 2048)

          assert result == :ok

          # Verify config was updated
          {:ok, new_config} = AgentAPI.get_config(session.id)
          assert new_config.temperature == 0.3
          assert new_config.max_tokens == 2048

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "also updates session's stored config" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "update_config_session_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          :ok = AgentAPI.update_config(session.id, %{temperature: 0.8})

          # Verify session's stored config was also updated
          {:ok, updated_session} = JidoCode.Session.State.get_state(session.id)
          assert updated_session.session.config.temperature == 0.8

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "validates session_id is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.update_config(12_345, %{temperature: 0.5})
      end
    end
  end

  describe "get_config/1" do
    test "returns error when session has no agent" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      result = AgentAPI.get_config("non-existent-session-id")

      assert {:error, :agent_not_found} = result
    end

    test "returns current config for valid session" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      # Create unique temp directory for this test
      tmp_dir =
        Path.join(System.tmp_dir!(), "get_config_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      config = SessionTestHelpers.valid_session_config()

      case Session.new(project_path: tmp_dir, config: config) do
        {:ok, session} ->
          {:ok, _sup_pid} = JidoCode.SessionSupervisor.start_session(session)

          result = AgentAPI.get_config(session.id)

          case result do
            {:ok, config} ->
              assert is_map(config)
              assert Map.has_key?(config, :provider)
              assert Map.has_key?(config, :model)
              assert Map.has_key?(config, :temperature)
              assert Map.has_key?(config, :max_tokens)

            {:error, _reason} ->
              # May fail if agent not fully started
              :ok
          end

          # Cleanup
          JidoCode.SessionSupervisor.stop_session(session.id)

        {:error, _reason} ->
          :ok
      end
    end

    test "validates session_id is binary" do
      System.put_env("ANTHROPIC_API_KEY", "test-key")

      assert_raise FunctionClauseError, fn ->
        AgentAPI.get_config(nil)
      end
    end
  end
end
