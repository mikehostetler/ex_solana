defmodule JidoCode.Session.StateTest do
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.State

  @registry JidoCode.SessionProcessRegistry

  setup do
    setup_session_registry("state_test")
  end

  describe "start_link/1" do
    test "starts state process successfully", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} = State.start_link(session: session)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "registers in SessionProcessRegistry with :state key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = State.start_link(session: session)

      # Should be findable via Registry with :state key
      assert [{^pid, _}] = Registry.lookup(@registry, {:state, session.id})

      # Cleanup
      GenServer.stop(pid)
    end

    test "requires :session option" do
      assert_raise KeyError, ~r/:session/, fn ->
        State.start_link([])
      end
    end

    test "fails for duplicate session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid1} = State.start_link(session: session)

      # Second start with same session should fail
      assert {:error, {:already_started, ^pid1}} = State.start_link(session: session)

      # Cleanup
      GenServer.stop(pid1)
    end
  end

  describe "child_spec/1" do
    test "returns correct specification", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      spec = State.child_spec(session: session)

      assert spec.id == {:session_state, session.id}
      assert spec.start == {State, :start_link, [[session: session]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end

  describe "get_session/1" do
    test "returns the session struct", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = State.start_link(session: session)

      assert {:ok, returned_session} = State.get_session(pid)
      assert returned_session.id == session.id
      assert returned_session.project_path == session.project_path

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "init/1 state structure" do
    test "initializes with empty messages list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.messages == []

      GenServer.stop(pid)
    end

    test "initializes with empty reasoning_steps list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.reasoning_steps == []

      GenServer.stop(pid)
    end

    test "initializes with empty tool_calls list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.tool_calls == []

      GenServer.stop(pid)
    end

    test "initializes with empty todos list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.todos == []

      GenServer.stop(pid)
    end

    test "initializes with scroll_offset = 0", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.scroll_offset == 0

      GenServer.stop(pid)
    end

    test "initializes with streaming_message = nil", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.streaming_message == nil

      GenServer.stop(pid)
    end

    test "initializes with is_streaming = false", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.is_streaming == false

      GenServer.stop(pid)
    end

    test "stores session_id in state", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.session_id == session.id

      GenServer.stop(pid)
    end

    test "stores session struct in state for backwards compatibility", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.session == session

      GenServer.stop(pid)
    end
  end

  describe "get_state/1" do
    test "returns full state for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, state} = State.get_state(session.id)
      assert state.session_id == session.id
      assert state.messages == []
      assert state.reasoning_steps == []
      assert state.todos == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_state("unknown-session-id")
    end
  end

  describe "get_messages/1" do
    test "returns messages list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, messages} = State.get_messages(session.id)
      assert messages == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_messages("unknown-session-id")
    end
  end

  describe "get_reasoning_steps/1" do
    test "returns reasoning steps list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, steps} = State.get_reasoning_steps(session.id)
      assert steps == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_reasoning_steps("unknown-session-id")
    end
  end

  describe "get_todos/1" do
    test "returns todos list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, todos} = State.get_todos(session.id)
      assert todos == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_todos("unknown-session-id")
    end
  end

  describe "get_tool_calls/1" do
    test "returns tool calls list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, tool_calls} = State.get_tool_calls(session.id)
      assert tool_calls == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_tool_calls("unknown-session-id")
    end
  end

  describe "append_message/2" do
    test "adds message to empty list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      message = %{
        id: "msg-1",
        role: :user,
        content: "Hello",
        timestamp: DateTime.utc_now()
      }

      assert {:ok, state} = State.append_message(session.id, message)
      assert length(state.messages) == 1
      assert hd(state.messages).id == "msg-1"
      assert hd(state.messages).content == "Hello"

      GenServer.stop(pid)
    end

    test "adds message to existing list maintaining order", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      message1 = %{id: "msg-1", role: :user, content: "First", timestamp: DateTime.utc_now()}

      message2 = %{
        id: "msg-2",
        role: :assistant,
        content: "Second",
        timestamp: DateTime.utc_now()
      }

      {:ok, _} = State.append_message(session.id, message1)
      {:ok, _state} = State.append_message(session.id, message2)

      # Use get_messages to verify order (internally stored reversed, reversed on read)
      {:ok, messages} = State.get_messages(session.id)
      assert length(messages) == 2
      assert Enum.at(messages, 0).id == "msg-1"
      assert Enum.at(messages, 1).id == "msg-2"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      assert {:error, :not_found} = State.append_message("unknown-session-id", message)
    end
  end

  describe "clear_messages/1" do
    test "clears all messages", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add some messages first
      message1 = %{id: "msg-1", role: :user, content: "First", timestamp: DateTime.utc_now()}

      message2 = %{
        id: "msg-2",
        role: :assistant,
        content: "Second",
        timestamp: DateTime.utc_now()
      }

      {:ok, _} = State.append_message(session.id, message1)
      {:ok, _} = State.append_message(session.id, message2)

      # Verify messages were added
      {:ok, messages_before} = State.get_messages(session.id)
      assert length(messages_before) == 2

      # Clear messages
      assert {:ok, []} = State.clear_messages(session.id)

      # Verify messages are cleared
      {:ok, messages_after} = State.get_messages(session.id)
      assert messages_after == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.clear_messages("unknown-session-id")
    end
  end

  describe "start_streaming/2" do
    test "sets streaming state", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, state} = State.start_streaming(session.id, "msg-1")
      assert state.is_streaming == true
      assert state.streaming_message == ""
      assert state.streaming_message_id == "msg-1"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.start_streaming("unknown-session-id", "msg-1")
    end
  end

  describe "update_streaming/2" do
    test "appends chunks to streaming message", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.start_streaming(session.id, "msg-1")

      :ok = State.update_streaming(session.id, "Hello ")
      :ok = State.update_streaming(session.id, "world!")

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      assert state.streaming_message == "Hello world!"

      GenServer.stop(pid)
    end

    test "ignores chunks when not streaming", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Don't start streaming
      :ok = State.update_streaming(session.id, "ignored chunk")

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      assert state.streaming_message == nil
      assert state.is_streaming == false

      GenServer.stop(pid)
    end

    test "returns :ok for unknown session (silent ignore)" do
      assert :ok = State.update_streaming("unknown-session-id", "chunk")
    end
  end

  describe "end_streaming/1" do
    test "creates message and resets streaming state", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.start_streaming(session.id, "msg-1")
      :ok = State.update_streaming(session.id, "Hello world!")

      # Give cast time to process
      Process.sleep(10)

      {:ok, message} = State.end_streaming(session.id)
      assert message.id == "msg-1"
      assert message.role == :assistant
      assert message.content == "Hello world!"
      assert %DateTime{} = message.timestamp

      # Verify state is reset
      {:ok, state} = State.get_state(session.id)
      assert state.is_streaming == false
      assert state.streaming_message == nil
      assert state.streaming_message_id == nil

      # Verify message is in messages list
      assert length(state.messages) == 1
      assert hd(state.messages).id == "msg-1"

      GenServer.stop(pid)
    end

    test "returns :not_streaming when not streaming", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:error, :not_streaming} = State.end_streaming(session.id)

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.end_streaming("unknown-session-id")
    end
  end

  describe "streaming lifecycle" do
    test "complete streaming flow", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Start streaming
      {:ok, state1} = State.start_streaming(session.id, "response-1")
      assert state1.is_streaming == true

      # Send chunks
      :ok = State.update_streaming(session.id, "I am ")
      :ok = State.update_streaming(session.id, "an AI ")
      :ok = State.update_streaming(session.id, "assistant.")

      # Give casts time to process
      Process.sleep(10)

      # End streaming
      {:ok, message} = State.end_streaming(session.id)
      assert message.content == "I am an AI assistant."

      # Verify final state
      {:ok, final_state} = State.get_state(session.id)
      assert final_state.is_streaming == false
      assert length(final_state.messages) == 1

      GenServer.stop(pid)
    end
  end

  describe "set_scroll_offset/2" do
    test "updates scroll offset", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, state} = State.set_scroll_offset(session.id, 10)
      assert state.scroll_offset == 10

      # Update again
      {:ok, state2} = State.set_scroll_offset(session.id, 25)
      assert state2.scroll_offset == 25

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.set_scroll_offset("unknown-session-id", 10)
    end
  end

  describe "update_todos/2" do
    test "replaces todo list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      todos = [
        %{id: "t-1", content: "Task 1", status: :pending},
        %{id: "t-2", content: "Task 2", status: :in_progress}
      ]

      assert {:ok, state} = State.update_todos(session.id, todos)
      assert length(state.todos) == 2
      assert Enum.at(state.todos, 0).id == "t-1"
      assert Enum.at(state.todos, 1).id == "t-2"

      # Replace with new list
      new_todos = [%{id: "t-3", content: "Task 3", status: :completed}]
      {:ok, state2} = State.update_todos(session.id, new_todos)
      assert length(state2.todos) == 1
      assert hd(state2.todos).id == "t-3"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.update_todos("unknown-session-id", [])
    end
  end

  describe "add_reasoning_step/2" do
    test "appends reasoning step", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      step1 = %{id: "r-1", content: "Analyzing request...", timestamp: DateTime.utc_now()}
      step2 = %{id: "r-2", content: "Planning approach...", timestamp: DateTime.utc_now()}

      {:ok, _state1} = State.add_reasoning_step(session.id, step1)
      {:ok, steps1} = State.get_reasoning_steps(session.id)
      assert length(steps1) == 1
      assert hd(steps1).id == "r-1"

      {:ok, _state2} = State.add_reasoning_step(session.id, step2)
      # Use get_reasoning_steps to verify order (internally stored reversed, reversed on read)
      {:ok, steps2} = State.get_reasoning_steps(session.id)
      assert length(steps2) == 2
      assert Enum.at(steps2, 1).id == "r-2"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      step = %{id: "r-1", content: "Test", timestamp: DateTime.utc_now()}
      assert {:error, :not_found} = State.add_reasoning_step("unknown-session-id", step)
    end
  end

  describe "clear_reasoning_steps/1" do
    test "clears reasoning steps", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add some steps first
      step1 = %{id: "r-1", content: "Step 1", timestamp: DateTime.utc_now()}
      step2 = %{id: "r-2", content: "Step 2", timestamp: DateTime.utc_now()}
      {:ok, _} = State.add_reasoning_step(session.id, step1)
      {:ok, _} = State.add_reasoning_step(session.id, step2)

      # Verify steps were added
      {:ok, state_before} = State.get_state(session.id)
      assert length(state_before.reasoning_steps) == 2

      # Clear steps
      assert {:ok, []} = State.clear_reasoning_steps(session.id)

      # Verify steps are cleared
      {:ok, state_after} = State.get_state(session.id)
      assert state_after.reasoning_steps == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.clear_reasoning_steps("unknown-session-id")
    end
  end

  describe "add_tool_call/2" do
    test "appends tool call", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      tool_call1 = %{
        id: "tc-1",
        name: "read_file",
        arguments: %{"path" => "/test.txt"},
        result: nil,
        status: :pending,
        timestamp: DateTime.utc_now()
      }

      tool_call2 = %{
        id: "tc-2",
        name: "write_file",
        arguments: %{"path" => "/out.txt", "content" => "hello"},
        result: nil,
        status: :pending,
        timestamp: DateTime.utc_now()
      }

      {:ok, _state1} = State.add_tool_call(session.id, tool_call1)
      {:ok, calls1} = State.get_tool_calls(session.id)
      assert length(calls1) == 1
      assert hd(calls1).name == "read_file"

      {:ok, _state2} = State.add_tool_call(session.id, tool_call2)
      # Use get_tool_calls to verify order (internally stored reversed, reversed on read)
      {:ok, calls2} = State.get_tool_calls(session.id)
      assert length(calls2) == 2
      assert Enum.at(calls2, 1).name == "write_file"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      tool_call = %{
        id: "tc-1",
        name: "test",
        arguments: %{},
        result: nil,
        status: :pending,
        timestamp: DateTime.utc_now()
      }

      assert {:error, :not_found} = State.add_tool_call("unknown-session-id", tool_call)
    end
  end

  describe "prompt_history" do
    test "initializes with empty prompt_history list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.prompt_history == []

      GenServer.stop(pid)
    end

    test "get_prompt_history/1 returns empty list for new session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, history} = State.get_prompt_history(session.id)
      assert history == []

      GenServer.stop(pid)
    end

    test "get_prompt_history/1 returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_prompt_history("unknown-session-id")
    end

    test "add_to_prompt_history/2 adds prompt to history", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, history} = State.add_to_prompt_history(session.id, "Hello world")
      assert history == ["Hello world"]

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 prepends new prompts (newest first)", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.add_to_prompt_history(session.id, "First")
      {:ok, _} = State.add_to_prompt_history(session.id, "Second")
      {:ok, history} = State.add_to_prompt_history(session.id, "Third")

      assert history == ["Third", "Second", "First"]

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 ignores empty prompts", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.add_to_prompt_history(session.id, "Hello")
      {:ok, history} = State.add_to_prompt_history(session.id, "")
      assert history == ["Hello"]

      {:ok, history} = State.add_to_prompt_history(session.id, "   ")
      assert history == ["Hello"]

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 enforces max history limit", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add more than max (100) prompts
      for i <- 1..110 do
        State.add_to_prompt_history(session.id, "Prompt #{i}")
      end

      {:ok, history} = State.get_prompt_history(session.id)

      # Should be capped at 100
      assert length(history) == 100
      # Most recent should be first
      assert hd(history) == "Prompt 110"
      # Oldest should be Prompt 11 (first 10 were evicted)
      assert List.last(history) == "Prompt 11"

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 returns :not_found for unknown session" do
      assert {:error, :not_found} = State.add_to_prompt_history("unknown-session-id", "Hello")
    end

    test "set_prompt_history/2 sets entire history", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      history = ["Newest", "Middle", "Oldest"]
      assert {:ok, ^history} = State.set_prompt_history(session.id, history)

      assert {:ok, ^history} = State.get_prompt_history(session.id)

      GenServer.stop(pid)
    end

    test "set_prompt_history/2 enforces max history limit", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Create a history with more than 100 items
      large_history = for i <- 1..150, do: "Prompt #{i}"

      {:ok, history} = State.set_prompt_history(session.id, large_history)

      # Should be capped at 100
      assert length(history) == 100
      # First 100 items should be preserved
      assert hd(history) == "Prompt 1"
      assert List.last(history) == "Prompt 100"

      GenServer.stop(pid)
    end

    test "set_prompt_history/2 returns :not_found for unknown session" do
      assert {:error, :not_found} = State.set_prompt_history("unknown-session-id", ["Hello"])
    end
  end
end
