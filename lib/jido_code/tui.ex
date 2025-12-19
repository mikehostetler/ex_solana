defmodule JidoCode.TUI do
  @moduledoc """
  Terminal User Interface for JidoCode using TermUI's Elm Architecture.

  This module implements the main TUI application following the Elm Architecture
  pattern: `init/1` for initial state, `update/2` for state transitions, and
  `view/1` for rendering.

  ## Architecture

  The TUI connects to the agent system via Phoenix PubSub, receiving events for:
  - Agent responses
  - Status changes (idle, processing, error)
  - Reasoning steps (Chain-of-Thought progress)
  - Tool calls and results

  ## Usage

      # Start the TUI (blocks until quit)
      JidoCode.TUI.run()

      # Or start via Runtime directly
      TermUI.Runtime.run(root: JidoCode.TUI)

  ## Model

  The TUI state contains:
  - `input_buffer` - Current text being typed
  - `messages` - Conversation history (stored in reverse order for O(1) prepend)
  - `agent_status` - Current agent state (:idle, :processing, :error, :unconfigured)
  - `config` - Provider and model configuration
  - `reasoning_steps` - Chain-of-Thought progress (stored in reverse order)
  - `tool_calls` - Tool execution history with results (stored in reverse order)
  - `window` - Terminal dimensions
  """

  use TermUI.Elm

  require Logger

  alias Jido.AI.Keyring
  alias JidoCode.Agents.LLMAgent
  alias JidoCode.AgentSupervisor
  alias JidoCode.Commands
  alias JidoCode.PubSubTopics
  alias JidoCode.Reasoning.QueryClassifier
  alias JidoCode.Settings
  alias JidoCode.Tools.Result
  alias JidoCode.TUI.Clipboard
  alias JidoCode.TUI.MessageHandlers
  alias JidoCode.TUI.ViewHelpers
  alias JidoCode.TUI.Widgets.ConversationView
  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Widget.PickList
  alias TermUI.Widgets.TextInput
  alias TermUI.Widgets.Viewport

  # ============================================================================
  # Message Types
  # ============================================================================

  # Messages handled by update/2:
  #
  # Keyboard input:
  #   {:key_input, char}     - Printable character typed
  #   {:key_input, :backspace} - Backspace pressed
  #   {:submit}              - Enter key pressed
  #   :quit                  - Ctrl+C pressed
  #
  # PubSub messages (from agent):
  #   {:agent_response, content}  - Agent response received
  #   {:status_update, status}    - Agent status changed
  #   {:config_change, config}    - Configuration changed
  #   {:reasoning_step, step}     - Chain-of-Thought step

  @type msg ::
          {:key_input, String.t() | :backspace}
          | {:submit}
          | :quit
          | {:agent_response, String.t()}
          | {:agent_status, Model.agent_status()}
          | {:status_update, Model.agent_status()}
          | {:config_changed, map()}
          | {:config_change, map()}
          | {:reasoning_step, Model.reasoning_step()}
          | :clear_reasoning_steps
          | {:tool_call, String.t(), map(), String.t()}
          | {:tool_result, Result.t()}
          | :toggle_tool_details
          | {:stream_chunk, String.t()}
          | {:stream_end, String.t()}
          | {:stream_error, term()}

  # Maximum number of messages to keep in the debug queue
  @max_queue_size 100

  # ============================================================================
  # Model
  # ============================================================================

  defmodule Model do
    @moduledoc """
    The TUI application state.
    """

    @type message :: %{
            role: :user | :assistant | :system,
            content: String.t(),
            timestamp: DateTime.t()
          }

    @type reasoning_step :: %{
            step: String.t(),
            status: :pending | :active | :complete
          }

    @type tool_call_entry :: %{
            call_id: String.t(),
            tool_name: String.t(),
            params: map(),
            result: JidoCode.Tools.Result.t() | nil,
            timestamp: DateTime.t()
          }

    @type agent_status :: :idle | :processing | :error | :unconfigured

    @type queued_message :: {term(), DateTime.t()}

    @type t :: %__MODULE__{
            text_input: map(),
            messages: [message()],
            agent_status: agent_status(),
            config: %{provider: String.t() | nil, model: String.t() | nil},
            reasoning_steps: [reasoning_step()],
            tool_calls: [tool_call_entry()],
            show_tool_details: boolean(),
            window: {non_neg_integer(), non_neg_integer()},
            message_queue: [queued_message()],
            scroll_offset: non_neg_integer(),
            show_reasoning: boolean(),
            agent_name: atom(),
            streaming_message: String.t() | nil,
            is_streaming: boolean(),
            session_topic: String.t() | nil,
            shell_dialog: map() | nil,
            shell_viewport: map() | nil,
            pick_list: map() | nil,
            conversation_view: map() | nil
          }

    @enforce_keys []
    defstruct text_input: nil,
              messages: [],
              agent_status: :unconfigured,
              config: %{provider: nil, model: nil},
              reasoning_steps: [],
              tool_calls: [],
              show_tool_details: false,
              window: {80, 24},
              message_queue: [],
              scroll_offset: 0,
              show_reasoning: false,
              agent_name: :llm_agent,
              streaming_message: nil,
              is_streaming: false,
              session_topic: nil,
              shell_dialog: nil,
              shell_viewport: nil,
              pick_list: nil,
              conversation_view: nil
  end

  # ============================================================================
  # Elm Callbacks
  # ============================================================================

  @doc """
  Initializes the TUI state.

  Loads settings from disk, subscribes to PubSub events and theme changes,
  and determines initial agent status based on configuration.
  """
  @impl true
  def init(_opts) do
    # Subscribe to TUI events using centralized topic
    Phoenix.PubSub.subscribe(JidoCode.PubSub, PubSubTopics.tui_events())

    # Subscribe to theme changes for live updates
    TermUI.Theme.subscribe()

    # Load configuration from settings
    config = load_config()

    # Determine initial status based on config
    status = determine_status(config)

    # Get actual terminal dimensions (Terminal is started by Runtime before init)
    window = get_terminal_dimensions()
    {width, _height} = window

    # Initialize TextInput widget for chat input
    # Note: We handle Enter explicitly in event_to_msg rather than using on_submit callback
    # because the callback would capture the wrong process pid
    text_input_props =
      TextInput.new(
        placeholder: "Type a message...",
        width: max(width - 4, 20),
        enter_submits: false
      )

    {:ok, text_input_state} = TextInput.init(text_input_props)
    # Set focused by default
    text_input_state = TextInput.set_focused(text_input_state, true)

    # Initialize ConversationView widget
    # Available height: total height - 2 (borders) - 1 (status bar) - 3 (separators) - 1 (input bar) - 1 (help bar)
    {width, height} = window
    conversation_height = max(height - 8, 1)
    conversation_width = max(width - 2, 1)

    conversation_view_props =
      ConversationView.new(
        messages: [],
        viewport_width: conversation_width,
        viewport_height: conversation_height,
        on_copy: &Clipboard.copy_to_clipboard/1
      )

    conversation_view_state = ConversationView.init(conversation_view_props)

    %Model{
      text_input: text_input_state,
      messages: [],
      agent_status: status,
      config: config,
      reasoning_steps: [],
      tool_calls: [],
      show_tool_details: false,
      window: window,
      message_queue: [],
      scroll_offset: 0,
      show_reasoning: false,
      agent_name: :llm_agent,
      streaming_message: nil,
      is_streaming: false,
      conversation_view: conversation_view_state
    }
  end

  # Get terminal dimensions, falling back to defaults if unavailable
  defp get_terminal_dimensions do
    case TermUI.size() do
      {:ok, {rows, cols}} -> {cols, rows}
      {:error, _} -> {80, 24}
    end
  end

  @doc """
  Converts terminal events to TUI messages.

  Handles keyboard events:
  - Ctrl+C → :quit
  - Ctrl+R → :toggle_reasoning
  - Ctrl+T → :toggle_tool_details
  - Up/Down arrows → scroll messages
  - Other key events → forwarded to TextInput widget
  """
  @impl true
  # Ctrl+C to quit
  def event_to_msg(%Event.Key{key: "c", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, :quit}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Ctrl+R to toggle reasoning panel
  def event_to_msg(%Event.Key{key: "r", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, :toggle_reasoning}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Ctrl+T to toggle tool details
  def event_to_msg(%Event.Key{key: "t", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, :toggle_tool_details}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Enter key - forward to modal if open, otherwise submit current input
  def event_to_msg(%Event.Key{key: :enter} = event, state) do
    cond do
      state.pick_list -> {:msg, {:pick_list_event, event}}
      state.shell_dialog -> {:msg, {:input_event, event}}
      true ->
        value = TextInput.get_value(state.text_input)
        {:msg, {:input_submitted, value}}
    end
  end

  # Escape key - forward to modal if open
  def event_to_msg(%Event.Key{key: :escape} = event, state) do
    cond do
      state.pick_list -> {:msg, {:pick_list_event, event}}
      state.shell_dialog -> {:msg, {:input_event, event}}
      true -> {:msg, {:input_event, event}}
    end
  end

  # Scroll navigation - if modal open, forward to modal; otherwise route to ConversationView
  def event_to_msg(%Event.Key{key: key} = event, state)
      when key in [:up, :down, :page_up, :page_down, :home, :end] do
    cond do
      state.pick_list -> {:msg, {:pick_list_event, event}}
      state.shell_dialog -> {:msg, {:input_event, event}}
      true -> {:msg, {:conversation_event, event}}
    end
  end

  # Backspace - forward to pick_list if open (for filter), otherwise to text input
  def event_to_msg(%Event.Key{key: :backspace} = event, state) do
    if state.pick_list do
      {:msg, {:pick_list_event, event}}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Resize events
  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  # Mouse events - route to ConversationView when not in modal
  def event_to_msg(%Event.Mouse{} = event, state) do
    cond do
      state.pick_list -> :ignore
      state.shell_dialog -> :ignore
      true -> {:msg, {:conversation_event, event}}
    end
  end

  # Forward all other key events - to pick_list if open, otherwise to TextInput widget
  def event_to_msg(%Event.Key{} = event, state) do
    if state.pick_list do
      {:msg, {:pick_list_event, event}}
    else
      {:msg, {:input_event, event}}
    end
  end

  def event_to_msg(_event, _state) do
    :ignore
  end

  @doc """
  Updates state based on messages.

  Handles:
  - `{:input_event, event}` - Forward keyboard events to TextInput widget
  - `{:input_submitted, value}` - Handle submitted text from TextInput
  - `:quit` - Return quit command
  - `{:resize, width, height}` - Update window dimensions
  - `{:scroll, :up/:down}` - Scroll message history
  - PubSub messages for agent events
  """
  @impl true
  # Handle shell dialog - intercept all input when dialog is open
  def update({:input_event, %Event.Key{} = event}, %{shell_dialog: dialog} = state)
      when not is_nil(dialog) do
    case event do
      # Close on Enter, Escape, or 'q'
      %Event.Key{key: key} when key in [:enter, :escape] ->
        {%{state | shell_dialog: nil, shell_viewport: nil}, []}

      %Event.Key{key: "q"} ->
        {%{state | shell_dialog: nil, shell_viewport: nil}, []}

      # Forward scroll events to viewport
      %Event.Key{key: key} when key in [:up, :down, :page_up, :page_down, :home, :end] ->
        case Viewport.handle_event(event, state.shell_viewport) do
          {:ok, new_viewport} ->
            {%{state | shell_viewport: new_viewport}, []}
          _ ->
            {state, []}
        end

      _ ->
        {state, []}
    end
  end

  # Handle pick_list events - intercept all input when pick list is open
  def update({:pick_list_event, %Event.Key{} = event}, %{pick_list: pick_list} = state)
      when not is_nil(pick_list) do
    case PickList.handle_event(event, pick_list) do
      {:ok, new_pick_list} ->
        {%{state | pick_list: new_pick_list}, []}

      {:ok, new_pick_list, actions} ->
        # Handle actions from PickList (select, cancel)
        handle_pick_list_actions(state, new_pick_list, actions)

      _ ->
        {state, []}
    end
  end

  # Forward keyboard events to TextInput widget
  def update({:input_event, event}, state) do
    {:ok, new_text_input} = TextInput.handle_event(event, state.text_input)
    {%{state | text_input: new_text_input}, []}
  end

  # Handle submitted text from TextInput (via on_submit callback)
  def update({:input_submitted, value}, state) do
    text = String.trim(value)

    cond do
      # Empty input - do nothing
      text == "" ->
        {state, []}

      # Command input - starts with /
      String.starts_with?(text, "/") ->
        # Clear input after command and ensure it stays focused
        new_text_input = state.text_input |> TextInput.clear() |> TextInput.set_focused(true)
        do_handle_command(text, %{state | text_input: new_text_input})

      # Chat input - requires configured provider/model
      true ->
        # Clear input after submit
        new_text_input = TextInput.clear(state.text_input)
        do_handle_chat_submit(text, %{state | text_input: new_text_input})
    end
  end

  def update(:quit, state) do
    {state, [:quit]}
  end

  def update({:resize, width, height}, state) do
    # Update TextInput width on resize
    {cur_width, _} = state.window
    new_width = max(width - 4, 20)

    new_text_input =
      if width != cur_width do
        %{state.text_input | width: new_width}
      else
        state.text_input
      end

    # Update ConversationView dimensions on resize
    conversation_height = max(height - 8, 1)
    conversation_width = max(width - 2, 1)

    new_conversation_view =
      if state.conversation_view do
        ConversationView.set_viewport_size(state.conversation_view, conversation_width, conversation_height)
      else
        state.conversation_view
      end

    {%{state | window: {width, height}, text_input: new_text_input, conversation_view: new_conversation_view}, []}
  end

  # ConversationView event handling - delegate keyboard and mouse events
  def update({:conversation_event, event}, state) when state.conversation_view != nil do
    case ConversationView.handle_event(event, state.conversation_view) do
      {:ok, new_conversation_view} ->
        {%{state | conversation_view: new_conversation_view}, []}

      _ ->
        {state, []}
    end
  end

  def update({:conversation_event, _event}, state) do
    # No conversation_view initialized, ignore
    {state, []}
  end

  # PubSub message handlers - delegated to MessageHandlers module
  # Note: Messages are stored in reverse order (newest first) for O(1) prepend
  def update({:agent_response, content}, state),
    do: MessageHandlers.handle_agent_response(content, state)

  # Streaming message handlers
  def update({:stream_chunk, chunk}, state),
    do: MessageHandlers.handle_stream_chunk(chunk, state)

  def update({:stream_end, full_content}, state),
    do: MessageHandlers.handle_stream_end(full_content, state)

  def update({:stream_error, reason}, state),
    do: MessageHandlers.handle_stream_error(reason, state)

  # Support both :status_update and :agent_status (per phase plan naming)
  def update({:status_update, status}, state),
    do: MessageHandlers.handle_status_update(status, state)

  def update({:agent_status, status}, state),
    do: MessageHandlers.handle_status_update(status, state)

  # Support both :config_change and :config_changed (per phase plan naming)
  def update({:config_change, config}, state),
    do: MessageHandlers.handle_config_change(config, state)

  def update({:config_changed, config}, state),
    do: MessageHandlers.handle_config_change(config, state)

  def update({:reasoning_step, step}, state),
    do: MessageHandlers.handle_reasoning_step(step, state)

  def update(:clear_reasoning_steps, state),
    do: MessageHandlers.handle_clear_reasoning_steps(state)

  def update(:toggle_reasoning, state),
    do: MessageHandlers.handle_toggle_reasoning(state)

  def update(:toggle_tool_details, state),
    do: MessageHandlers.handle_toggle_tool_details(state)

  # Tool call handling - add pending tool call to list
  def update({:tool_call, tool_name, params, call_id}, state),
    do: MessageHandlers.handle_tool_call(tool_name, params, call_id, state)

  # Tool result handling - match result to pending call and update
  def update({:tool_result, %Result{} = result}, state),
    do: MessageHandlers.handle_tool_result(result, state)

  # Theme change handling - triggers re-render with new theme colors
  def update({:theme_changed, _theme}, state) do
    # The theme is stored in TermUI.Theme's ETS table, accessed by ViewHelpers
    # We just need to trigger a re-render by returning the same state
    {state, []}
  end

  # Catch-all for unhandled messages
  def update(msg, state) do
    Logger.debug("TUI unhandled message: #{inspect(msg)}")
    {state, []}
  end

  # ============================================================================
  # Message Builder Helpers
  # ============================================================================

  @doc """
  Creates a user message with the current timestamp.
  """
  @spec user_message(String.t()) :: Model.message()
  def user_message(content) do
    %{role: :user, content: content, timestamp: DateTime.utc_now()}
  end

  @doc """
  Creates an assistant message with the current timestamp.
  """
  @spec assistant_message(String.t()) :: Model.message()
  def assistant_message(content) do
    %{role: :assistant, content: content, timestamp: DateTime.utc_now()}
  end

  @doc """
  Creates a system message with the current timestamp.
  """
  @spec system_message(String.t()) :: Model.message()
  def system_message(content) do
    %{role: :system, content: content, timestamp: DateTime.utc_now()}
  end

  # ============================================================================
  # Update Helpers
  # ============================================================================

  # Generate a unique message ID for ConversationView
  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Handle actions returned from PickList widget
  defp handle_pick_list_actions(state, _new_pick_list, actions) do
    pick_list_type = state.pick_list.props[:pick_list_type]
    provider = state.pick_list.props[:provider]

    Enum.reduce(actions, {%{state | pick_list: nil}, []}, fn action, {acc_state, acc_cmds} ->
      case action do
        {:send, _pid, {:select, selected}} ->
          handle_pick_list_selection(acc_state, acc_cmds, pick_list_type, provider, selected)

        {:send, _pid, :cancel} ->
          # Selection was cancelled
          {acc_state, acc_cmds}

        _ ->
          {acc_state, acc_cmds}
      end
    end)
  end

  defp handle_pick_list_selection(state, cmds, :provider, _provider, selected_provider) do
    # Provider was selected - set it via Commands
    result = Commands.execute("/provider #{selected_provider}", state.config)
    apply_command_result(state, cmds, result)
  end

  defp handle_pick_list_selection(state, cmds, :model, provider, model) do
    # Model was selected - set it via Commands
    result = Commands.execute("/model #{provider}:#{model}", state.config)
    apply_command_result(state, cmds, result)
  end

  defp handle_pick_list_selection(state, cmds, _, _, _) do
    {state, cmds}
  end

  defp apply_command_result(state, cmds, result) do
    case result do
      {:ok, message, new_config} ->
        system_msg = system_message(message)
        updated_config = %{
          provider: new_config[:provider] || state.config.provider,
          model: new_config[:model] || state.config.model
        }
        new_status = determine_status(updated_config)
        new_state = %{
          state
          | messages: [system_msg | state.messages],
            config: updated_config,
            agent_status: new_status
        }
        {new_state, cmds}

      {:error, error_message} ->
        error_msg = system_message(error_message)
        new_state = %{state | messages: [error_msg | state.messages]}
        {new_state, cmds}

      _ ->
        {state, cmds}
    end
  end

  # Handle command input (starts with /)
  defp do_handle_command(text, state) do
    case Commands.execute(text, state.config) do
      {:ok, message, new_config} ->
        system_msg = system_message(message)

        # Merge new config with existing config
        updated_config =
          if map_size(new_config) > 0 do
            %{
              provider: new_config[:provider] || state.config.provider,
              model: new_config[:model] || state.config.model
            }
          else
            state.config
          end

        # Determine new status based on config
        new_status = determine_status(updated_config)

        # Sync system message to ConversationView
        new_conversation_view =
          if state.conversation_view do
            ConversationView.add_message(state.conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: message,
              timestamp: DateTime.utc_now()
            })
          else
            state.conversation_view
          end

        new_state = %{
          state
          | messages: [system_msg | state.messages],
            config: updated_config,
            agent_status: new_status,
            conversation_view: new_conversation_view
        }

        {new_state, []}

      {:pick_list, type_or_provider, items, title} ->
        # Show interactive picker using PickList widget
        # type_or_provider is :provider for provider selection, or a provider name string for model selection
        {width, height} = state.window

        {pick_list_type, provider} =
          if type_or_provider == :provider do
            {:provider, nil}
          else
            {:model, type_or_provider}
          end

        pick_list_props = %{
          items: items,
          title: title,
          width: min(60, width - 4),
          height: min(20, height - 4),
          pick_list_type: pick_list_type,
          provider: provider
        }
        {:ok, pick_list_state} = PickList.init(pick_list_props)

        new_state = %{state | pick_list: pick_list_state}
        {new_state, []}

      {:shell_output, command, output} ->
        # Show shell output in modal dialog using widgets
        {width, height} = state.window
        lines = String.split(output, "\n")
        content_height = length(lines)

        # Calculate modal dimensions - 70% of window, capped at reasonable sizes
        modal_width = min(div(width * 70, 100), 100) |> max(40)
        modal_height = min(div(height * 70, 100), 30) |> max(10)

        # Viewport dimensions account for border (2), title (1), blank (1), footer (1), blank (1)
        viewport_width = modal_width - 4
        viewport_height = modal_height - 6

        # Create viewport for scrollable content
        viewport_content = stack(:vertical, Enum.map(lines, &text(&1, nil)))
        viewport_props = Viewport.new(
          content: viewport_content,
          content_height: content_height,
          width: viewport_width,
          height: viewport_height,
          scroll_bars: :vertical
        )
        {:ok, viewport_state} = Viewport.init(viewport_props)

        # Create dialog state (we use a simple map, not the full Dialog widget)
        dialog_state = %{title: "Shell: #{command}"}

        new_state = %{state | shell_dialog: dialog_state, shell_viewport: viewport_state}
        {new_state, []}

      {:error, error_message} ->
        error_msg = system_message(error_message)

        # Sync error message to ConversationView
        new_conversation_view =
          if state.conversation_view do
            ConversationView.add_message(state.conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: error_message,
              timestamp: DateTime.utc_now()
            })
          else
            state.conversation_view
          end

        new_state = %{state | messages: [error_msg | state.messages], conversation_view: new_conversation_view}
        {new_state, []}
    end
  end

  # Handle chat message submission
  defp do_handle_chat_submit(text, state) do
    # Check if provider and model are configured
    case {state.config.provider, state.config.model} do
      {nil, _} ->
        do_show_config_error(state)

      {_, nil} ->
        do_show_config_error(state)

      {_provider, _model} ->
        do_dispatch_to_agent(text, state)
    end
  end

  defp do_show_config_error(state) do
    error_content = "Please configure a model first. Use /model <provider>:<model> or Ctrl+M to select."
    error_msg = system_message(error_content)

    # Sync error message to ConversationView
    new_conversation_view =
      if state.conversation_view do
        ConversationView.add_message(state.conversation_view, %{
          id: generate_message_id(),
          role: :system,
          content: error_content,
          timestamp: DateTime.utc_now()
        })
      else
        state.conversation_view
      end

    new_state = %{state | messages: [error_msg | state.messages], conversation_view: new_conversation_view}
    {new_state, []}
  end

  defp do_dispatch_to_agent(text, state) do
    # Add user message to conversation
    user_msg = user_message(text)

    # Classify query for CoT (for future use)
    _use_cot = QueryClassifier.should_use_cot?(text)

    # Sync user message to ConversationView
    new_conversation_view =
      if state.conversation_view do
        ConversationView.add_message(state.conversation_view, %{
          id: generate_message_id(),
          role: :user,
          content: text,
          timestamp: DateTime.utc_now()
        })
      else
        state.conversation_view
      end

    # Look up and dispatch to agent with streaming
    case AgentSupervisor.lookup_agent(state.agent_name) do
      {:ok, agent_pid} ->
        # Subscribe to session-specific topic if not already subscribed
        new_state = ensure_session_subscription(state, agent_pid)

        # Dispatch async with streaming - agent will broadcast chunks via PubSub
        LLMAgent.chat_stream(agent_pid, text)

        updated_state = %{
          new_state
          | messages: [user_msg | new_state.messages],
            agent_status: :processing,
            scroll_offset: 0,
            streaming_message: "",
            is_streaming: true,
            conversation_view: new_conversation_view
        }

        {updated_state, []}

      {:error, :not_found} ->
        error_msg =
          system_message(
            "LLM agent not running. Start with: JidoCode.AgentSupervisor.start_agent(%{name: :llm_agent, module: JidoCode.Agents.LLMAgent, args: []})"
          )

        # Also add error message to ConversationView
        cv_with_error =
          if new_conversation_view do
            ConversationView.add_message(new_conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: error_msg.content,
              timestamp: DateTime.utc_now()
            })
          else
            new_conversation_view
          end

        new_state = %{
          state
          | messages: [error_msg, user_msg | state.messages],
            agent_status: :error,
            conversation_view: cv_with_error
        }

        {new_state, []}
    end
  end

  # Subscribe to the agent's session-specific topic if not already subscribed
  defp ensure_session_subscription(state, agent_pid) do
    case LLMAgent.get_session_info(agent_pid) do
      {:ok, _session_id, topic} ->
        if state.session_topic != topic do
          # Unsubscribe from old topic if we had one
          if state.session_topic do
            Phoenix.PubSub.unsubscribe(JidoCode.PubSub, state.session_topic)
          end

          # Subscribe to new session topic
          Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
          %{state | session_topic: topic}
        else
          state
        end

      _ ->
        state
    end
  end

  @doc """
  Renders the current state to a render tree.

  Implements a three-pane layout:
  - Status bar (top): Provider, model, agent status, keyboard hints
  - Conversation area (middle): Message history with role indicators
  - Input bar (bottom): Prompt indicator and current input buffer
  """
  @impl true
  def view(state) do
    # Always show main view - status bar displays "No provider" / "No model" when unconfigured
    main_view = render_main_view(state)

    # Overlay modals if present (pick_list takes priority over shell_dialog)
    cond do
      state.pick_list ->
        overlay_pick_list(state, main_view)

      state.shell_dialog ->
        overlay_shell_dialog(state, main_view)

      true ->
        main_view
    end
  end

  defp render_main_view(state) do
    {width, _height} = state.window

    content =
      if state.show_reasoning do
        # Show reasoning panel
        if width >= 100 do
          # Wide terminal: side-by-side layout
          render_main_content_with_sidebar(state)
        else
          # Narrow terminal: stacked layout with compact reasoning
          render_main_content_with_drawer(state)
        end
      else
        # Standard layout without reasoning panel
        # Layout: status bar | separator | main UI | separator | text input | separator | key controls
        stack(:vertical, [
          ViewHelpers.render_status_bar(state),
          ViewHelpers.render_separator(state),
          render_conversation_area(state),
          ViewHelpers.render_separator(state),
          ViewHelpers.render_input_bar(state),
          ViewHelpers.render_separator(state),
          ViewHelpers.render_help_bar(state)
        ])
      end

    ViewHelpers.render_with_border(state, content)
  end

  defp render_main_content_with_sidebar(state) do
    # Side-by-side layout for wide terminals
    stack(:vertical, [
      ViewHelpers.render_status_bar(state),
      ViewHelpers.render_separator(state),
      stack(:horizontal, [
        render_conversation_area(state),
        ViewHelpers.render_reasoning(state)
      ]),
      ViewHelpers.render_separator(state),
      ViewHelpers.render_input_bar(state),
      ViewHelpers.render_separator(state),
      ViewHelpers.render_help_bar(state)
    ])
  end

  defp render_main_content_with_drawer(state) do
    # Stacked layout with reasoning drawer for narrow terminals
    stack(:vertical, [
      ViewHelpers.render_status_bar(state),
      ViewHelpers.render_separator(state),
      render_conversation_area(state),
      ViewHelpers.render_reasoning_compact(state),
      ViewHelpers.render_separator(state),
      ViewHelpers.render_input_bar(state),
      ViewHelpers.render_separator(state),
      ViewHelpers.render_help_bar(state)
    ])
  end

  # Render conversation using ConversationView widget if available, otherwise fallback to ViewHelpers
  defp render_conversation_area(state) do
    if state.conversation_view do
      {width, height} = state.window
      # Available height: total height - 2 (borders) - 1 (status bar) - 3 (separators) - 1 (input bar) - 1 (help bar)
      available_height = max(height - 8, 1)
      content_width = max(width - 2, 1)

      area = %{x: 0, y: 0, width: content_width, height: available_height}
      ConversationView.render(state.conversation_view, area)
    else
      ViewHelpers.render_conversation(state)
    end
  end

  defp overlay_shell_dialog(state, main_view) do
    {width, height} = state.window

    # Calculate modal dimensions - 70% of window, capped at reasonable sizes
    modal_width = min(div(width * 70, 100), 100) |> max(40)
    modal_height = min(div(height * 70, 100), 30) |> max(10)

    # Viewport dimensions account for border (2), title (1), blank (1), footer (1), blank (1)
    viewport_width = modal_width - 4
    viewport_height = modal_height - 6

    # Render the viewport content
    viewport_view = Viewport.render(state.shell_viewport, %{width: viewport_width, height: viewport_height})

    # Build dialog content with title, viewport, and footer
    title = text(state.shell_dialog.title, Style.new(fg: :cyan, attrs: [:bold]))
    footer = text("[Enter/Esc/q] Close  [↑↓/PgUp/PgDn] Scroll", Style.new(fg: :bright_black))

    dialog_content = stack(:vertical, [
      title,
      text("", nil),
      viewport_view,
      text("", nil),
      footer
    ])

    # Build the dialog box with border
    dialog_box = ViewHelpers.render_dialog_box(dialog_content, modal_width, modal_height)

    # Calculate position to center the dialog
    dialog_x = div(width - modal_width, 2)
    dialog_y = div(height - modal_height, 2)

    # Return list of nodes - main view renders first, then overlay renders on top at absolute position
    [
      main_view,
      %{
        type: :overlay,
        content: dialog_box,
        x: dialog_x,
        y: dialog_y,
        z: 100,
        width: modal_width,
        height: modal_height,
        bg: Style.new(bg: :black)
      }
    ]
  end

  defp overlay_pick_list(state, main_view) do
    {width, height} = state.window

    # PickList.render returns a RenderNode with cells at absolute positions
    # We need to pass an area that represents the full window
    area = %{width: width, height: height}
    pick_list_view = PickList.render(state.pick_list, area)

    # Wrap in overlay at position 0,0 so the absolute cell positions work correctly
    # The PickList cells already contain their absolute screen coordinates
    [
      main_view,
      %{
        type: :overlay,
        content: pick_list_view,
        x: 0,
        y: 0,
        z: 100
      }
    ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs the TUI application.

  This blocks the calling process until the TUI exits (e.g., user presses Ctrl+C).
  """
  @spec run() :: :ok
  def run do
    TermUI.Runtime.run(root: __MODULE__)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec load_config() :: %{provider: String.t() | nil, model: String.t() | nil}
  defp load_config do
    {:ok, settings} = Settings.load()

    provider = Map.get(settings, "provider")
    model = Map.get(settings, "model")

    # Only use provider/model if the API key is available
    if provider && has_api_key?(provider) do
      %{provider: provider, model: model}
    else
      %{provider: nil, model: nil}
    end
  end

  # Check if API key is available for the provider
  defp has_api_key?(provider) do
    key_name = provider_to_key_name(provider)

    case Keyring.get(key_name) do
      nil -> false
      "" -> false
      _key -> true
    end
  end

  # Known provider to API key name mapping
  @provider_keys %{
    "openai" => :openai_api_key,
    "anthropic" => :anthropic_api_key,
    "openrouter" => :openrouter_api_key,
    "azure" => :azure_api_key,
    "google" => :google_api_key,
    "gemini" => :google_api_key,
    "cohere" => :cohere_api_key,
    "mistral" => :mistral_api_key,
    "groq" => :groq_api_key,
    "together" => :together_api_key,
    "fireworks" => :fireworks_api_key,
    "deepseek" => :deepseek_api_key,
    "perplexity" => :perplexity_api_key,
    "xai" => :xai_api_key,
    "ollama" => :ollama_api_key,
    "cerebras" => :cerebras_api_key,
    "sambanova" => :sambanova_api_key
  }

  defp provider_to_key_name(provider) do
    Map.get(@provider_keys, provider, :unknown_provider_api_key)
  end

  @doc false
  @spec determine_status(%{provider: String.t() | nil, model: String.t() | nil}) ::
          Model.agent_status()
  def determine_status(config) do
    cond do
      is_nil(config.provider) -> :unconfigured
      is_nil(config.model) -> :unconfigured
      true -> :idle
    end
  end

  @doc """
  Queues a message with timestamp, limiting to @max_queue_size entries.

  Used for debugging and preventing unbounded message accumulation during rapid updates.
  """
  @spec queue_message([Model.queued_message()], term()) :: [Model.queued_message()]
  def queue_message(queue, msg) do
    [{msg, DateTime.utc_now()} | queue]
    |> Enum.take(@max_queue_size)
  end

  @doc """
  Calculates the maximum scroll offset based on message count and available height.

  Returns 0 if all messages fit on screen, otherwise returns the number of lines
  that can be scrolled up (towards older messages).
  """
  @spec max_scroll_offset(Model.t()) :: non_neg_integer()
  def max_scroll_offset(state) do
    {width, height} = state.window
    available_height = max(height - 2, 1)
    # Calculate total lines with wrapping
    total_lines = calculate_total_lines(state.messages, width)
    max(total_lines - available_height, 0)
  end

  # Calculate total lines accounting for text wrapping
  defp calculate_total_lines(messages, width) do
    Enum.reduce(messages, 0, fn msg, acc ->
      # Account for prefix length in wrapping
      prefix_len = prefix_length(msg.role)
      content_width = max(width - prefix_len, 20)
      lines = wrap_text(msg.content, content_width)
      acc + length(lines)
    end)
  end

  defp prefix_length(:user), do: String.length("[00:00] You: ")
  defp prefix_length(:assistant), do: String.length("[00:00] Assistant: ")
  defp prefix_length(:system), do: String.length("[00:00] System: ")

  @doc """
  Wraps text to fit within the specified width.

  Words are kept together when possible. Words longer than max_width are split.
  Returns a list of lines.
  """
  @spec wrap_text(String.t(), pos_integer()) :: [String.t()]
  def wrap_text(text, max_width) when max_width > 0 do
    text
    |> String.split(" ")
    |> Enum.reduce({[], ""}, fn word, acc -> wrap_word(word, acc, max_width) end)
    |> finalize_wrap()
  end

  def wrap_text(_text, _max_width), do: [""]

  defp wrap_word(word, {lines, current_line}, max_width) do
    new_line = if current_line == "", do: word, else: current_line <> " " <> word

    cond do
      String.length(new_line) <= max_width ->
        {lines, new_line}

      current_line == "" ->
        # Word is longer than max_width, split it
        {lines ++ [String.slice(word, 0, max_width)], String.slice(word, max_width..-1//1)}

      true ->
        {lines ++ [current_line], word}
    end
  end

  defp finalize_wrap({lines, last}) do
    result = if last == "", do: lines, else: lines ++ [last]

    case result do
      [] -> [""]
      final_lines -> final_lines
    end
  end

  @doc """
  Formats a timestamp as HH:MM.
  """
  @spec format_timestamp(DateTime.t()) :: String.t()
  def format_timestamp(datetime) do
    hour = datetime.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = datetime.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "[#{hour}:#{minute}]"
  end

  # ============================================================================
  # View Helpers - Public API (delegated to ViewHelpers)
  # ============================================================================

  @doc """
  Returns the style for a given agent status.
  """
  def status_style(:idle), do: Style.new(fg: :green, bg: :blue)
  def status_style(:processing), do: Style.new(fg: :yellow, bg: :blue)
  def status_style(:error), do: Style.new(fg: :red, bg: :blue)
  def status_style(:unconfigured), do: Style.new(fg: :red, bg: :blue, attrs: [:dim])

  @doc """
  Returns the style for the config display based on configuration state.
  """
  def config_style(%{provider: nil}), do: Style.new(fg: :red, bg: :blue)
  def config_style(%{model: nil}), do: Style.new(fg: :yellow, bg: :blue)
  def config_style(_), do: Style.new(fg: :white, bg: :blue)

  @doc """
  Formats a tool call entry for display.

  Returns a list of render nodes representing the tool call and its result.

  ## Parameters

  - `entry` - Tool call entry with call_id, tool_name, params, result, timestamp
  - `show_details` - Whether to show full details (true) or condensed (false)
  """
  defdelegate format_tool_call_entry(entry, show_details), to: ViewHelpers

  @doc """
  Renders the reasoning panel showing Chain-of-Thought steps.

  Steps are displayed with status indicators:
  - ○ pending (dim)
  - ● active (yellow)
  - ✓ complete (green)
  """
  defdelegate render_reasoning(state), to: ViewHelpers

  @doc """
  Renders reasoning steps as a compact single-line display for narrow terminals.
  """
  defdelegate render_reasoning_compact(state), to: ViewHelpers
end
