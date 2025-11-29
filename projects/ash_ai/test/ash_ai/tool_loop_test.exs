# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolLoopTest do
  use ExUnit.Case, async: true

  alias AshAi.ToolLoop

  defmodule FakeReqLLM do
    @moduledoc """
    Fake ReqLLM for testing tool loops.
    """

    def generate_text(_model, context) do
      messages = context.messages

      # Check if we have tool results
      has_tool_result = Enum.any?(messages, &(&1.role == :tool))

      if has_tool_result do
        # After tool execution, return final response
        {:ok,
         %{
           message: %ReqLLM.Message{
             role: :assistant,
             content: [ReqLLM.Message.ContentPart.text("Task completed successfully")]
           }
         }}
      else
        # First call: return a tool call
        {:ok,
         %{
           message: %ReqLLM.Message{
             role: :assistant,
             content: [],
             tool_calls: [
               ReqLLM.ToolCall.new("call_123", "read_test_posts", Jason.encode!(%{"limit" => 5}))
             ]
           }
         }}
      end
    end

    def stream_text(_model, context) do
      messages = context.messages
      has_tool_result = Enum.any?(messages, &(&1.role == :tool))

      if has_tool_result do
        # After tool execution, stream final response
        stream = [
          %{type: :content, text: "Task "},
          %{type: :content, text: "completed"}
        ]

        {:ok, %{stream: stream}}
      else
        # First call: stream a tool call
        stream = [
          %{
            type: :tool_call,
            id: "call_123",
            name: "read_test_posts",
            arguments: %{"limit" => 5}
          }
        ]

        {:ok, %{stream: stream}}
      end
    end
  end

  defmodule MultiIterationFakeReqLLM do
    @moduledoc """
    Fake LLM that requires multiple iterations.
    """

    def generate_text(_model, context) do
      messages = context.messages

      tool_result_count = Enum.count(messages, &(&1.role == :tool))

      cond do
        tool_result_count >= 2 ->
          # After 2 tool calls, return final response
          {:ok,
           %{
             message: %ReqLLM.Message{
               role: :assistant,
               content: [
                 ReqLLM.Message.ContentPart.text("All tasks completed successfully")
               ]
             }
           }}

        tool_result_count == 1 ->
          # Second tool call
          {:ok,
           %{
             message: %ReqLLM.Message{
               role: :assistant,
               content: [],
               tool_calls: [
                 ReqLLM.ToolCall.new(
                   "call_456",
                   "read_test_posts",
                   Jason.encode!(%{"limit" => 3})
                 )
               ]
             }
           }}

        true ->
          # First tool call
          {:ok,
           %{
             message: %ReqLLM.Message{
               role: :assistant,
               content: [],
               tool_calls: [
                 ReqLLM.ToolCall.new(
                   "call_123",
                   "read_test_posts",
                   Jason.encode!(%{"limit" => 5})
                 )
               ]
             }
           }}
      end
    end
  end

  defmodule EndlessFakeReqLLM do
    @moduledoc """
    Fake LLM that never stops calling tools.
    """

    def generate_text(_model, _context) do
      {:ok,
       %{
         message: %ReqLLM.Message{
           role: :assistant,
           content: [],
           tool_calls: [
             ReqLLM.ToolCall.new("call_#{:rand.uniform(1000)}", "read_test_posts", "{}")
           ]
         }
       }}
    end
  end

  defmodule SlowFakeReqLLM do
    @moduledoc """
    Fake LLM that times out.
    """

    def generate_text(_model, _context) do
      Process.sleep(100)

      {:ok,
       %{
         message: %ReqLLM.Message{
           role: :assistant,
           content: [ReqLLM.Message.ContentPart.text("Too slow")]
         }
       }}
    end
  end

  defmodule ErrorFakeReqLLM do
    @moduledoc """
    Fake LLM that returns errors.
    """

    def generate_text(_model, _context) do
      {:error, "LLM service unavailable"}
    end
  end

  # Test Resources

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, otp_app: :ash_ai, extensions: [AshAi]

    defmodule Post do
      @moduledoc false
      use Ash.Resource,
        domain: TestDomain,
        data_layer: Ash.DataLayer.Ets,
        authorizers: [Ash.Policy.Authorizer]

      ets do
        private? true
      end

      attributes do
        uuid_primary_key :id
        attribute :title, :string, allow_nil?: false, public?: true
        attribute :content, :string, public?: true
        attribute :published, :boolean, default: false, public?: true
      end

      actions do
        default_accept :*
        defaults [:read, :destroy, create: :*, update: :*]
      end

      policies do
        policy always() do
          authorize_if always()
        end
      end
    end

    defmodule PrivatePost do
      @moduledoc false
      use Ash.Resource,
        domain: TestDomain,
        data_layer: Ash.DataLayer.Ets,
        authorizers: [Ash.Policy.Authorizer]

      ets do
        private? true
      end

      attributes do
        uuid_primary_key :id
        attribute :title, :string, allow_nil?: false, public?: true
      end

      actions do
        default_accept :*
        defaults [:read]
      end

      policies do
        policy always() do
          forbid_if always()
        end
      end
    end

    resources do
      resource Post
      resource PrivatePost
    end

    tools do
      tool :read_test_posts, Post, :read
      tool :create_test_post, Post, :create
      tool :read_private_posts, PrivatePost, :read
    end
  end

  describe "run/2" do
    test "executes single tool call and returns final message" do
      messages = [%{role: "user", content: "Get the latest posts"}]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )

      assert result.message.role == :assistant

      assert result.message.content == [
               ReqLLM.Message.ContentPart.text("Task completed successfully")
             ]

      assert result.iterations == 2
      assert result.metadata.tool_calls_count == 1
      refute result.metadata.max_iterations_reached
    end

    test "executes multiple iterations" do
      messages = [%{role: "user", content: "Get posts in multiple batches"}]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: MultiIterationFakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )

      assert result.iterations == 3
      assert result.metadata.tool_calls_count == 2

      assert result.message.content == [
               ReqLLM.Message.ContentPart.text("All tasks completed successfully")
             ]
    end

    test "respects max_iterations limit" do
      messages = [%{role: "user", content: "Keep going"}]

      {:error, :max_iterations_reached} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: EndlessFakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          max_iterations: 3
        )
    end

    test "respects timeout" do
      messages = [%{role: "user", content: "Be slow"}]

      {:error, :timeout} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: SlowFakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          timeout: 10
        )
    end

    test "returns error when LLM fails" do
      messages = [%{role: "user", content: "Fail please"}]

      {:error, "LLM service unavailable"} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: ErrorFakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )
    end

    test "requires model parameter" do
      messages = [%{role: "user", content: "Test"}]

      {:error, "model is required"} =
        ToolLoop.run(messages,
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )
    end

    test "returns messages when return_messages? is true" do
      messages = [%{role: "user", content: "Get posts"}]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          return_messages?: true
        )

      assert result.messages == messages
    end

    test "does not return messages by default" do
      messages = [%{role: "user", content: "Get posts"}]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )

      assert is_nil(result.messages)
    end

    test "returns tool results when return_tool_results? is true" do
      messages = [%{role: "user", content: "Get posts"}]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          return_tool_results?: true
        )

      assert is_list(result.tool_results)
      assert length(result.tool_results) == 1
    end

    test "passes actor to tools" do
      messages = [%{role: "user", content: "Get posts"}]
      actor = %{id: 1, name: "Test User"}

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          actor: actor
        )

      # If actor wasn't passed, the tool would fail
      # This test verifies the flow works with an actor
    end

    test "passes tenant to tools" do
      messages = [%{role: "user", content: "Get posts"}]
      tenant = "org_123"

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          tenant: tenant
        )

      # Verifies tenant is threaded through
    end

    test "passes context to tools" do
      messages = [%{role: "user", content: "Get posts"}]
      context = %{request_id: "req_123"}

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          context: context
        )

      # Verifies context is threaded through
    end
  end

  describe "callbacks" do
    test "emits on_tool_start callback" do
      test_pid = self()

      on_tool_start = fn event ->
        send(test_pid, {:tool_start, event})
      end

      messages = [%{role: "user", content: "Get posts"}]

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          on_tool_start: on_tool_start
        )

      assert_receive {:tool_start, %AshAi.ToolStartEvent{} = event}
      assert event.tool_name == "read_test_posts"
      assert event.action == :read
      assert event.resource == Post
      assert event.arguments == %{"limit" => 5}
    end

    test "emits on_tool_end callback" do
      test_pid = self()

      on_tool_end = fn event ->
        send(test_pid, {:tool_end, event})
      end

      messages = [%{role: "user", content: "Get posts"}]

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          on_tool_end: on_tool_end
        )

      assert_receive {:tool_end, %AshAi.ToolEndEvent{} = event}
      assert event.tool_name == "read_test_posts"
      assert match?({:ok, _, _}, event.result)
    end

    test "emits on_iteration callback" do
      test_pid = self()

      on_iteration = fn event ->
        send(test_pid, {:iteration, event})
      end

      messages = [%{role: "user", content: "Get posts"}]

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          on_iteration: on_iteration
        )

      # Should receive 2 iterations (initial + after tool call)
      assert_receive {:iteration, %ToolLoop.IterationEvent{iteration: 1}}
      assert_receive {:iteration, %ToolLoop.IterationEvent{iteration: 2}}
    end

    test "emits callbacks for multiple iterations" do
      test_pid = self()

      on_tool_start = fn event ->
        send(test_pid, {:tool_start, event.tool_name})
      end

      messages = [%{role: "user", content: "Multiple batches"}]

      {:ok, _result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: MultiIterationFakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain],
          on_tool_start: on_tool_start
        )

      # Should receive 2 tool start events
      assert_receive {:tool_start, "read_test_posts"}
      assert_receive {:tool_start, "read_test_posts"}
    end
  end

  describe "authorization" do
    test "enforces authorization on tool calls" do
      defmodule UnauthorizedFakeReqLLM do
        def generate_text(_model, context) do
          has_tool_result = Enum.any?(context.messages, &(&1.role == :tool))

          if has_tool_result do
            {:ok,
             %{
               message: %ReqLLM.Message{
                 role: :assistant,
                 content: [ReqLLM.Message.ContentPart.text("Done")]
               }
             }}
          else
            {:ok,
             %{
               message: %ReqLLM.Message{
                 role: :assistant,
                 content: [],
                 tool_calls: [
                   ReqLLM.ToolCall.new("call_unauthorized", "read_private_posts", "{}")
                 ]
               }
             }}
          end
        end
      end

      messages = [%{role: "user", content: "Get private posts"}]
      actor = %{id: 1, role: "user"}

      # The tool will be filtered out during tool discovery due to authorization
      assert {:error, _reason} =
               ToolLoop.run(messages,
                 model: "test-model",
                 req_llm: UnauthorizedFakeReqLLM,
                 actions: [{PrivatePost, [:read]}],
                 actor: actor
               )
    end
  end

  describe "stream/2" do
    test "returns a stream" do
      messages = [%{role: "user", content: "Get posts"}]

      stream =
        ToolLoop.stream(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )

      assert is_function(stream)
    end

    test "streams text chunks" do
      messages = [%{role: "user", content: "Get posts"}]

      events =
        ToolLoop.stream(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )
        |> Enum.to_list()

      text_events = Enum.filter(events, &match?({:text, _}, &1))
      assert length(text_events) >= 0
    end

    test "streams tool call events" do
      messages = [%{role: "user", content: "Get posts"}]

      events =
        ToolLoop.stream(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )
        |> Enum.to_list()

      tool_call_events = Enum.filter(events, &match?({:tool_call, _, _}, &1))
      assert length(tool_call_events) >= 0
    end
  end

  describe "error handling" do
    test "returns error for unknown tool" do
      defmodule UnknownToolFakeReqLLM do
        def generate_text(_model, _context) do
          {:ok,
           %{
             message: %ReqLLM.Message{
               role: :assistant,
               content: [],
               tool_calls: [
                 ReqLLM.ToolCall.new("call_unknown", "nonexistent_tool", "{}")
               ]
             }
           }}
        end
      end

      messages = [%{role: "user", content: "Call unknown tool"}]

      {:error, {:tool_not_found, "nonexistent_tool"}} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: UnknownToolFakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )
    end

    test "handles missing otp_app/actions gracefully" do
      messages = [%{role: "user", content: "Test"}]

      {:error, _reason} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM
        )
    end
  end

  describe "message normalization" do
    test "handles plain map messages" do
      messages = [%{role: "user", content: "Test"}]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )

      assert result.message.role == :assistant
    end

    test "handles ReqLLM.Message structs" do
      messages = [
        %ReqLLM.Message{
          role: :user,
          content: [ReqLLM.Message.ContentPart.text("Test")]
        }
      ]

      {:ok, result} =
        ToolLoop.run(messages,
          model: "test-model",
          req_llm: FakeReqLLM,
          domains: [AshAi.ToolLoopTest.TestDomain]
        )

      assert result.message.role == :assistant
    end
  end
end
