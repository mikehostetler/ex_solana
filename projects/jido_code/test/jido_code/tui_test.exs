defmodule JidoCode.TUITest do
  use ExUnit.Case, async: false

  alias Jido.AI.Keyring
  alias JidoCode.Settings
  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias TermUI.Event
  alias TermUI.Widgets.TextInput

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
      _ -> String.to_atom("#{provider}_api_key")
    end
  end

  setup do
    # Clear settings cache before each test
    Settings.clear_cache()

    # Save and remove local settings file temporarily to avoid test interference
    settings_path = Settings.local_path()
    backup_path = settings_path <> ".bak"

    if File.exists?(settings_path) do
      File.rename(settings_path, backup_path)
    end

    on_exit(fn ->
      # Restore settings file after test
      if File.exists?(backup_path) do
        File.rename(backup_path, settings_path)
      end

      Settings.clear_cache()
    end)

    :ok
  end

  # Helper to create a TextInput state with given value
  # Cursor is positioned at the end of the text (simulating user having typed it)
  defp create_text_input(value \\ "") do
    props = TextInput.new(
      value: value,
      placeholder: "Type a message...",
      width: 76,
      enter_submits: true
    )
    {:ok, state} = TextInput.init(props)
    state = TextInput.set_focused(state, true)

    # Move cursor to end of text (simulating user having typed this text)
    if value != "" do
      %{state | cursor_col: String.length(value)}
    else
      state
    end
  end

  # Helper to get text value from TextInput state
  defp get_input_value(model) do
    TextInput.get_value(model.text_input)
  end

  describe "Model struct" do
    test "has correct default values" do
      model = %Model{text_input: create_text_input()}

      assert get_input_value(model) == ""
      assert model.messages == []
      assert model.agent_status == :unconfigured
      assert model.config == %{provider: nil, model: nil}
      assert model.reasoning_steps == []
      assert model.window == {80, 24}
    end

    test "can be created with custom values" do
      model = %Model{
        text_input: create_text_input("test input"),
        messages: [%{role: :user, content: "hello", timestamp: DateTime.utc_now()}],
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        reasoning_steps: [%{step: "thinking", status: :active}],
        window: {120, 40}
      }

      assert get_input_value(model) == "test input"
      assert length(model.messages) == 1
      assert model.agent_status == :idle
      assert model.config.provider == "anthropic"
      assert model.window == {120, 40}
    end
  end

  describe "init/1" do
    test "returns a Model struct" do
      model = TUI.init([])
      assert %Model{} = model
    end

    test "subscribes to PubSub tui.events topic" do
      _model = TUI.init([])

      # Verify subscription by broadcasting and receiving
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:test_message, "hello"})
      assert_receive {:test_message, "hello"}, 1000
    end

    test "sets agent_status to :unconfigured when no provider" do
      # Ensure no settings file exists (use empty settings)
      model = TUI.init([])

      # Without settings file, provider and model will be nil
      assert model.agent_status == :unconfigured
    end

    test "initializes with empty messages list" do
      model = TUI.init([])
      assert model.messages == []
    end

    test "initializes with empty text input" do
      model = TUI.init([])
      assert get_input_value(model) == ""
    end

    test "initializes with empty reasoning steps" do
      model = TUI.init([])
      assert model.reasoning_steps == []
    end
  end

  describe "determine_status/1" do
    test "returns :unconfigured when provider is nil" do
      config = %{provider: nil, model: "gpt-4"}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when model is nil" do
      config = %{provider: "openai", model: nil}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when both are nil" do
      config = %{provider: nil, model: nil}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :idle when both provider and model are set" do
      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}
      assert TUI.determine_status(config) == :idle
    end
  end

  describe "event_to_msg/2" do
    test "Ctrl+C returns {:msg, :quit}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("c", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :quit}
    end

    test "Ctrl+R returns {:msg, :toggle_reasoning}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("r", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_reasoning}
    end

    test "Ctrl+T returns {:msg, :toggle_tool_details}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("t", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_tool_details}
    end

    test "up arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key(:up)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "down arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key(:down)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "resize event returns {:msg, {:resize, width, height}}" do
      model = %Model{text_input: create_text_input()}
      event = Event.resize(120, 40)

      assert TUI.event_to_msg(event, model) == {:msg, {:resize, 120, 40}}
    end

    test "Enter key returns {:msg, {:input_submitted, value}}" do
      model = %Model{text_input: create_text_input("hello")}

      enter_event = Event.key(:enter)
      assert {:msg, {:input_submitted, "hello"}} = TUI.event_to_msg(enter_event, model)
    end

    test "key events are forwarded to TextInput as {:msg, {:input_event, event}}" do
      model = %Model{text_input: create_text_input()}

      # Backspace key
      backspace_event = Event.key(:backspace)
      assert {:msg, {:input_event, ^backspace_event}} = TUI.event_to_msg(backspace_event, model)

      # Printable character (without ctrl modifier)
      char_result = TUI.event_to_msg(Event.key("a", char: "a"), model)
      assert {:msg, {:input_event, %Event.Key{key: "a"}}} = char_result
    end

    test "returns :ignore for unhandled events" do
      model = %Model{text_input: create_text_input()}

      # Mouse events
      assert TUI.event_to_msg(Event.mouse(:click, :left, 10, 10), model) == :ignore

      # Focus events
      assert TUI.event_to_msg(Event.focus(:gained), model) == :ignore

      # Unknown events
      assert TUI.event_to_msg(:some_event, model) == :ignore
      assert TUI.event_to_msg(nil, model) == :ignore
    end
  end

  describe "update/2 - input events" do
    test "forwards key events to TextInput widget" do
      model = %Model{text_input: create_text_input("hel")}

      # Simulate typing 'l' via input_event
      event = Event.key("l", char: "l")
      {new_model, commands} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == "hell"
      assert commands == []
    end

    test "appends to empty text input" do
      model = %Model{text_input: create_text_input("")}

      event = Event.key("a", char: "a")
      {new_model, _} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == "a"
    end

    test "handles multiple characters" do
      model = %Model{text_input: create_text_input("")}

      {model1, _} = TUI.update({:input_event, Event.key("h", char: "h")}, model)
      {model2, _} = TUI.update({:input_event, Event.key("i", char: "i")}, model1)

      assert get_input_value(model2) == "hi"
    end
  end

  describe "update/2 - backspace via input_event" do
    test "removes last character from text input" do
      model = %Model{text_input: create_text_input("hello")}

      event = Event.key(:backspace)
      {new_model, commands} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == "hell"
      assert commands == []
    end

    test "does nothing on empty input" do
      model = %Model{text_input: create_text_input("")}

      event = Event.key(:backspace)
      {new_model, _} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == ""
    end

    test "handles single character input" do
      model = %Model{text_input: create_text_input("a")}

      event = Event.key(:backspace)
      {new_model, _} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == ""
    end
  end

  describe "update/2 - input_submitted" do
    test "does nothing with empty input" do
      model = %Model{text_input: create_text_input(""), messages: []}

      {new_model, _} = TUI.update({:input_submitted, ""}, model)

      assert get_input_value(new_model) == ""
      assert new_model.messages == []
    end

    test "does nothing with whitespace-only input" do
      model = %Model{text_input: create_text_input("   "), messages: []}

      {new_model, _} = TUI.update({:input_submitted, "   "}, model)

      assert new_model.messages == []
    end

    test "shows config error when provider is nil" do
      model = %Model{
        text_input: create_text_input("hello"),
        messages: [],
        config: %{provider: nil, model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "configure a model"
    end

    test "shows config error when model is nil" do
      model = %Model{
        text_input: create_text_input("hello"),
        messages: [],
        config: %{provider: "test", model: nil}
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "configure a model"
    end

    test "handles command input with / prefix" do
      model = %Model{
        text_input: create_text_input("/help"),
        messages: [],
        config: %{provider: "test", model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "/help"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "Available commands"
    end

    test "/config command shows current configuration" do
      model = %Model{
        text_input: create_text_input("/config"),
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"}
      }

      {new_model, _} = TUI.update({:input_submitted, "/config"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).content =~ "Provider: anthropic"
      assert hd(new_model.messages).content =~ "Model: claude-3-5-sonnet"
    end

    test "/provider command updates config and status" do
      model = %Model{
        text_input: create_text_input("/provider anthropic"),
        messages: [],
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured
      }

      {new_model, _} = TUI.update({:input_submitted, "/provider anthropic"}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == nil
      # Still unconfigured because model is nil
      assert new_model.agent_status == :unconfigured
    end

    test "/model provider:model command updates config and status" do
      setup_api_key("anthropic")

      model = %Model{
        text_input: create_text_input("/model anthropic:claude-3-5-sonnet"),
        messages: [],
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured
      }

      {new_model, _} = TUI.update({:input_submitted, "/model anthropic:claude-3-5-sonnet"}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == "claude-3-5-sonnet"
      # Now configured - status should be idle
      assert new_model.agent_status == :idle

      cleanup_api_key("anthropic")
    end

    test "unknown command shows error" do
      model = %Model{
        text_input: create_text_input("/unknown_cmd"),
        messages: [],
        config: %{provider: "test", model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "/unknown_cmd"}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "Unknown command"
    end

    test "shows agent not found error when agent not started" do
      model = %Model{
        text_input: create_text_input("hello"),
        messages: [],
        config: %{provider: "test", model: "test"},
        agent_name: :nonexistent_agent
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      # Should have user message and error message
      # Messages are stored in reverse order (newest first)
      assert length(new_model.messages) == 2
      assert Enum.at(new_model.messages, 0).role == :system
      assert Enum.at(new_model.messages, 0).content =~ "not running"
      assert Enum.at(new_model.messages, 1).role == :user
      assert new_model.agent_status == :error
    end

    @tag :requires_api_key
    @tag :skip
    test "sets status to processing when dispatching to agent" do
      # This test requires a real API key since the agent runs in a separate process
      # and cannot see session-scoped test values. Skip for now.
      setup_api_key("anthropic")

      # Start a mock agent for this test
      {:ok, _pid} =
        JidoCode.AgentSupervisor.start_agent(%{
          name: :test_llm_agent,
          module: JidoCode.Agents.LLMAgent,
          args: [provider: :anthropic, model: "claude-3-5-haiku-latest"]
        })

      model = %Model{
        text_input: create_text_input("hello"),
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-latest"},
        agent_name: :test_llm_agent
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :user
      assert hd(new_model.messages).content == "hello"
      assert new_model.agent_status == :processing

      # Cleanup
      JidoCode.AgentSupervisor.stop_agent(:test_llm_agent)
      cleanup_api_key("anthropic")
    end

    test "trims whitespace from input before processing" do
      model = %Model{
        text_input: create_text_input("  /help  "),
        messages: [],
        config: %{provider: "test", model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "  /help  "}, model)

      # Command should be received without leading whitespace
      assert hd(new_model.messages).content =~ "/help"
    end
  end

  describe "update/2 - quit" do
    test "returns :quit command" do
      model = %Model{text_input: create_text_input()}

      {_new_model, commands} = TUI.update(:quit, model)

      assert commands == [:quit]
    end
  end

  describe "update/2 - resize" do
    test "updates window dimensions" do
      model = %Model{text_input: create_text_input(), window: {80, 24}}

      {new_model, commands} = TUI.update({:resize, 120, 40}, model)

      assert new_model.window == {120, 40}
      assert commands == []
    end
  end

  describe "update/2 - agent messages" do
    test "handles agent_response" do
      model = %Model{text_input: create_text_input(), messages: []}

      {new_model, _} = TUI.update({:agent_response, "Hello!"}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :assistant
      assert hd(new_model.messages).content == "Hello!"
    end

    test "agent_response sets status to idle" do
      model = %Model{text_input: create_text_input(), messages: [], agent_status: :processing}

      {new_model, _} = TUI.update({:agent_response, "Done!"}, model)

      assert new_model.agent_status == :idle
    end

    test "unhandled messages are logged but do not change state" do
      # After message type normalization, :llm_response is no longer supported
      # It should go to the catch-all handler and not change state
      model = %Model{text_input: create_text_input(), messages: [], agent_status: :processing}

      {new_model, _} = TUI.update({:llm_response, "Hello from LLM!"}, model)

      # State should remain unchanged - message goes to catch-all
      assert new_model.messages == []
      assert new_model.agent_status == :processing
    end

    # Streaming tests
    test "stream_chunk appends to streaming_message" do
      model = %Model{text_input: create_text_input(), streaming_message: "", is_streaming: true}

      {new_model, _} = TUI.update({:stream_chunk, "Hello "}, model)

      assert new_model.streaming_message == "Hello "
      assert new_model.is_streaming == true

      # Append another chunk
      {new_model2, _} = TUI.update({:stream_chunk, "world!"}, new_model)

      assert new_model2.streaming_message == "Hello world!"
      assert new_model2.is_streaming == true
    end

    test "stream_chunk starts with nil streaming_message" do
      model = %Model{text_input: create_text_input(), streaming_message: nil, is_streaming: false}

      {new_model, _} = TUI.update({:stream_chunk, "Hello"}, model)

      assert new_model.streaming_message == "Hello"
      assert new_model.is_streaming == true
    end

    test "stream_end finalizes message and clears streaming state" do
      model = %Model{text_input: create_text_input(),
        messages: [],
        streaming_message: "Complete response",
        is_streaming: true,
        agent_status: :processing
      }

      {new_model, _} = TUI.update({:stream_end, "Complete response"}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :assistant
      assert hd(new_model.messages).content == "Complete response"
      assert new_model.streaming_message == nil
      assert new_model.is_streaming == false
      assert new_model.agent_status == :idle
    end

    test "stream_error shows error message and clears streaming" do
      model = %Model{text_input: create_text_input(),
        messages: [],
        streaming_message: "Partial",
        is_streaming: true,
        agent_status: :processing
      }

      {new_model, _} = TUI.update({:stream_error, :connection_failed}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "Streaming error"
      assert hd(new_model.messages).content =~ "connection_failed"
      assert new_model.streaming_message == nil
      assert new_model.is_streaming == false
      assert new_model.agent_status == :error
    end

    test "handles status_update" do
      model = %Model{text_input: create_text_input(), agent_status: :idle}

      {new_model, _} = TUI.update({:status_update, :processing}, model)

      assert new_model.agent_status == :processing
    end

    test "handles agent_status as alias for status_update" do
      model = %Model{text_input: create_text_input(), agent_status: :idle}

      {new_model, _} = TUI.update({:agent_status, :processing}, model)

      assert new_model.agent_status == :processing
    end

    test "handles config_change with atom keys" do
      model = %Model{text_input: create_text_input(), config: %{provider: nil, model: nil}}

      {new_model, _} =
        TUI.update({:config_change, %{provider: "anthropic", model: "claude"}}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == "claude"
      assert new_model.agent_status == :idle
    end

    test "handles config_change with string keys" do
      model = %Model{text_input: create_text_input(), config: %{provider: nil, model: nil}}

      {new_model, _} =
        TUI.update({:config_change, %{"provider" => "openai", "model" => "gpt-4"}}, model)

      assert new_model.config.provider == "openai"
      assert new_model.config.model == "gpt-4"
    end

    test "handles config_changed as alias for config_change" do
      model = %Model{text_input: create_text_input(), config: %{provider: nil, model: nil}}

      {new_model, _} = TUI.update({:config_changed, %{provider: "openai", model: "gpt-4"}}, model)

      assert new_model.config.provider == "openai"
      assert new_model.config.model == "gpt-4"
      assert new_model.agent_status == :idle
    end

    test "handles reasoning_step" do
      model = %Model{text_input: create_text_input(), reasoning_steps: []}
      step = %{step: "Thinking...", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(new_model.reasoning_steps) == 1
      assert hd(new_model.reasoning_steps) == step
    end

    test "handles clear_reasoning_steps" do
      model = %Model{text_input: create_text_input(), reasoning_steps: [%{step: "Step 1", status: :complete}]}

      {new_model, _} = TUI.update(:clear_reasoning_steps, model)

      assert new_model.reasoning_steps == []
    end
  end

  describe "message queueing" do
    test "agent_response adds to message queue" do
      model = %Model{text_input: create_text_input(), message_queue: []}

      {new_model, _} = TUI.update({:agent_response, "Hello!"}, model)

      assert length(new_model.message_queue) == 1
      {{:agent_response, "Hello!"}, _timestamp} = hd(new_model.message_queue)
    end

    test "status_update adds to message queue" do
      model = %Model{text_input: create_text_input(), message_queue: []}

      {new_model, _} = TUI.update({:status_update, :processing}, model)

      assert length(new_model.message_queue) == 1
      {{:status_update, :processing}, _timestamp} = hd(new_model.message_queue)
    end

    test "config_change adds to message queue" do
      model = %Model{text_input: create_text_input(), message_queue: []}

      {new_model, _} = TUI.update({:config_change, %{provider: "test"}}, model)

      assert length(new_model.message_queue) == 1
    end

    test "reasoning_step adds to message queue" do
      model = %Model{text_input: create_text_input(), message_queue: []}
      step = %{step: "Thinking", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(new_model.message_queue) == 1
    end

    test "message queue limits size to max_queue_size" do
      # Create a model with a queue at max size
      large_queue =
        Enum.map(1..100, fn i ->
          {{:test_message, i}, DateTime.utc_now()}
        end)

      model = %Model{text_input: create_text_input(), message_queue: large_queue}

      # Add one more message
      {new_model, _} = TUI.update({:agent_response, "New message"}, model)

      # Queue should still be at max size (100)
      assert length(new_model.message_queue) == 100

      # Most recent message should be first
      {{:agent_response, "New message"}, _} = hd(new_model.message_queue)
    end

    test "queue_message maintains LIFO order" do
      queue = []
      queue = TUI.queue_message(queue, :msg1)
      queue = TUI.queue_message(queue, :msg2)
      queue = TUI.queue_message(queue, :msg3)

      assert length(queue) == 3
      {:msg3, _} = Enum.at(queue, 0)
      {:msg2, _} = Enum.at(queue, 1)
      {:msg1, _} = Enum.at(queue, 2)
    end
  end

  describe "PubSub integration" do
    test "init subscribes to tui.events topic" do
      _model = TUI.init([])

      # Verify subscription by broadcasting and receiving
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:test_pubsub, "integration"})
      assert_receive {:test_pubsub, "integration"}, 1000
    end

    test "full message flow: agent_response via PubSub" do
      model = TUI.init([])

      # Simulate receiving a PubSub message
      msg = {:agent_response, "Test response from agent"}
      {new_model, _} = TUI.update(msg, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).content == "Test response from agent"
      assert hd(new_model.messages).role == :assistant
    end

    test "full message flow: status transitions" do
      model = TUI.init([])

      # Start processing
      {model, _} = TUI.update({:agent_status, :processing}, model)
      assert model.agent_status == :processing

      # Complete with response
      {model, _} = TUI.update({:agent_response, "Done!"}, model)
      assert length(model.messages) == 1

      # Back to idle
      {model, _} = TUI.update({:agent_status, :idle}, model)
      assert model.agent_status == :idle
    end

    test "full message flow: reasoning steps accumulation" do
      model = TUI.init([])

      # Simulate CoT reasoning flow
      {model, _} = TUI.update({:reasoning_step, %{step: "Understanding", status: :active}}, model)
      {model, _} = TUI.update({:reasoning_step, %{step: "Planning", status: :pending}}, model)
      {model, _} = TUI.update({:reasoning_step, %{step: "Executing", status: :pending}}, model)

      # Steps are stored in reverse order (newest first)
      assert length(model.reasoning_steps) == 3
      assert Enum.at(model.reasoning_steps, 0).step == "Executing"
      assert Enum.at(model.reasoning_steps, 2).step == "Understanding"

      # Clear reasoning steps for next query
      {model, _} = TUI.update(:clear_reasoning_steps, model)
      assert model.reasoning_steps == []
    end

    test "rapid message handling doesn't exceed queue limit" do
      model = TUI.init([])

      # Simulate rapid message burst (150 messages)
      model =
        Enum.reduce(1..150, model, fn i, acc ->
          {new_model, _} = TUI.update({:agent_response, "Message #{i}"}, acc)
          new_model
        end)

      # Queue should be limited to 100
      assert length(model.message_queue) == 100

      # All 150 messages should be in the messages list
      assert length(model.messages) == 150
    end
  end

  describe "update/2 - unknown messages" do
    test "returns state unchanged for unknown messages" do
      model = %Model{text_input: create_text_input("test")}

      {new_model, commands} = TUI.update(:unknown_message, model)

      assert new_model == model
      assert commands == []
    end
  end

  describe "view/1" do
    test "returns a render tree" do
      model = %Model{
        text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"}
      }

      view = TUI.view(model)

      # View should return a RenderNode with type :box (border wrapper)
      assert %TermUI.Component.RenderNode{type: :box} = view
    end

    test "renders unconfigured status message" do
      model = %Model{text_input: create_text_input(),
        agent_status: :unconfigured,
        config: %{provider: nil, model: nil}
      }

      view = TUI.view(model)

      # Convert view tree to string for inspection
      view_text = inspect(view)

      assert view_text =~ "Not Configured" or view_text =~ "unconfigured"
    end

    test "renders configured status" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "anthropic" or view_text =~ "Idle"
    end

    test "main view has border structure when configured" do
      model = %Model{
        text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        messages: []
      }

      view = TUI.view(model)

      # Main view is wrapped in a border box
      # The box contains a stack with: top border, middle (with content), bottom border
      assert %TermUI.Component.RenderNode{type: :box, children: [inner_stack]} = view
      assert %TermUI.Component.RenderNode{type: :stack, children: border_children} = inner_stack
      # Border children: top border, middle row (with content), bottom border
      assert length(border_children) == 3
    end

    test "status bar shows provider and model" do
      model = %Model{
        text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "openai", model: "gpt-4"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "openai:gpt-4"
    end

    test "status bar shows keyboard hints" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+C"
    end

    test "conversation shows empty message when no messages" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        messages: []
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "No messages yet"
    end

    test "conversation shows user messages with You: prefix" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        messages: [
          %{role: :user, content: "Hello there", timestamp: DateTime.utc_now()}
        ]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "You:"
      assert view_text =~ "Hello there"
    end

    test "conversation shows assistant messages with Assistant: prefix" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        messages: [
          %{role: :assistant, content: "Hi! How can I help?", timestamp: DateTime.utc_now()}
        ]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Assistant:"
      assert view_text =~ "Hi! How can I help?"
    end

    test "input bar shows current text" do
      model = %Model{
        text_input: create_text_input("typing something"),
        agent_status: :idle,
        config: %{provider: "test", model: "test"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "typing something"
    end

    test "input bar shows prompt indicator" do
      model = %Model{
        text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      # Should show > prompt
      assert view_text =~ ">"
    end

    test "status bar shows processing status" do
      model = %Model{text_input: create_text_input(),
        agent_status: :processing,
        config: %{provider: "test", model: "test"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      # Status changed to "Streaming..." for better UX during streaming responses
      assert view_text =~ "Streaming"
    end

    test "status bar shows error status" do
      model = %Model{text_input: create_text_input(),
        agent_status: :error,
        config: %{provider: "test", model: "test"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Error"
    end
  end

  describe "integration" do
    test "TUI module uses TermUI.Elm behaviour" do
      # Verify the module implements the required callbacks
      behaviours = JidoCode.TUI.__info__(:attributes)[:behaviour] || []
      assert TermUI.Elm in behaviours
    end

    test "Model struct is accessible via JidoCode.TUI.Model" do
      # Verify the nested module is accessible
      assert Code.ensure_loaded?(JidoCode.TUI.Model)
    end
  end

  describe "wrap_text/2" do
    test "returns single line for short text" do
      result = TUI.wrap_text("hello world", 80)
      assert result == ["hello world"]
    end

    test "wraps text at word boundaries" do
      result = TUI.wrap_text("hello world foo bar", 11)
      assert result == ["hello world", "foo bar"]
    end

    test "handles text exactly at max width" do
      result = TUI.wrap_text("hello", 5)
      assert result == ["hello"]
    end

    test "splits words longer than max width" do
      result = TUI.wrap_text("superlongword", 5)
      # First iteration splits at 5, then the remainder is handled
      assert result == ["super", "longword"]
    end

    test "handles empty string" do
      result = TUI.wrap_text("", 80)
      assert result == [""]
    end

    test "handles single word" do
      result = TUI.wrap_text("word", 80)
      assert result == ["word"]
    end

    test "handles multiple spaces" do
      result = TUI.wrap_text("hello world", 80)
      # String.split on single space produces empty strings
      assert is_list(result)
    end

    test "handles invalid max_width" do
      result = TUI.wrap_text("hello", 0)
      assert result == [""]

      result = TUI.wrap_text("hello", -5)
      assert result == [""]
    end
  end

  describe "format_timestamp/1" do
    test "formats datetime as [HH:MM]" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[14:32]"
    end

    test "pads single digit hours and minutes" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[09:05:00], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[09:05]"
    end

    test "handles midnight" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[00:00:00], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[00:00]"
    end

    test "handles end of day" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[23:59:59], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[23:59]"
    end
  end

  describe "max_scroll_offset/1" do
    test "returns 0 when no messages" do
      model = %Model{text_input: create_text_input(), messages: [], window: {80, 24}}
      assert TUI.max_scroll_offset(model) == 0
    end

    test "returns 0 when messages fit in view" do
      model = %Model{text_input: create_text_input(),
        messages: [
          %{role: :user, content: "hello", timestamp: DateTime.utc_now()}
        ],
        window: {80, 24}
      }

      assert TUI.max_scroll_offset(model) == 0
    end

    test "returns positive offset when messages exceed view" do
      # Create many messages to exceed the view height
      messages =
        Enum.map(1..50, fn i ->
          %{role: :user, content: "Message #{i}", timestamp: DateTime.utc_now()}
        end)

      model = %Model{text_input: create_text_input(), messages: messages, window: {80, 10}}

      # With 50 messages and height 10 (8 available after status/input)
      # max_offset should be positive
      assert TUI.max_scroll_offset(model) > 0
    end
  end

  describe "scroll navigation" do
    alias JidoCode.TUI.Widgets.ConversationView

    test "up arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{}
      event = Event.key(:up)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "down arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{}
      event = Event.key(:down)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "conversation_event delegates to ConversationView.handle_event" do
      # Create a ConversationView with scrollable content
      cv_messages = Enum.map(1..50, fn i ->
        %{id: "#{i}", role: :user, content: "Message #{i}", timestamp: DateTime.utc_now()}
      end)
      cv_props = ConversationView.new(messages: cv_messages, viewport_width: 80, viewport_height: 10)
      cv_state = ConversationView.init(cv_props)

      model = %Model{
        text_input: create_text_input(),
        conversation_view: cv_state,
        window: {80, 24}
      }

      # Down arrow should trigger scroll in ConversationView
      event = Event.key(:down)
      {new_model, _} = TUI.update({:conversation_event, event}, model)

      # ConversationView should have scrolled
      assert new_model.conversation_view != nil
      assert new_model.conversation_view.scroll_offset == 1
    end

    test "conversation_event ignored when conversation_view is nil" do
      model = %Model{
        text_input: create_text_input(),
        conversation_view: nil,
        window: {80, 24}
      }

      event = Event.key(:down)
      {new_model, _} = TUI.update({:conversation_event, event}, model)

      # Should be unchanged
      assert new_model.conversation_view == nil
    end

    test "scroll keys route to conversation_event" do
      model = %Model{text_input: create_text_input()}

      for key <- [:up, :down, :page_up, :page_down, :home, :end] do
        event = Event.key(key)
        assert {:msg, {:conversation_event, ^event}} = TUI.event_to_msg(event, model)
      end
    end
  end

  describe "message display with timestamps" do
    test "messages include timestamp in view" do
      timestamp = DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")

      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        messages: [
          %{role: :user, content: "Hello", timestamp: timestamp}
        ]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "[14:32]"
      assert view_text =~ "You:"
      assert view_text =~ "Hello"
    end
  end

  describe "Model scroll_offset field" do
    test "has default value of 0" do
      model = %Model{}
      assert model.scroll_offset == 0
    end

    test "init sets scroll_offset to 0" do
      model = TUI.init([])
      assert model.scroll_offset == 0
    end
  end

  describe "show_reasoning field" do
    test "has default value of false" do
      model = %Model{}
      assert model.show_reasoning == false
    end

    test "init sets show_reasoning to false" do
      model = TUI.init([])
      assert model.show_reasoning == false
    end
  end

  describe "toggle_reasoning" do
    test "Ctrl+R returns {:msg, :toggle_reasoning}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("r", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_reasoning}
    end

    test "plain 'r' key is forwarded to TextInput" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("r", char: "r")

      assert {:msg, {:input_event, %Event.Key{key: "r"}}} = TUI.event_to_msg(event, model)
    end

    test "toggle_reasoning flips show_reasoning from false to true" do
      model = %Model{text_input: create_text_input(), show_reasoning: false}

      {new_model, commands} = TUI.update(:toggle_reasoning, model)

      assert new_model.show_reasoning == true
      assert commands == []
    end

    test "toggle_reasoning flips show_reasoning from true to false" do
      model = %Model{text_input: create_text_input(), show_reasoning: true}

      {new_model, commands} = TUI.update(:toggle_reasoning, model)

      assert new_model.show_reasoning == false
      assert commands == []
    end
  end

  describe "render_reasoning/1" do
    test "renders empty state when no reasoning steps" do
      model = %Model{text_input: create_text_input(), reasoning_steps: []}

      view = TUI.render_reasoning(model)
      view_text = inspect(view)

      assert view_text =~ "Reasoning"
      assert view_text =~ "No reasoning steps"
    end

    test "renders pending step with circle indicator" do
      model = %Model{text_input: create_text_input(),
        reasoning_steps: [%{step: "Understanding query", status: :pending}]
      }

      view = TUI.render_reasoning(model)
      view_text = inspect(view)

      assert view_text =~ "○"
      assert view_text =~ "Understanding query"
    end

    test "renders active step with filled circle indicator" do
      model = %Model{text_input: create_text_input(),
        reasoning_steps: [%{step: "Analyzing code", status: :active}]
      }

      view = TUI.render_reasoning(model)
      view_text = inspect(view)

      assert view_text =~ "●"
      assert view_text =~ "Analyzing code"
    end

    test "renders complete step with checkmark indicator" do
      model = %Model{text_input: create_text_input(),
        reasoning_steps: [%{step: "Found solution", status: :complete}]
      }

      view = TUI.render_reasoning(model)
      view_text = inspect(view)

      assert view_text =~ "✓"
      assert view_text =~ "Found solution"
    end

    test "renders multiple steps with different statuses" do
      model = %Model{text_input: create_text_input(),
        reasoning_steps: [
          %{step: "Step 1", status: :complete},
          %{step: "Step 2", status: :active},
          %{step: "Step 3", status: :pending}
        ]
      }

      view = TUI.render_reasoning(model)
      view_text = inspect(view)

      assert view_text =~ "✓"
      assert view_text =~ "●"
      assert view_text =~ "○"
      assert view_text =~ "Step 1"
      assert view_text =~ "Step 2"
      assert view_text =~ "Step 3"
    end

    test "renders confidence score when present" do
      model = %Model{text_input: create_text_input(),
        reasoning_steps: [%{step: "Validated", status: :complete, confidence: 0.92}]
      }

      view = TUI.render_reasoning(model)
      view_text = inspect(view)

      assert view_text =~ "confidence: 0.92"
    end
  end

  describe "render_reasoning_compact/1" do
    test "renders compact format for empty steps" do
      model = %Model{text_input: create_text_input(), reasoning_steps: []}

      view = TUI.render_reasoning_compact(model)
      view_text = inspect(view)

      assert view_text =~ "Reasoning"
      assert view_text =~ "none"
    end

    test "renders compact format with multiple steps" do
      model = %Model{text_input: create_text_input(),
        reasoning_steps: [
          %{step: "Step 1", status: :complete},
          %{step: "Step 2", status: :active}
        ]
      }

      view = TUI.render_reasoning_compact(model)
      view_text = inspect(view)

      assert view_text =~ "✓"
      assert view_text =~ "●"
      assert view_text =~ "│"
    end
  end

  describe "reasoning panel in view" do
    test "status bar shows Ctrl+R: Reasoning when panel is hidden" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_reasoning: false
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+R: Reasoning"
    end

    test "status bar shows Ctrl+R: Hide when panel is visible" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_reasoning: true
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+R: Hide"
    end

    test "view includes reasoning panel when show_reasoning is true (wide terminal)" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_reasoning: true,
        reasoning_steps: [%{step: "Test step", status: :active}],
        window: {120, 40}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Reasoning"
      assert view_text =~ "Test step"
    end

    test "view uses compact reasoning in narrow terminal" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_reasoning: true,
        reasoning_steps: [%{step: "Test step", status: :active}],
        window: {80, 24}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      # Compact view uses │ separator
      assert view_text =~ "Reasoning"
    end

    test "view does not include reasoning panel when show_reasoning is false" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_reasoning: false,
        reasoning_steps: [%{step: "Hidden step", status: :active}]
      }

      view = TUI.view(model)

      # Main view is wrapped in a border box
      # The box contains a stack with: top border, middle row, bottom border
      assert %TermUI.Component.RenderNode{type: :box, children: [inner_stack]} = view
      assert %TermUI.Component.RenderNode{type: :stack, children: border_children} = inner_stack
      assert length(border_children) == 3
    end
  end

  describe "status_style/1" do
    test "idle status returns green style" do
      style = TUI.status_style(:idle)
      assert style.fg == :green
      assert style.bg == :blue
    end

    test "processing status returns yellow style" do
      style = TUI.status_style(:processing)
      assert style.fg == :yellow
      assert style.bg == :blue
    end

    test "error status returns red style" do
      style = TUI.status_style(:error)
      assert style.fg == :red
      assert style.bg == :blue
    end

    test "unconfigured status returns dim red style" do
      style = TUI.status_style(:unconfigured)
      assert style.fg == :red
      assert style.bg == :blue
      assert :dim in style.attrs
    end
  end

  describe "config_style/1" do
    test "no provider returns red style" do
      style = TUI.config_style(%{provider: nil, model: "test"})
      assert style.fg == :red
    end

    test "no model returns yellow style" do
      style = TUI.config_style(%{provider: "test", model: nil})
      assert style.fg == :yellow
    end

    test "fully configured returns white style" do
      style = TUI.config_style(%{provider: "test", model: "test"})
      assert style.fg == :white
    end
  end

  describe "help bar keyboard hints" do
    test "help bar includes Ctrl+M: Model hint" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+M: Model"
    end

    test "help bar includes Ctrl+C: Quit hint" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        # Use wider window to fit all help bar hints
        window: {120, 24}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+C: Quit"
    end
  end

  describe "CoT indicator in status bar" do
    test "shows [CoT] when reasoning steps have active step" do
      model = %Model{text_input: create_text_input(),
        agent_status: :processing,
        config: %{provider: "test", model: "test"},
        reasoning_steps: [%{step: "Thinking", status: :active}]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "[CoT]"
    end

    test "does not show [CoT] when no reasoning steps" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        reasoning_steps: []
      }

      view = TUI.view(model)
      view_text = inspect(view)

      refute view_text =~ "[CoT]"
    end

    test "does not show [CoT] when only pending/complete steps" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        reasoning_steps: [
          %{step: "Done", status: :complete},
          %{step: "Waiting", status: :pending}
        ]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      refute view_text =~ "[CoT]"
    end
  end

  describe "status bar color priority" do
    test "error state takes priority over other states" do
      model = %Model{text_input: create_text_input(),
        agent_status: :error,
        config: %{provider: "test", model: "test"},
        reasoning_steps: [%{step: "Active", status: :active}]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      # Error should show red in the view
      assert view_text =~ "Error"
    end

    test "unconfigured state shows appropriate warning" do
      model = %Model{text_input: create_text_input(),
        agent_status: :unconfigured,
        config: %{provider: nil, model: nil}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "No provider"
      assert view_text =~ "Not Configured"
    end
  end

  # ============================================================================
  # Tool Call Display Tests
  # ============================================================================

  describe "tool_calls and show_tool_details fields" do
    test "Model has default empty tool_calls list" do
      model = %Model{}
      assert model.tool_calls == []
    end

    test "Model has default false show_tool_details" do
      model = %Model{}
      assert model.show_tool_details == false
    end

    test "init sets tool_calls to empty list" do
      model = TUI.init([])
      assert model.tool_calls == []
    end

    test "init sets show_tool_details to false" do
      model = TUI.init([])
      assert model.show_tool_details == false
    end
  end

  describe "toggle_tool_details" do
    test "Ctrl+T returns {:msg, :toggle_tool_details}" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("t", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_tool_details}
    end

    test "plain 't' key is forwarded to TextInput" do
      model = %Model{text_input: create_text_input()}
      event = Event.key("t", char: "t")

      assert {:msg, {:input_event, %Event.Key{key: "t"}}} = TUI.event_to_msg(event, model)
    end

    test "toggle_tool_details flips show_tool_details from false to true" do
      model = %Model{text_input: create_text_input(), show_tool_details: false}

      {new_model, commands} = TUI.update(:toggle_tool_details, model)

      assert new_model.show_tool_details == true
      assert commands == []
    end

    test "toggle_tool_details flips show_tool_details from true to false" do
      model = %Model{text_input: create_text_input(), show_tool_details: true}

      {new_model, commands} = TUI.update(:toggle_tool_details, model)

      assert new_model.show_tool_details == false
      assert commands == []
    end
  end

  describe "update/2 - tool_call message" do
    test "adds tool call entry to tool_calls list" do
      model = %Model{text_input: create_text_input(), tool_calls: []}

      {new_model, _} =
        TUI.update({:tool_call, "read_file", %{"path" => "test.ex"}, "call_123"}, model)

      assert length(new_model.tool_calls) == 1
      entry = hd(new_model.tool_calls)
      assert entry.call_id == "call_123"
      assert entry.tool_name == "read_file"
      assert entry.params == %{"path" => "test.ex"}
      assert entry.result == nil
      assert %DateTime{} = entry.timestamp
    end

    test "appends to existing tool calls" do
      existing = %{
        call_id: "call_1",
        tool_name: "grep",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(), tool_calls: [existing]}

      {new_model, _} =
        TUI.update({:tool_call, "read_file", %{"path" => "test.ex"}, "call_2"}, model)

      # Tool calls are stored in reverse order (newest first)
      assert length(new_model.tool_calls) == 2
      assert Enum.at(new_model.tool_calls, 0).call_id == "call_2"
      assert Enum.at(new_model.tool_calls, 1).call_id == "call_1"
    end

    test "adds tool_call to message queue" do
      model = %Model{text_input: create_text_input(), tool_calls: [], message_queue: []}

      {new_model, _} =
        TUI.update({:tool_call, "read_file", %{"path" => "test.ex"}, "call_123"}, model)

      assert length(new_model.message_queue) == 1

      {{:tool_call, "read_file", %{"path" => "test.ex"}, "call_123"}, _ts} =
        hd(new_model.message_queue)
    end
  end

  describe "update/2 - tool_result message" do
    alias JidoCode.Tools.Result

    test "matches result to pending tool call by call_id" do
      pending = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{"path" => "test.ex"},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(), tool_calls: [pending]}

      result = Result.ok("call_123", "read_file", "file contents", 45)

      {new_model, _} = TUI.update({:tool_result, result}, model)

      assert length(new_model.tool_calls) == 1
      entry = hd(new_model.tool_calls)
      assert entry.result != nil
      assert entry.result.status == :ok
      assert entry.result.content == "file contents"
      assert entry.result.duration_ms == 45
    end

    test "does not modify unmatched tool calls" do
      pending1 = %{
        call_id: "call_1",
        tool_name: "read_file",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      pending2 = %{
        call_id: "call_2",
        tool_name: "grep",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(), tool_calls: [pending1, pending2]}

      result = Result.ok("call_1", "read_file", "content", 30)

      {new_model, _} = TUI.update({:tool_result, result}, model)

      assert Enum.at(new_model.tool_calls, 0).result != nil
      assert Enum.at(new_model.tool_calls, 1).result == nil
    end

    test "handles error results" do
      pending = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(), tool_calls: [pending]}

      result = Result.error("call_123", "read_file", "File not found", 12)

      {new_model, _} = TUI.update({:tool_result, result}, model)

      entry = hd(new_model.tool_calls)
      assert entry.result.status == :error
      assert entry.result.content == "File not found"
    end

    test "handles timeout results" do
      pending = %{
        call_id: "call_123",
        tool_name: "slow_op",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(), tool_calls: [pending]}

      result = Result.timeout("call_123", "slow_op", 30_000)

      {new_model, _} = TUI.update({:tool_result, result}, model)

      entry = hd(new_model.tool_calls)
      assert entry.result.status == :timeout
    end

    test "adds tool_result to message queue" do
      pending = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(), tool_calls: [pending], message_queue: []}

      result = Result.ok("call_123", "read_file", "content", 30)

      {new_model, _} = TUI.update({:tool_result, result}, model)

      assert length(new_model.message_queue) == 1
      {{:tool_result, ^result}, _ts} = hd(new_model.message_queue)
    end
  end

  describe "format_tool_call_entry/2" do
    alias JidoCode.Tools.Result

    test "formats pending tool call (no result yet)" do
      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{"path" => "test.ex"},
        result: nil,
        timestamp: DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")
      }

      lines = TUI.format_tool_call_entry(entry, false)

      assert length(lines) == 2
      # First line is the tool call
      call_text = inspect(Enum.at(lines, 0))
      assert call_text =~ "[14:32]"
      assert call_text =~ "⚙"
      assert call_text =~ "read_file"
      # Second line is "executing..."
      exec_text = inspect(Enum.at(lines, 1))
      assert exec_text =~ "executing"
    end

    test "formats successful tool result" do
      result = Result.ok("call_123", "read_file", "file contents", 45)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{"path" => "test.ex"},
        result: result,
        timestamp: DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")
      }

      lines = TUI.format_tool_call_entry(entry, false)

      assert length(lines) == 2
      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "✓"
      assert result_text =~ "[45ms]"
      assert result_text =~ "file contents"
    end

    test "formats error tool result" do
      result = Result.error("call_123", "read_file", "File not found", 12)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, false)

      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "✗"
      assert result_text =~ "File not found"
    end

    test "formats timeout tool result" do
      result = Result.timeout("call_123", "slow_op", 30_000)

      entry = %{
        call_id: "call_123",
        tool_name: "slow_op",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, false)

      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "⏱"
      assert result_text =~ "[30000ms]"
    end

    test "truncates long content when show_details is false" do
      long_content = String.duplicate("x", 200)
      result = Result.ok("call_123", "read_file", long_content, 45)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, false)

      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "[...]"
    end

    test "shows full content when show_details is true" do
      long_content = String.duplicate("x", 200)
      result = Result.ok("call_123", "read_file", long_content, 45)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, true)

      result_text = inspect(Enum.at(lines, 1))
      refute result_text =~ "[...]"
    end
  end

  describe "status bar tool hints" do
    test "status bar shows Ctrl+T: Tools when show_tool_details is false" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_tool_details: false
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+T: Tools"
    end

    test "status bar shows Ctrl+T: Hide when show_tool_details is true" do
      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        show_tool_details: true
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "Ctrl+T: Hide"
    end
  end

  describe "tool calls in conversation view" do
    alias JidoCode.Tools.Result

    test "conversation shows tool calls" do
      result = Result.ok("call_123", "read_file", "file contents", 45)

      tool_call = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{"path" => "test.ex"},
        result: result,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        messages: [],
        tool_calls: [tool_call]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "⚙"
      assert view_text =~ "read_file"
      assert view_text =~ "✓"
    end

    test "conversation shows tool call without empty message text" do
      tool_call = %{
        call_id: "call_123",
        tool_name: "grep",
        params: %{"pattern" => "TODO"},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{text_input: create_text_input(),
        agent_status: :idle,
        config: %{provider: "test", model: "test"},
        messages: [],
        tool_calls: [tool_call]
      }

      view = TUI.view(model)
      view_text = inspect(view)

      # Should NOT show "No messages yet" when there are tool calls
      refute view_text =~ "No messages yet"
      assert view_text =~ "grep"
    end
  end
end
