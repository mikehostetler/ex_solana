defmodule JidoCode.Tools.ExecutorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result, Tool}

  # Mock handler for testing
  defmodule MockHandler do
    def execute(%{"path" => path}, _context) do
      {:ok, "Contents of #{path}"}
    end

    def execute(%{"error" => true}, _context) do
      {:error, "Intentional error"}
    end

    def execute(%{"slow" => ms}, _context) do
      Process.sleep(ms)
      {:ok, "Completed after #{ms}ms"}
    end

    def execute(args, _context) do
      {:ok, "Executed with: #{inspect(args)}"}
    end
  end

  setup do
    # Ensure application is started (Manager and registries)
    Application.ensure_all_started(:jido_code)

    # Clear registry for each test
    Registry.clear()

    # Register test tools (idempotent - will skip if already registered)
    {:ok, read_file} =
      Tool.new(%{
        name: "read_file",
        description: "Read a file",
        handler: MockHandler,
        parameters: [
          %{name: "path", type: :string, description: "File path", required: true}
        ]
      })

    {:ok, write_file} =
      Tool.new(%{
        name: "write_file",
        description: "Write a file",
        handler: MockHandler,
        parameters: [
          %{name: "path", type: :string, description: "File path", required: true},
          %{name: "content", type: :string, description: "Content", required: true}
        ]
      })

    {:ok, error_tool} =
      Tool.new(%{
        name: "error_tool",
        description: "Tool that errors",
        handler: MockHandler,
        parameters: [
          %{name: "error", type: :boolean, description: "Error flag", required: true}
        ]
      })

    {:ok, slow_tool} =
      Tool.new(%{
        name: "slow_tool",
        description: "Slow tool",
        handler: MockHandler,
        parameters: [
          %{name: "slow", type: :integer, description: "Sleep ms", required: true}
        ]
      })

    # Register tools, ignoring if already registered
    _ = Registry.register(read_file)
    _ = Registry.register(write_file)
    _ = Registry.register(error_tool)
    _ = Registry.register(slow_tool)

    :ok
  end

  describe "parse_tool_calls/1" do
    test "parses OpenAI-format tool calls with JSON arguments" do
      response = %{
        "tool_calls" => [
          %{
            "id" => "call_123",
            "type" => "function",
            "function" => %{
              "name" => "read_file",
              "arguments" => ~s({"path": "/src/main.ex"})
            }
          }
        ]
      }

      assert {:ok, [tool_call]} = Executor.parse_tool_calls(response)
      assert tool_call.id == "call_123"
      assert tool_call.name == "read_file"
      assert tool_call.arguments == %{"path" => "/src/main.ex"}
    end

    test "parses multiple tool calls" do
      response = %{
        "tool_calls" => [
          %{
            "id" => "call_1",
            "type" => "function",
            "function" => %{
              "name" => "read_file",
              "arguments" => ~s({"path": "/a.txt"})
            }
          },
          %{
            "id" => "call_2",
            "type" => "function",
            "function" => %{
              "name" => "read_file",
              "arguments" => ~s({"path": "/b.txt"})
            }
          }
        ]
      }

      assert {:ok, tool_calls} = Executor.parse_tool_calls(response)
      assert length(tool_calls) == 2
      assert Enum.at(tool_calls, 0).id == "call_1"
      assert Enum.at(tool_calls, 1).id == "call_2"
    end

    test "parses atom-keyed tool calls" do
      response = %{
        tool_calls: [
          %{
            id: "call_123",
            type: "function",
            function: %{
              name: "read_file",
              arguments: %{path: "/test.txt"}
            }
          }
        ]
      }

      assert {:ok, [tool_call]} = Executor.parse_tool_calls(response)
      assert tool_call.name == "read_file"
    end

    test "parses direct format without type wrapper" do
      tool_calls = [
        %{
          "id" => "call_123",
          "name" => "read_file",
          "arguments" => %{"path" => "/test.txt"}
        }
      ]

      assert {:ok, [tool_call]} = Executor.parse_tool_calls(tool_calls)
      assert tool_call.name == "read_file"
    end

    test "parses from full API response with choices" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "type" => "function",
                  "function" => %{
                    "name" => "read_file",
                    "arguments" => ~s({"path": "/test.txt"})
                  }
                }
              ]
            }
          }
        ]
      }

      assert {:ok, [tool_call]} = Executor.parse_tool_calls(response)
      assert tool_call.name == "read_file"
    end

    test "returns error for no tool calls" do
      assert {:error, :no_tool_calls} = Executor.parse_tool_calls(%{})
      assert {:error, :no_tool_calls} = Executor.parse_tool_calls(%{"tool_calls" => []})
      assert {:error, :no_tool_calls} = Executor.parse_tool_calls(%{"tool_calls" => nil})
    end

    test "returns error for invalid JSON in arguments" do
      response = %{
        "tool_calls" => [
          %{
            "id" => "call_123",
            "type" => "function",
            "function" => %{
              "name" => "read_file",
              "arguments" => "invalid json {"
            }
          }
        ]
      }

      assert {:error, {:invalid_tool_call, msg}} = Executor.parse_tool_calls(response)
      assert msg =~ "invalid JSON"
    end

    test "returns error for malformed tool call" do
      response = %{
        "tool_calls" => [
          %{"bad" => "format"}
        ]
      }

      assert {:error, {:invalid_tool_call, _}} = Executor.parse_tool_calls(response)
    end
  end

  describe "execute/2" do
    test "executes valid tool call successfully" do
      tool_call = %{id: "call_123", name: "read_file", arguments: %{"path" => "/test.txt"}}

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :ok
      assert result.tool_call_id == "call_123"
      assert result.tool_name == "read_file"
      assert result.content == "Contents of /test.txt"
      assert result.duration_ms >= 0
    end

    test "handles string-keyed tool call" do
      tool_call = %{
        "id" => "call_123",
        "name" => "read_file",
        "arguments" => %{"path" => "/test.txt"}
      }

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :ok
    end

    test "returns error result for non-existent tool" do
      tool_call = %{id: "call_123", name: "nonexistent_tool", arguments: %{}}

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "returns error result for missing required parameter" do
      tool_call = %{id: "call_123", name: "read_file", arguments: %{}}

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "returns error result for unknown parameter" do
      tool_call = %{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "/test.txt", "unknown" => "param"}
      }

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :error
      assert result.content =~ "unknown parameter"
    end

    test "returns error result for wrong parameter type" do
      tool_call = %{id: "call_123", name: "read_file", arguments: %{"path" => 123}}

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :error
      assert result.content =~ "must be a string"
    end

    test "returns error result when handler returns error" do
      tool_call = %{id: "call_123", name: "error_tool", arguments: %{"error" => true}}

      assert {:ok, result} = Executor.execute(tool_call)
      assert result.status == :error
      assert result.content == "Intentional error"
    end

    test "uses custom executor function" do
      custom_executor = fn _tool, args, _context ->
        {:ok, "Custom: #{inspect(args)}"}
      end

      tool_call = %{id: "call_123", name: "read_file", arguments: %{"path" => "/test.txt"}}

      assert {:ok, result} = Executor.execute(tool_call, executor: custom_executor)
      assert result.content =~ "Custom:"
    end

    test "passes context to executor" do
      custom_executor = fn _tool, _args, context ->
        {:ok, "Context: #{inspect(context)}"}
      end

      tool_call = %{id: "call_123", name: "read_file", arguments: %{"path" => "/test.txt"}}

      assert {:ok, result} =
               Executor.execute(tool_call, executor: custom_executor, context: %{user: "test"})

      assert result.content =~ "user"
    end

    test "handles timeout" do
      tool_call = %{id: "call_123", name: "slow_tool", arguments: %{"slow" => 500}}

      assert {:ok, result} = Executor.execute(tool_call, timeout: 100)
      assert result.status == :timeout
      assert result.content =~ "timed out"
    end

    test "tracks execution duration" do
      tool_call = %{id: "call_123", name: "slow_tool", arguments: %{"slow" => 50}}

      assert {:ok, result} = Executor.execute(tool_call, timeout: 5000)
      assert result.duration_ms >= 50
    end
  end

  describe "execute_batch/2" do
    test "executes multiple tool calls sequentially" do
      tool_calls = [
        %{id: "call_1", name: "read_file", arguments: %{"path" => "/a.txt"}},
        %{id: "call_2", name: "read_file", arguments: %{"path" => "/b.txt"}}
      ]

      assert {:ok, results} = Executor.execute_batch(tool_calls)
      assert length(results) == 2
      assert Enum.at(results, 0).tool_call_id == "call_1"
      assert Enum.at(results, 1).tool_call_id == "call_2"
    end

    test "executes in parallel when option set" do
      tool_calls = [
        %{id: "call_1", name: "slow_tool", arguments: %{"slow" => 50}},
        %{id: "call_2", name: "slow_tool", arguments: %{"slow" => 50}}
      ]

      start = System.monotonic_time(:millisecond)
      {:ok, results} = Executor.execute_batch(tool_calls, parallel: true, timeout: 5000)
      elapsed = System.monotonic_time(:millisecond) - start

      assert length(results) == 2
      # Parallel execution should be faster than sequential (50+50=100ms)
      # Allow some overhead but should be less than 150ms
      assert elapsed < 150
    end

    test "handles mixed success and failure" do
      tool_calls = [
        %{id: "call_1", name: "read_file", arguments: %{"path" => "/a.txt"}},
        %{id: "call_2", name: "error_tool", arguments: %{"error" => true}},
        %{id: "call_3", name: "read_file", arguments: %{"path" => "/c.txt"}}
      ]

      assert {:ok, results} = Executor.execute_batch(tool_calls)

      assert Enum.at(results, 0).status == :ok
      assert Enum.at(results, 1).status == :error
      assert Enum.at(results, 2).status == :ok
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = Executor.execute_batch([])
    end
  end

  describe "validate_tool_exists/1" do
    test "returns tool when it exists" do
      assert {:ok, tool} = Executor.validate_tool_exists("read_file")
      assert tool.name == "read_file"
    end

    test "returns error when tool not found" do
      assert {:error, :not_found} = Executor.validate_tool_exists("nonexistent")
    end
  end

  describe "validate_arguments/2" do
    test "returns ok for valid arguments" do
      {:ok, tool} = Registry.get("read_file")
      assert :ok = Executor.validate_arguments(tool, %{"path" => "/test.txt"})
    end

    test "returns error for invalid arguments" do
      {:ok, tool} = Registry.get("read_file")
      assert {:error, _} = Executor.validate_arguments(tool, %{})
    end
  end

  describe "integration: parse and execute" do
    test "full round-trip from LLM response to results" do
      # Simulate LLM response with tool calls
      llm_response = %{
        "tool_calls" => [
          %{
            "id" => "call_abc",
            "type" => "function",
            "function" => %{
              "name" => "read_file",
              "arguments" => ~s({"path": "/src/main.ex"})
            }
          }
        ]
      }

      # Parse
      assert {:ok, tool_calls} = Executor.parse_tool_calls(llm_response)

      # Execute
      assert {:ok, results} = Executor.execute_batch(tool_calls)

      # Convert to LLM messages
      messages = Result.to_llm_messages(results)

      assert [message] = messages
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert message.content == "Contents of /src/main.ex"
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts tool_call event when executing" do
      # Subscribe to global topic
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_pubsub_1", name: "read_file", arguments: %{"path" => "/test.txt"}}
      {:ok, _result} = Executor.execute(tool_call)

      # Should receive tool_call event with session_id (nil when not provided)
      assert_receive {:tool_call, "read_file", %{"path" => "/test.txt"}, "call_pubsub_1", nil},
                     1000
    end

    test "broadcasts tool_result event when executing" do
      # Subscribe to global topic
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_pubsub_2", name: "read_file", arguments: %{"path" => "/result.txt"}}
      {:ok, _result} = Executor.execute(tool_call)

      # Should receive tool_result event with session_id (nil when not provided)
      assert_receive {:tool_result, result, nil}, 1000
      assert result.tool_call_id == "call_pubsub_2"
      assert result.tool_name == "read_file"
      assert result.status == :ok
    end

    test "broadcasts to session-specific topic when session_id provided" do
      session_id = "test_session_123"
      # Subscribe to session-specific topic
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events.#{session_id}")

      tool_call = %{id: "call_session_1", name: "read_file", arguments: %{"path" => "/test.txt"}}
      {:ok, _result} = Executor.execute(tool_call, session_id: session_id)

      # Should receive events on session topic with session_id in payload
      assert_receive {:tool_call, "read_file", _, "call_session_1", ^session_id}, 1000
      assert_receive {:tool_result, _result, ^session_id}, 1000
    end

    test "broadcasts to BOTH global and session topic when session_id provided (ARCH-2 fix)" do
      # ARCH-2 Fix: Now broadcasts to both topics so PubSubBridge receives messages
      session_id = "isolated_session"
      # Subscribe to global topic (should now receive due to ARCH-2 fix)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_isolated", name: "read_file", arguments: %{"path" => "/test.txt"}}
      {:ok, _result} = Executor.execute(tool_call, session_id: session_id)

      # ARCH-2: Should NOW receive events on global topic with session_id in payload
      assert_receive {:tool_call, _, _, "call_isolated", ^session_id}, 100
      assert_receive {:tool_result, _, ^session_id}, 100
    end

    test "broadcasts error result for non-existent tool" do
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_error_1", name: "nonexistent", arguments: %{}}
      {:ok, _result} = Executor.execute(tool_call)

      # Should receive error result with nil session_id
      assert_receive {:tool_result, result, nil}, 1000
      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "broadcasts timeout result" do
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_timeout_1", name: "slow_tool", arguments: %{"slow" => 500}}
      {:ok, _result} = Executor.execute(tool_call, timeout: 50)

      # Should receive both call and timeout result with nil session_id
      assert_receive {:tool_call, "slow_tool", _, "call_timeout_1", nil}, 1000
      assert_receive {:tool_result, result, nil}, 1000
      assert result.status == :timeout
    end

    test "includes session_id in tool_call payload" do
      session_id = "payload_test_session"
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_payload_1", name: "read_file", arguments: %{"path" => "/test.txt"}}
      {:ok, _result} = Executor.execute(tool_call, session_id: session_id)

      # Verify session_id is in the 5th position of the tuple
      assert_receive {:tool_call, _name, _params, _call_id, received_session_id}, 1000
      assert received_session_id == session_id
    end

    test "includes session_id in tool_result payload" do
      session_id = "result_payload_session"
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      tool_call = %{id: "call_result_1", name: "read_file", arguments: %{"path" => "/test.txt"}}
      {:ok, _result} = Executor.execute(tool_call, session_id: session_id)

      # Verify session_id is in the 3rd position of the tuple
      assert_receive {:tool_result, _result, received_session_id}, 1000
      assert received_session_id == session_id
    end
  end

  describe "pubsub_topic/1" do
    test "returns global topic for nil session_id" do
      assert Executor.pubsub_topic(nil) == "tui.events"
    end

    test "returns session-specific topic for session_id" do
      assert Executor.pubsub_topic("session_abc") == "tui.events.session_abc"
    end
  end

  # ============================================================================
  # Context Building Tests
  # ============================================================================

  describe "build_context/2" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Suppress deprecation warnings for tests
      Application.put_env(:jido_code, :suppress_executor_deprecation_warnings, true)

      # Create a session with a manager for testing
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "context-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:context_test_sup, session.id}}}
        )

      on_exit(fn ->
        Application.delete_env(:jido_code, :suppress_executor_deprecation_warnings)

        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session, tmp_dir: tmp_dir}
    end

    test "builds context with project_root from Session.Manager", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      {:ok, context} = Executor.build_context(session.id)

      assert context.session_id == session.id
      assert context.project_root == tmp_dir
      assert context.timeout == 30_000
    end

    test "allows custom timeout", %{session: session, tmp_dir: tmp_dir} do
      {:ok, context} = Executor.build_context(session.id, timeout: 60_000)

      assert context.session_id == session.id
      assert context.project_root == tmp_dir
      assert context.timeout == 60_000
    end

    test "returns error for unknown session_id" do
      # Use a valid UUID that doesn't exist
      assert {:error, :not_found} =
               Executor.build_context("550e8400-e29b-41d4-a716-446655440000")
    end
  end

  describe "enrich_context/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Create a session with a manager for testing
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "enrich-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:enrich_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session, tmp_dir: tmp_dir}
    end

    test "returns context unchanged if project_root already present", %{session: session} do
      context = %{session_id: session.id, project_root: "/custom/path"}
      {:ok, enriched} = Executor.enrich_context(context)

      assert enriched == context
      assert enriched.project_root == "/custom/path"
    end

    test "adds project_root from Session.Manager", %{session: session, tmp_dir: tmp_dir} do
      context = %{session_id: session.id}
      {:ok, enriched} = Executor.enrich_context(context)

      assert enriched.session_id == session.id
      assert enriched.project_root == tmp_dir
    end

    test "returns error for missing session_id" do
      assert {:error, :missing_session_id} = Executor.enrich_context(%{})
      assert {:error, :missing_session_id} = Executor.enrich_context(%{other: "value"})
    end

    test "returns error for unknown session_id" do
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}
      assert {:error, :not_found} = Executor.enrich_context(context)
    end
  end

  describe "execute/2 with context" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Suppress deprecation warnings for tests
      Application.put_env(:jido_code, :suppress_executor_deprecation_warnings, true)

      # Create a session with a manager for testing
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "exec-context-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:exec_context_test_sup, session.id}}}
        )

      on_exit(fn ->
        Application.delete_env(:jido_code, :suppress_executor_deprecation_warnings)

        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session, tmp_dir: tmp_dir}
    end

    test "uses session_id from context", %{session: session, tmp_dir: tmp_dir} do
      tool_call = %{id: "call_ctx_1", name: "read_file", arguments: %{"path" => "/test.txt"}}
      context = %{session_id: session.id, project_root: tmp_dir}

      {:ok, result} = Executor.execute(tool_call, context: context)

      assert result.status == :ok
      assert result.tool_call_id == "call_ctx_1"
    end

    test "auto-populates project_root when session_id present", %{session: session} do
      tool_call = %{id: "call_ctx_2", name: "read_file", arguments: %{"path" => "/test.txt"}}
      # Context with only session_id
      context = %{session_id: session.id}

      {:ok, result} = Executor.execute(tool_call, context: context)

      assert result.status == :ok
    end

    test "prefers session_id from context over legacy option", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      tool_call = %{id: "call_ctx_3", name: "read_file", arguments: %{"path" => "/test.txt"}}
      context = %{session_id: session.id, project_root: tmp_dir}

      # Pass both context.session_id and legacy session_id option
      {:ok, result} =
        Executor.execute(tool_call,
          context: context,
          session_id: "other-session-id"
        )

      # Should use context.session_id
      assert result.status == :ok
    end
  end

  # ============================================================================
  # Security Tests
  # ============================================================================

  describe "build_context/2 UUID validation" do
    test "rejects non-UUID format strings" do
      assert {:error, :invalid_session_id} = Executor.build_context("not-a-uuid")
      assert {:error, :invalid_session_id} = Executor.build_context("abc123")
      assert {:error, :invalid_session_id} = Executor.build_context("")
    end

    test "rejects malformed UUIDs" do
      # Wrong length
      assert {:error, :invalid_session_id} =
               Executor.build_context("550e8400-e29b-41d4-a716")

      # Missing dashes
      assert {:error, :invalid_session_id} =
               Executor.build_context("550e8400e29b41d4a716446655440000")

      # Invalid characters
      assert {:error, :invalid_session_id} =
               Executor.build_context("550e8400-e29b-41d4-a716-44665544ZZZZ")
    end

    test "rejects session IDs with special characters" do
      assert {:error, :invalid_session_id} = Executor.build_context("../../../etc/passwd")

      assert {:error, :invalid_session_id} =
               Executor.build_context("test<script>alert(1)</script>")

      assert {:error, :invalid_session_id} = Executor.build_context("session\nid")
      assert {:error, :invalid_session_id} = Executor.build_context("session\x00id")
    end

    test "rejects path traversal attempts" do
      assert {:error, :invalid_session_id} = Executor.build_context("..%2F..%2F..%2Fetc%2Fpasswd")
      assert {:error, :invalid_session_id} = Executor.build_context("....//....//etc/passwd")
    end

    test "accepts valid UUIDs" do
      # Valid UUID v4 - will return :not_found since session doesn't exist
      assert {:error, :not_found} =
               Executor.build_context("550e8400-e29b-41d4-a716-446655440000")

      # Valid UUID with uppercase
      assert {:error, :not_found} =
               Executor.build_context("550E8400-E29B-41D4-A716-446655440000")

      # Mixed case
      assert {:error, :not_found} =
               Executor.build_context("550e8400-E29B-41d4-A716-446655440000")
    end
  end

  describe "pubsub_topic/1 delegates to PubSubHelpers" do
    test "returns global topic for nil" do
      assert Executor.pubsub_topic(nil) == "tui.events"
    end

    test "returns session-specific topic for session_id" do
      assert Executor.pubsub_topic("abc-123") == "tui.events.abc-123"
    end
  end
end
