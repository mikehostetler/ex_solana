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
  alias JidoCode.Commands
  alias JidoCode.Config.ProviderKeys
  alias JidoCode.PubSubTopics
  alias JidoCode.Session
  alias JidoCode.Settings
  alias JidoCode.Tools.Result
  alias JidoCode.TUI.Clipboard
  alias JidoCode.TUI.MessageHandlers
  alias JidoCode.TUI.ViewHelpers
  alias JidoCode.TUI.Widgets.ConversationView
  alias JidoCode.TUI.Widgets.MainLayout
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
          | {:tool_call, String.t(), map(), String.t(), String.t() | nil}
          | {:tool_result, Result.t(), String.t() | nil}
          | :toggle_tool_details
          | {:stream_chunk, String.t(), String.t()}
          | {:stream_end, String.t(), String.t()}
          | {:stream_error, term()}

  # Maximum number of messages to keep in the debug queue
  @max_queue_size 100

  # ============================================================================
  # Model
  # ============================================================================

  defmodule Model do
    @moduledoc """
    The TUI application state.

    ## Multi-Session Support

    The Model supports multiple concurrent sessions via the session tracking fields:

    - `sessions` - Map of session_id to Session.t() structs
    - `session_order` - List of session_ids in tab display order
    - `active_session_id` - Currently focused session

    Per-session data (messages, reasoning_steps, tool_calls, streaming state) is
    stored in Session.State and accessed via the active_session_id. The legacy
    fields are retained for backwards compatibility during transition.

    ## Focus States

    The `focus` field controls keyboard navigation:

    - `:input` - Text input has focus (default)
    - `:conversation` - Conversation view has focus (for scrolling)
    - `:tabs` - Tab bar has focus (for tab selection)
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

    @typedoc """
    Thinking mode sub-types representing JidoAI runners.

    Maps to actual JidoAI runner implementations:
    - `:chat` - Direct LLM call (no special reasoning)
    - `:chain_of_thought` - Step-by-step reasoning (8-15% accuracy improvement)
    - `:react` - Reasoning + Acting, interleaved with tool execution (+27.4% on HotpotQA)
    - `:tree_of_thoughts` - Multi-branch reasoning exploration (+70% on complex tasks)
    - `:self_consistency` - Multiple reasoning paths with voting (+17.9% on GSM8K)
    - `:program_of_thought` - Generate programs to solve problems
    - `:gepa` - Genetic-Pareto evolutionary prompt optimization/rewording
    """
    @type thinking_mode ::
            :chat
            | :chain_of_thought
            | :react
            | :tree_of_thoughts
            | :self_consistency
            | :program_of_thought
            | :gepa

    @typedoc """
    Detailed agent activity status.

    Provides granular tracking of what the agent is currently doing:
    - `:idle` - Agent is ready for new requests
    - `:unconfigured` - Agent not configured (no provider/model)
    - `{:thinking, mode}` - LLM is processing with specified thinking mode (JidoAI runner)
    - `{:tool_executing, tool_name}` - Executing a specific tool
    - `{:error, reason}` - Error state with reason

    ## Examples

        :idle
        {:thinking, :chat}
        {:thinking, :chain_of_thought}
        {:thinking, :react}
        {:thinking, :tree_of_thoughts}
        {:tool_executing, "read_file"}
        {:error, :timeout}
    """
    @type agent_activity ::
            :idle
            | :unconfigured
            | {:thinking, thinking_mode()}
            | {:tool_executing, tool_name :: String.t()}
            | {:error, reason :: term()}

    @typedoc """
    Indicates the session is blocked waiting for user input.

    - `nil` - Not waiting for input, session can proceed
    - `:clarification` - LLM asked a question, waiting for user response
    - `:permission` - Tool execution requires user approval
    - `:confirmation` - Action requires user confirmation before proceeding

    This is tracked separately from `agent_activity` to allow both states:
    e.g., agent is idle but awaiting clarification input.
    """
    @type awaiting_input :: nil | :clarification | :permission | :confirmation

    @type queued_message :: {term(), DateTime.t()}

    @typedoc "Per-session UI state stored in the TUI process"
    @type session_ui_state :: %{
            text_input: map() | nil,
            conversation_view: map() | nil,
            accordion: JidoCode.TUI.Widgets.Accordion.t() | nil,
            scroll_offset: non_neg_integer(),
            streaming_message: String.t() | nil,
            is_streaming: boolean(),
            reasoning_steps: [reasoning_step()],
            tool_calls: [tool_call_entry()],
            messages: [message()],
            agent_activity: agent_activity(),
            awaiting_input: awaiting_input()
          }

    @typedoc "Focus states for keyboard navigation"
    @type focus :: :input | :conversation | :tabs | :sidebar

    @typedoc "Map of session_id to Session struct"
    @type session_map :: %{optional(String.t()) => JidoCode.Session.t()}

    @type t :: %__MODULE__{
            # Session management (multi-session support)
            sessions: session_map(),
            session_order: [String.t()],
            active_session_id: String.t() | nil,

            # UI state
            text_input: map(),
            tabs_widget: map() | nil,
            focus: focus(),
            window: {non_neg_integer(), non_neg_integer()},
            show_reasoning: boolean(),
            show_tool_details: boolean(),
            agent_status: agent_status(),
            config: %{provider: String.t() | nil, model: String.t() | nil},

            # Sidebar state (Phase 4.5)
            sidebar_visible: boolean(),
            sidebar_width: pos_integer(),
            sidebar_expanded: MapSet.t(String.t()),
            sidebar_selected_index: non_neg_integer(),

            # Sidebar activity tracking (Phase 4.7.3)
            streaming_sessions: MapSet.t(String.t()),
            unread_counts: %{String.t() => non_neg_integer()},
            active_tools: %{String.t() => non_neg_integer()},
            last_activity: %{String.t() => DateTime.t()},

            # Modals (shared across sessions)
            shell_dialog: map() | nil,
            shell_viewport: map() | nil,
            pick_list: map() | nil,

            # Main layout state (SplitPane with sidebar + tabs)
            main_layout: JidoCode.TUI.Widgets.MainLayout.t() | nil,

            # Legacy per-session fields (for backwards compatibility)
            # These will be migrated to Session.State in Phase 4.2
            messages: [message()],
            reasoning_steps: [reasoning_step()],
            tool_calls: [tool_call_entry()],
            message_queue: [queued_message()],
            scroll_offset: non_neg_integer(),
            agent_name: atom(),
            streaming_message: String.t() | nil,
            is_streaming: boolean(),
            session_topic: String.t() | nil,
            conversation_view: map() | nil
          }

    # Maximum number of tabs supported (Ctrl+1 through Ctrl+9, plus Ctrl+0 for 10th)
    @max_tabs 10

    defstruct [
      # Session management (multi-session support)
      sessions: %{},
      session_order: [],
      active_session_id: nil,
      # UI state
      text_input: nil,
      tabs_widget: nil,
      # Focus state for keyboard navigation (used in Phase 4.5)
      focus: :input,
      window: {80, 24},
      show_reasoning: false,
      show_tool_details: false,
      agent_status: :unconfigured,
      config: %{provider: nil, model: nil},
      # Sidebar state (Phase 4.5)
      sidebar_visible: true,
      sidebar_width: 20,
      sidebar_expanded: MapSet.new(),
      sidebar_selected_index: 0,
      # Sidebar activity tracking (Phase 4.7.3)
      streaming_sessions: MapSet.new(),
      unread_counts: %{},
      active_tools: %{},
      last_activity: %{},
      # Modals (shared across sessions)
      shell_dialog: nil,
      shell_viewport: nil,
      pick_list: nil,
      # Main layout state (SplitPane with sidebar + tabs)
      main_layout: nil,
      # Legacy per-session fields (for backwards compatibility)
      # These will be migrated to Session.State in Phase 4.2
      messages: [],
      reasoning_steps: [],
      tool_calls: [],
      message_queue: [],
      scroll_offset: 0,
      agent_name: :llm_agent,
      streaming_message: nil,
      is_streaming: false,
      session_topic: nil,
      conversation_view: nil
    ]

    # =========================================================================
    # Session Access Helpers
    # =========================================================================

    @doc """
    Returns the currently active Session struct from the model.

    Returns `nil` if no session is active (active_session_id is nil) or if
    the active session is not found in the sessions map.

    ## Examples

        iex> model = %Model{sessions: %{"s1" => session}, active_session_id: "s1"}
        iex> Model.get_active_session(model)
        %Session{...}

        iex> model = %Model{active_session_id: nil}
        iex> Model.get_active_session(model)
        nil
    """
    @spec get_active_session(t()) :: JidoCode.Session.t() | nil
    def get_active_session(%__MODULE__{active_session_id: nil}), do: nil

    def get_active_session(%__MODULE__{active_session_id: id, sessions: sessions}) do
      Map.get(sessions, id)
    end

    @doc """
    Fetches the active session's state from the Session.State GenServer.

    This function looks up the active session and retrieves its conversation
    state (messages, streaming state, etc.) from the Session.State process.

    Returns `nil` if no session is active.

    ## Examples

        iex> model = %Model{active_session_id: "session-123"}
        iex> Model.get_active_session_state(model)
        %{messages: [...], streaming_message: nil, ...}
    """
    @spec get_active_session_state(t()) :: map() | nil
    def get_active_session_state(%__MODULE__{active_session_id: nil}), do: nil

    def get_active_session_state(%__MODULE__{active_session_id: id}) do
      case JidoCode.Session.State.get_state(id) do
        {:ok, state} -> state
        {:error, :not_found} -> nil
      end
    end

    @doc """
    Returns the agent status for a session.

    Queries Session.AgentAPI to determine if the session's agent is:
    - `:idle` - Agent is ready for new requests
    - `:processing` - Agent is actively processing a request
    - `:error` - Agent is not responding or crashed
    - `:unconfigured` - Session has no agent

    ## Parameters
    - `session_id` - The session identifier

    ## Returns
    - `agent_status()` atom

    ## Examples

        iex> Model.get_session_status("session-123")
        :idle

        iex> Model.get_session_status("nonexistent")
        :unconfigured
    """
    @spec get_session_status(String.t()) :: agent_status()
    def get_session_status(session_id) do
      case JidoCode.Session.AgentAPI.get_status(session_id) do
        {:ok, %{ready: true}} -> :idle
        {:ok, %{ready: false}} -> :processing
        {:error, :agent_not_found} -> :unconfigured
        {:error, _} -> :error
      end
    end

    @doc """
    Returns the session at the given tab index (1-based).

    Tab indices 1-9 correspond to Ctrl+1 through Ctrl+9.
    Tab index 10 corresponds to Ctrl+0 (the 10th tab).

    Returns `nil` if the index is out of range or if no sessions exist.

    ## Examples

        iex> model = %Model{session_order: ["s1", "s2", "s3"], sessions: %{...}}
        iex> Model.get_session_by_index(model, 1)
        %Session{id: "s1", ...}

        iex> Model.get_session_by_index(model, 10)
        nil  # Only 3 sessions exist
    """
    @spec get_session_by_index(t(), pos_integer()) :: JidoCode.Session.t() | nil
    def get_session_by_index(%__MODULE__{session_order: []}, _index), do: nil

    def get_session_by_index(%__MODULE__{session_order: order, sessions: sessions}, index)
        when is_integer(index) and index >= 1 and index <= @max_tabs do
      # Convert 1-based tab index to 0-based list index
      list_index = index - 1

      case Enum.at(order, list_index) do
        nil -> nil
        session_id -> Map.get(sessions, session_id)
      end
    end

    def get_session_by_index(_model, _index), do: nil

    # =========================================================================
    # Session Modification Helpers
    # =========================================================================

    @doc """
    Adds a session to the model and makes it the active session.

    This function:
    1. Adds the session to the sessions map
    2. Appends the session ID to session_order
    3. Sets the session as the active session

    Returns the updated model.

    ## Examples

        iex> model = %Model{}
        iex> session = %Session{id: "s1", name: "project"}
        iex> model = Model.add_session(model, session)
        iex> model.active_session_id
        "s1"
    """
    @spec add_session(t(), JidoCode.Session.t()) :: t()
    def add_session(%__MODULE__{} = model, %JidoCode.Session{} = session) do
      # Subscribe to the new session's events
      JidoCode.TUI.subscribe_to_session(session.id)

      # Add UI state to the session data
      session_with_ui = Map.put(session, :ui_state, default_ui_state(model.window))

      %{
        model
        | sessions: Map.put(model.sessions, session.id, session_with_ui),
          session_order: model.session_order ++ [session.id],
          active_session_id: session.id
      }
    end

    @doc """
    Adds a session to the tab list without forcing it to be active.

    This function differs from `add_session/2` in that it only sets the new
    session as active if no other session is currently active. This is useful
    when loading multiple sessions at startup or when creating background sessions.

    ## Behavior

    1. Adds the session to the sessions map
    2. Appends the session ID to session_order
    3. Sets as active ONLY if `active_session_id` is currently `nil`

    ## Examples

        # First session becomes active
        iex> model = %Model{}
        iex> session1 = %Session{id: "s1", name: "project1"}
        iex> model = Model.add_session_to_tabs(model, session1)
        iex> model.active_session_id
        "s1"

        # Second session does NOT become active
        iex> session2 = %Session{id: "s2", name: "project2"}
        iex> model = Model.add_session_to_tabs(model, session2)
        iex> model.active_session_id
        "s1"

    ## See Also

    - `add_session/2` - Always sets new session as active
    - `switch_session/2` - Explicitly switch to a session
    """
    @spec add_session_to_tabs(t(), JidoCode.Session.t() | map()) :: t()
    def add_session_to_tabs(%__MODULE__{} = model, session) when is_map(session) do
      session_id = Map.get(session, :id) || Map.get(session, "id")

      # Subscribe to the new session's events
      JidoCode.TUI.subscribe_to_session(session_id)

      # Add UI state to the session data
      session_with_ui = Map.put(session, :ui_state, default_ui_state(model.window))

      %{
        model
        | sessions: Map.put(model.sessions, session_id, session_with_ui),
          session_order: model.session_order ++ [session_id],
          active_session_id: model.active_session_id || session_id
      }
    end

    @doc """
    Removes a session from the tab list.

    This is an alias for `remove_session/2` that follows the naming convention
    from Phase 4.1.3 of the work-session plan.

    See `remove_session/2` for full documentation.
    """
    @spec remove_session_from_tabs(t(), String.t()) :: t()
    def remove_session_from_tabs(%__MODULE__{} = model, session_id) do
      remove_session(model, session_id)
    end

    @doc """
    Switches to a different session by ID.

    Only switches if the session exists in the sessions map.
    Returns the model unchanged if session ID is not found.

    ## Examples

        iex> model = %Model{sessions: %{"s1" => session}, active_session_id: nil}
        iex> model = Model.switch_session(model, "s1")
        iex> model.active_session_id
        "s1"

        iex> model = Model.switch_session(model, "unknown")
        iex> model.active_session_id  # unchanged
        "s1"
    """
    @spec switch_session(t(), String.t()) :: t()
    def switch_session(%__MODULE__{sessions: sessions} = model, session_id) do
      if Map.has_key?(sessions, session_id) do
        %{model | active_session_id: session_id}
      else
        model
      end
    end

    @doc """
    Returns the number of sessions in the model.

    ## Examples

        iex> model = %Model{sessions: %{"s1" => s1, "s2" => s2}}
        iex> Model.session_count(model)
        2
    """
    @spec session_count(t()) :: non_neg_integer()
    def session_count(%__MODULE__{sessions: sessions}), do: map_size(sessions)

    @doc """
    Removes a session from the model.

    Removes the session from both the sessions map and session_order list.
    If the removed session was active, switches to the previous session in order,
    or the next session if it was first, or nil if it was the last session.

    ## Examples

        iex> model = %Model{sessions: %{"s1" => s1, "s2" => s2}, session_order: ["s1", "s2"], active_session_id: "s2"}
        iex> model = Model.remove_session(model, "s2")
        iex> model.active_session_id
        "s1"

        iex> model = Model.remove_session(model, "s1")
        iex> model.active_session_id
        nil
    """
    @spec remove_session(t(), String.t()) :: t()
    def remove_session(%__MODULE__{} = model, session_id) do
      # Unsubscribe from the session's events before removal
      JidoCode.TUI.unsubscribe_from_session(session_id)

      # Remove from sessions map
      new_sessions = Map.delete(model.sessions, session_id)

      # Remove from session_order
      new_order = Enum.reject(model.session_order, &(&1 == session_id))

      # Determine new active session if we're closing the active one
      new_active_id =
        if model.active_session_id == session_id do
          # Find the index of the closed session in the original order
          old_index = Enum.find_index(model.session_order, &(&1 == session_id)) || 0

          cond do
            # No sessions left
            new_order == [] ->
              nil

            # Try previous session (go back one index)
            old_index > 0 ->
              Enum.at(new_order, old_index - 1)

            # Otherwise take the first remaining session
            true ->
              List.first(new_order)
          end
        else
          model.active_session_id
        end

      %{
        model
        | sessions: new_sessions,
          session_order: new_order,
          active_session_id: new_active_id
      }
    end

    @doc """
    Renames a session in the model.

    Updates the session's name in the sessions map.

    ## Parameters
      - model: The current model state
      - session_id: The ID of the session to rename
      - new_name: The new name for the session

    ## Returns
      The updated model with the renamed session.

    ## Examples

        iex> session = %{id: "s1", name: "old-name", project_path: "/path"}
        iex> model = %Model{sessions: %{"s1" => session}, session_order: ["s1"], active_session_id: "s1"}
        iex> model = Model.rename_session(model, "s1", "new-name")
        iex> model.sessions["s1"].name
        "new-name"
    """
    @spec rename_session(t(), String.t(), String.t()) :: t()
    def rename_session(%__MODULE__{} = model, session_id, new_name) do
      case Map.get(model.sessions, session_id) do
        nil ->
          # Session not found, return unchanged
          model

        session ->
          # Update the session name
          updated_session = Map.put(session, :name, new_name)
          new_sessions = Map.put(model.sessions, session_id, updated_session)
          %{model | sessions: new_sessions}
      end
    end

    # =========================================================================
    # Per-Session UI State Helpers
    # =========================================================================

    @doc """
    Creates default UI state for a new session.

    ## Parameters
      - window: Tuple of {width, height} for viewport sizing

    ## Returns
      A session_ui_state map with initialized fields.
    """
    @spec default_ui_state({non_neg_integer(), non_neg_integer()}) :: session_ui_state()
    def default_ui_state({width, height}) do
      # Create TextInput for this session
      text_input_props =
        TermUI.Widgets.TextInput.new(
          placeholder: "Type a message...",
          width: max(width - 4, 20),
          enter_submits: false
        )

      {:ok, text_input_state} = TermUI.Widgets.TextInput.init(text_input_props)

      # Create ConversationView for this session
      # Available height: total height - 2 (borders) - 1 (status bar) - 3 (separators) - 1 (input bar) - 1 (help bar)
      conversation_height = max(height - 8, 1)
      conversation_width = max(width - 4, 1)

      conversation_view_props =
        JidoCode.TUI.Widgets.ConversationView.new(
          messages: [],
          viewport_width: conversation_width,
          viewport_height: conversation_height,
          on_copy: &JidoCode.TUI.Clipboard.copy_to_clipboard/1
        )

      {:ok, conversation_view_state} = JidoCode.TUI.Widgets.ConversationView.init(conversation_view_props)

      # Create Accordion for this session's sidebar sections
      accordion =
        JidoCode.TUI.Widgets.Accordion.new(
          sections: [
            %{id: :info, title: "Info", content: []},
            %{id: :files, title: "Files", content: []},
            %{id: :tools, title: "Tools", content: []}
          ],
          active_ids: [:info]
        )

      %{
        text_input: text_input_state,
        conversation_view: conversation_view_state,
        accordion: accordion,
        scroll_offset: 0,
        streaming_message: nil,
        is_streaming: false,
        reasoning_steps: [],
        tool_calls: [],
        messages: [],
        agent_activity: :idle,
        awaiting_input: nil
      }
    end

    @doc """
    Gets the UI state for a specific session.

    Returns nil if the session doesn't exist or has no UI state.

    ## Examples

        iex> Model.get_session_ui_state(model, "session-123")
        %{text_input: ..., conversation_view: ..., ...}
    """
    @spec get_session_ui_state(t(), String.t()) :: session_ui_state() | nil
    def get_session_ui_state(%__MODULE__{sessions: sessions}, session_id) do
      case Map.get(sessions, session_id) do
        nil -> nil
        session_data -> Map.get(session_data, :ui_state)
      end
    end

    @doc """
    Gets the UI state for the active session.

    Returns nil if no active session or if the session has no UI state.

    ## Examples

        iex> Model.get_active_ui_state(model)
        %{text_input: ..., conversation_view: ..., ...}
    """
    @spec get_active_ui_state(t()) :: session_ui_state() | nil
    def get_active_ui_state(%__MODULE__{active_session_id: nil}), do: nil

    def get_active_ui_state(%__MODULE__{active_session_id: id} = model) do
      get_session_ui_state(model, id)
    end

    @doc """
    Updates the UI state for a specific session.

    Takes a function that receives the current UI state and returns the new UI state.
    If the session doesn't exist, returns the model unchanged.

    ## Examples

        iex> Model.update_session_ui_state(model, "session-123", fn ui ->
        ...>   %{ui | scroll_offset: ui.scroll_offset + 1}
        ...> end)
    """
    @spec update_session_ui_state(t(), String.t(), (session_ui_state() -> session_ui_state())) ::
            t()
    def update_session_ui_state(%__MODULE__{sessions: sessions} = model, session_id, fun) do
      case Map.get(sessions, session_id) do
        nil ->
          model

        session_data ->
          current_ui = Map.get(session_data, :ui_state) || default_ui_state(model.window)
          new_ui = fun.(current_ui)
          updated_session = Map.put(session_data, :ui_state, new_ui)
          %{model | sessions: Map.put(sessions, session_id, updated_session)}
      end
    end

    @doc """
    Updates the UI state for the active session.

    Convenience function that calls update_session_ui_state with the active session ID.
    If no session is active, returns the model unchanged.

    ## Examples

        iex> Model.update_active_ui_state(model, fn ui ->
        ...>   %{ui | is_streaming: true}
        ...> end)
    """
    @spec update_active_ui_state(t(), (session_ui_state() -> session_ui_state())) :: t()
    def update_active_ui_state(%__MODULE__{active_session_id: nil} = model, _fun), do: model

    def update_active_ui_state(%__MODULE__{active_session_id: id} = model, fun) do
      update_session_ui_state(model, id, fun)
    end

    @doc """
    Gets the text input state for the active session.

    Returns nil if no active session or if the session has no UI state.
    """
    @spec get_active_text_input(t()) :: map() | nil
    def get_active_text_input(model) do
      case get_active_ui_state(model) do
        nil -> nil
        ui_state -> ui_state.text_input
      end
    end

    @doc """
    Gets the conversation view for the active session.

    Returns nil if no active session or if the session has no UI state.
    """
    @spec get_active_conversation_view(t()) :: map() | nil
    def get_active_conversation_view(model) do
      case get_active_ui_state(model) do
        nil -> nil
        ui_state -> ui_state.conversation_view
      end
    end

    @doc """
    Gets the accordion for the active session.

    Returns nil if no active session or if the session has no UI state.
    """
    @spec get_active_accordion(t()) :: JidoCode.TUI.Widgets.Accordion.t() | nil
    def get_active_accordion(model) do
      case get_active_ui_state(model) do
        nil -> nil
        ui_state -> ui_state.accordion
      end
    end

    @doc """
    Gets the agent activity for the active session.

    Returns `:idle` if no active session or if the session has no UI state.

    ## Examples

        Model.get_active_agent_activity(model)
        # => :idle
        # => {:thinking, :chat}
        # => {:thinking, :chain_of_thought}
        # => {:tool_executing, "read_file"}
    """
    @spec get_active_agent_activity(t()) :: agent_activity()
    def get_active_agent_activity(model) do
      case get_active_ui_state(model) do
        nil -> :idle
        ui_state -> ui_state.agent_activity || :idle
      end
    end

    @doc """
    Gets the agent activity for a specific session.

    ## Examples

        Model.get_session_agent_activity(model, session_id)
        # => :idle
        # => {:thinking, :chat}
    """
    @spec get_session_agent_activity(t(), String.t()) :: agent_activity()
    def get_session_agent_activity(model, session_id) do
      case get_session_ui_state(model, session_id) do
        nil -> :idle
        ui_state -> ui_state.agent_activity || :idle
      end
    end

    @doc """
    Sets the agent activity for the active session.

    ## Examples

        Model.set_active_agent_activity(model, {:thinking, :chat})
        Model.set_active_agent_activity(model, {:tool_executing, "read_file"})
        Model.set_active_agent_activity(model, :idle)
    """
    @spec set_active_agent_activity(t(), agent_activity()) :: t()
    def set_active_agent_activity(model, activity) do
      update_active_ui_state(model, fn ui ->
        %{ui | agent_activity: activity}
      end)
    end

    @doc """
    Sets the agent activity for a specific session.

    ## Examples

        Model.set_session_agent_activity(model, session_id, {:thinking, :react})
    """
    @spec set_session_agent_activity(t(), String.t(), agent_activity()) :: t()
    def set_session_agent_activity(model, session_id, activity) do
      update_session_ui_state(model, session_id, fn ui ->
        %{ui | agent_activity: activity}
      end)
    end

    @doc """
    Converts agent activity to a display icon and style for tab headers.

    Returns `{icon, style}` tuple, or `{nil, nil}` for idle/unconfigured states.

    ## Examples

        Model.activity_icon_for(:idle)
        # => {nil, nil}

        Model.activity_icon_for({:thinking, :chat})
        # => {"⚙", %Style{fg: :yellow}}

        Model.activity_icon_for({:tool_executing, "read_file"})
        # => {"⚙", %Style{fg: :cyan}}
    """
    @spec activity_icon_for(agent_activity()) :: {String.t() | nil, Style.t() | nil}
    def activity_icon_for(:idle), do: {nil, nil}
    def activity_icon_for(:unconfigured), do: {nil, nil}

    def activity_icon_for({:thinking, _mode}) do
      {"⚙", Style.new(fg: :yellow)}
    end

    def activity_icon_for({:tool_executing, _tool_name}) do
      {"⚙", Style.new(fg: :cyan)}
    end

    def activity_icon_for({:error, _reason}) do
      {"⚠", Style.new(fg: :red)}
    end

    def activity_icon_for(_), do: {nil, nil}

    # -------------------------------------------------------------------------
    # Awaiting Input Accessors
    # -------------------------------------------------------------------------

    @doc """
    Gets the awaiting_input state for the active session.

    ## Examples

        Model.get_active_awaiting_input(model)
        # => nil
        # => :clarification
        # => :permission
    """
    @spec get_active_awaiting_input(t()) :: awaiting_input()
    def get_active_awaiting_input(model) do
      case get_active_ui_state(model) do
        nil -> nil
        ui_state -> ui_state.awaiting_input
      end
    end

    @doc """
    Gets the awaiting_input state for a specific session.

    ## Examples

        Model.get_session_awaiting_input(model, session_id)
        # => nil
        # => :permission
    """
    @spec get_session_awaiting_input(t(), String.t()) :: awaiting_input()
    def get_session_awaiting_input(model, session_id) do
      case get_session_ui_state(model, session_id) do
        nil -> nil
        ui_state -> ui_state.awaiting_input
      end
    end

    @doc """
    Sets the awaiting_input state for the active session.

    ## Examples

        Model.set_active_awaiting_input(model, :clarification)
        Model.set_active_awaiting_input(model, :permission)
        Model.set_active_awaiting_input(model, nil)  # Clear waiting state
    """
    @spec set_active_awaiting_input(t(), awaiting_input()) :: t()
    def set_active_awaiting_input(model, awaiting) do
      update_active_ui_state(model, fn ui ->
        %{ui | awaiting_input: awaiting}
      end)
    end

    @doc """
    Sets the awaiting_input state for a specific session.

    ## Examples

        Model.set_session_awaiting_input(model, session_id, :permission)
    """
    @spec set_session_awaiting_input(t(), String.t(), awaiting_input()) :: t()
    def set_session_awaiting_input(model, session_id, awaiting) do
      update_session_ui_state(model, session_id, fn ui ->
        %{ui | awaiting_input: awaiting}
      end)
    end

    @doc """
    Converts awaiting_input state to a display icon and style for tab headers.

    Returns `{icon, style}` tuple, or `{nil, nil}` when not waiting.
    The awaiting icon takes precedence over activity icon when displayed.

    ## Examples

        Model.awaiting_input_icon_for(nil)
        # => {nil, nil}

        Model.awaiting_input_icon_for(:clarification)
        # => {"?", %Style{fg: :magenta}}

        Model.awaiting_input_icon_for(:permission)
        # => {"⚡", %Style{fg: :yellow}}
    """
    @spec awaiting_input_icon_for(awaiting_input()) :: {String.t() | nil, Style.t() | nil}
    def awaiting_input_icon_for(nil), do: {nil, nil}

    def awaiting_input_icon_for(:clarification) do
      {"?", Style.new(fg: :magenta, attrs: [:bold])}
    end

    def awaiting_input_icon_for(:permission) do
      {"⚡", Style.new(fg: :yellow, attrs: [:bold])}
    end

    def awaiting_input_icon_for(:confirmation) do
      {"!", Style.new(fg: :cyan, attrs: [:bold])}
    end

    @doc """
    Checks if the active session is currently streaming.

    Returns false if no active session.
    """
    @spec active_session_streaming?(t()) :: boolean()
    def active_session_streaming?(model) do
      case get_active_ui_state(model) do
        nil -> false
        ui_state -> ui_state.is_streaming
      end
    end
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

    # Load existing sessions from registry and subscribe to their topics
    sessions = load_sessions_from_registry()
    session_order = Enum.map(sessions, & &1.id)
    active_id = List.first(session_order)
    subscribe_to_all_sessions(sessions)

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
    # Content width excludes borders (2) and padding (2)
    conversation_width = max(width - 4, 1)

    conversation_view_props =
      ConversationView.new(
        messages: [],
        viewport_width: conversation_width,
        viewport_height: conversation_height,
        on_copy: &Clipboard.copy_to_clipboard/1
      )

    {:ok, conversation_view_state} = ConversationView.init(conversation_view_props)

    # Add UI state to each loaded session
    sessions_with_ui =
      Map.new(sessions, fn session ->
        session_with_ui = Map.put(session, :ui_state, Model.default_ui_state(window))
        {session.id, session_with_ui}
      end)

    %Model{
      # Multi-session fields
      sessions: sessions_with_ui,
      session_order: session_order,
      active_session_id: active_id,
      # Existing fields
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
      conversation_view: conversation_view_state,
      # Sidebar state (Phase 4.5)
      sidebar_visible: true,
      sidebar_width: 20,
      sidebar_expanded: MapSet.new(),
      sidebar_selected_index: 0
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

  # Ctrl+S to toggle sidebar visibility
  def event_to_msg(%Event.Key{key: "s", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, :toggle_sidebar}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Ctrl+W to close current session
  def event_to_msg(%Event.Key{key: "w", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, :close_active_session}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Ctrl+N to create new session
  def event_to_msg(%Event.Key{key: "n", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, :create_new_session}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Ctrl+1 through Ctrl+9 to switch to session by index
  def event_to_msg(%Event.Key{key: key, modifiers: modifiers} = event, _state)
      when key in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    if :ctrl in modifiers do
      index = String.to_integer(key)
      {:msg, {:switch_to_session_index, index}}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Ctrl+0 to switch to session 10 (the 10th tab)
  def event_to_msg(%Event.Key{key: "0", modifiers: modifiers} = event, _state) do
    if :ctrl in modifiers do
      {:msg, {:switch_to_session_index, 10}}
    else
      {:msg, {:input_event, event}}
    end
  end

  # Up arrow when sidebar focused - navigate to previous session
  def event_to_msg(%Event.Key{key: :up}, %Model{focus: :sidebar} = _state) do
    {:msg, {:sidebar_nav, :up}}
  end

  # Down arrow when sidebar focused - navigate to next session
  def event_to_msg(%Event.Key{key: :down}, %Model{focus: :sidebar} = _state) do
    {:msg, {:sidebar_nav, :down}}
  end

  # Enter key when sidebar focused - toggle accordion section
  def event_to_msg(%Event.Key{key: :enter}, %Model{focus: :sidebar} = state) do
    if state.sidebar_selected_index < length(state.session_order) do
      session_id = Enum.at(state.session_order, state.sidebar_selected_index)
      {:msg, {:toggle_accordion, session_id}}
    else
      :ignore
    end
  end

  # Enter key - forward to modal if open, otherwise submit current input
  def event_to_msg(%Event.Key{key: :enter} = event, state) do
    cond do
      state.pick_list ->
        {:msg, {:pick_list_event, event}}

      state.shell_dialog ->
        {:msg, {:input_event, event}}

      true ->
        # Get value from active session's text input
        text_input = Model.get_active_text_input(state)
        value = if text_input, do: TextInput.get_value(text_input), else: ""
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

  # Tab key - Ctrl+Tab cycles sessions, Tab/Shift+Tab cycles focus
  def event_to_msg(%Event.Key{key: :tab, modifiers: modifiers}, _state) do
    cond do
      # Ctrl+Shift+Tab → previous session
      :ctrl in modifiers and :shift in modifiers ->
        {:msg, :prev_tab}

      # Ctrl+Tab → next session
      :ctrl in modifiers ->
        {:msg, :next_tab}

      # Shift+Tab → focus backward
      :shift in modifiers ->
        {:msg, {:cycle_focus, :backward}}

      # Tab → focus forward
      true ->
        {:msg, {:cycle_focus, :forward}}
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

  # Forward keyboard events to active session's TextInput widget
  def update({:input_event, event}, state) do
    case Model.get_active_text_input(state) do
      nil ->
        # No active session, ignore input
        {state, []}

      text_input ->
        {:ok, new_text_input} = TextInput.handle_event(event, text_input)

        new_state =
          Model.update_active_ui_state(state, fn ui ->
            %{ui | text_input: new_text_input}
          end)

        {new_state, []}
    end
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
        # Clear active session's input after command and ensure it stays focused
        cleared_state =
          Model.update_active_ui_state(state, fn ui ->
            new_text_input = ui.text_input |> TextInput.clear() |> TextInput.set_focused(true)
            %{ui | text_input: new_text_input}
          end)

        do_handle_command(text, cleared_state)

      # Chat input - requires configured provider/model
      true ->
        # Clear active session's input after submit
        cleared_state =
          Model.update_active_ui_state(state, fn ui ->
            new_text_input = TextInput.clear(ui.text_input)
            %{ui | text_input: new_text_input}
          end)

        do_handle_chat_submit(text, cleared_state)
    end
  end

  def update(:quit, state) do
    # Clear terminal and disable mouse tracking before quitting
    # This ensures clean exit even if Runtime cleanup is incomplete
    IO.write("\e[?1006l\e[?1003l\e[?1002l\e[?1000l")  # Disable mouse modes
    IO.write("\e[?25h")  # Show cursor
    IO.write("\e[2J\e[H")  # Clear screen and move to top-left
    {state, [:quit]}
  end

  def update({:resize, width, height}, state) do
    {cur_width, cur_height} = state.window
    new_input_width = max(width - 4, 20)
    conversation_height = max(height - 8, 1)
    conversation_width = max(width - 4, 1)

    # Update all sessions' UI state if window size changed
    new_sessions =
      if width != cur_width or height != cur_height do
        Map.new(state.sessions, fn {session_id, session} ->
          case Map.get(session, :ui_state) do
            nil ->
              {session_id, session}

            ui_state ->
              # Update text input width
              new_text_input =
                if ui_state.text_input do
                  %{ui_state.text_input | width: new_input_width}
                else
                  ui_state.text_input
                end

              # Update conversation view dimensions
              new_conversation_view =
                if ui_state.conversation_view do
                  ConversationView.set_viewport_size(
                    ui_state.conversation_view,
                    conversation_width,
                    conversation_height
                  )
                else
                  ui_state.conversation_view
                end

              updated_ui = %{ui_state | text_input: new_text_input, conversation_view: new_conversation_view}
              {session_id, Map.put(session, :ui_state, updated_ui)}
          end
        end)
      else
        state.sessions
      end

    {%{state | window: {width, height}, sessions: new_sessions}, []}
  end

  # ConversationView event handling - delegate keyboard and mouse events to active session's view
  def update({:conversation_event, event}, state) do
    case Model.get_active_conversation_view(state) do
      nil ->
        # No active session or conversation view, ignore
        {state, []}

      conversation_view ->
        case ConversationView.handle_event(event, conversation_view) do
          {:ok, new_conversation_view} ->
            new_state =
              Model.update_active_ui_state(state, fn ui ->
                %{ui | conversation_view: new_conversation_view}
              end)

            {new_state, []}

          _ ->
            {state, []}
        end
    end
  end

  # PubSub message handlers - delegated to MessageHandlers module
  # Note: Messages are stored in reverse order (newest first) for O(1) prepend
  def update({:agent_response, content}, state),
    do: MessageHandlers.handle_agent_response(content, state)

  # Streaming message handlers
  def update({:stream_chunk, session_id, chunk}, state),
    do: MessageHandlers.handle_stream_chunk(session_id, chunk, state)

  def update({:stream_end, session_id, full_content}, state),
    do: MessageHandlers.handle_stream_end(session_id, full_content, state)

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

  # Toggle sidebar visibility (Ctrl+S)
  def update(:toggle_sidebar, state) do
    new_state = %{state | sidebar_visible: not state.sidebar_visible}
    {new_state, []}
  end

  # Navigate sidebar up/down
  def update({:sidebar_nav, :up}, state) do
    max_index = length(state.session_order) - 1

    new_index =
      if state.sidebar_selected_index == 0 do
        max_index  # Wrap to bottom
      else
        state.sidebar_selected_index - 1
      end

    new_state = %{state | sidebar_selected_index: new_index}
    {new_state, []}
  end

  def update({:sidebar_nav, :down}, state) do
    max_index = length(state.session_order) - 1

    new_index =
      if state.sidebar_selected_index >= max_index do
        0  # Wrap to top
      else
        state.sidebar_selected_index + 1
      end

    new_state = %{state | sidebar_selected_index: new_index}
    {new_state, []}
  end

  # Toggle accordion section expansion
  def update({:toggle_accordion, session_id}, state) do
    expanded =
      if MapSet.member?(state.sidebar_expanded, session_id) do
        MapSet.delete(state.sidebar_expanded, session_id)
      else
        MapSet.put(state.sidebar_expanded, session_id)
      end

    new_state = %{state | sidebar_expanded: expanded}
    {new_state, []}
  end

  # Cycle focus forward (Tab)
  def update({:cycle_focus, :forward}, state) do
    new_focus =
      case state.focus do
        :input -> :conversation
        :conversation -> if state.sidebar_visible, do: :sidebar, else: :input
        :sidebar -> :input
        _ -> :input
      end

    # Update active session's text input focus state
    focused = new_focus == :input

    new_state =
      Model.update_active_ui_state(%{state | focus: new_focus}, fn ui ->
        new_text_input =
          if ui.text_input do
            TextInput.set_focused(ui.text_input, focused)
          else
            ui.text_input
          end

        %{ui | text_input: new_text_input}
      end)

    {new_state, []}
  end

  # Cycle focus backward (Shift+Tab)
  def update({:cycle_focus, :backward}, state) do
    new_focus =
      case state.focus do
        :input -> if state.sidebar_visible, do: :sidebar, else: :conversation
        :conversation -> :input
        :sidebar -> :conversation
        _ -> :input
      end

    # Update active session's text input focus state
    focused = new_focus == :input

    new_state =
      Model.update_active_ui_state(%{state | focus: new_focus}, fn ui ->
        new_text_input =
          if ui.text_input do
            TextInput.set_focused(ui.text_input, focused)
          else
            ui.text_input
          end

        %{ui | text_input: new_text_input}
      end)

    {new_state, []}
  end

  # Close active session (Ctrl+W)
  def update(:close_active_session, state) do
    case state.active_session_id do
      nil ->
        # No active session to close
        new_state = add_session_message(state, "No active session to close.")
        {new_state, []}

      session_id ->
        # Get session name for the message
        session = Map.get(state.sessions, session_id)
        session_name = if session, do: session.name, else: session_id

        final_state = do_close_session(state, session_id, session_name)
        {final_state, []}
    end
  end

  # Create new session (Ctrl+N)
  def update(:create_new_session, state) do
    # Get current working directory
    case File.cwd() do
      {:ok, _path} ->
        # Use Commands.execute_session to create session for current directory
        # Path: nil means use current directory (handled by resolve_session_path)
        handle_session_command({:new, %{path: nil, name: nil}}, state)

      {:error, reason} ->
        # File.cwd() failure is rare but handle gracefully
        new_state = add_session_message(state, "Failed to get current directory: #{inspect(reason)}")
        {new_state, []}
    end
  end

  # Switch to session by index (Ctrl+1 through Ctrl+0)
  def update({:switch_to_session_index, index}, state) do
    case Model.get_session_by_index(state, index) do
      nil ->
        # No session at that index
        new_state = add_session_message(state, "No session at index #{index}.")
        {new_state, []}

      session ->
        if session.id == state.active_session_id do
          # Already on this session
          {state, []}
        else
          new_state =
            state
            |> Model.switch_session(session.id)
            |> refresh_conversation_view_for_session(session.id)
            |> clear_session_activity(session.id)
            |> focus_active_session_input()
            |> add_session_message("Switched to: #{session.name}")

          {new_state, []}
        end
    end
  end

  # Cycle to next session (Ctrl+Tab)
  def update(:next_tab, state) do
    case state.session_order do
      # No sessions (should not happen in practice)
      [] ->
        {state, []}

      # Single session - stay on current
      [_single] ->
        {state, []}

      # Multiple sessions - cycle forward
      order ->
        case Enum.find_index(order, &(&1 == state.active_session_id)) do
          nil ->
            # Active session not in order list (should not happen)
            {state, []}

          current_idx ->
            # Calculate next index with wrap-around
            next_idx = rem(current_idx + 1, length(order))
            next_id = Enum.at(order, next_idx)
            next_session = Map.get(state.sessions, next_id)

            new_state =
              state
              |> Model.switch_session(next_id)
              |> refresh_conversation_view_for_session(next_id)
              |> clear_session_activity(next_id)
              |> focus_active_session_input()
              |> add_session_message("Switched to: #{next_session.name}")

            {new_state, []}
        end
    end
  end

  # Cycle to previous session (Ctrl+Shift+Tab)
  def update(:prev_tab, state) do
    case state.session_order do
      [] -> {state, []}
      [_single] -> {state, []}

      order ->
        case Enum.find_index(order, &(&1 == state.active_session_id)) do
          nil -> {state, []}

          current_idx ->
            # Calculate previous index with wrap-around
            # Add length before modulo to handle negative wrap
            prev_idx = rem(current_idx - 1 + length(order), length(order))
            prev_id = Enum.at(order, prev_idx)
            prev_session = Map.get(state.sessions, prev_id)

            new_state =
              state
              |> Model.switch_session(prev_id)
              |> refresh_conversation_view_for_session(prev_id)
              |> clear_session_activity(prev_id)
              |> focus_active_session_input()
              |> add_session_message("Switched to: #{prev_session.name}")

            {new_state, []}
        end
    end
  end

  # Tool call handling - add pending tool call to list
  # The session_id in the message is for routing identification; we pass it through
  def update({:tool_call, tool_name, params, call_id, session_id}, state),
    do: MessageHandlers.handle_tool_call(session_id, tool_name, params, call_id, state)

  # Tool result handling - match result to pending call and update
  # The session_id in the message is for routing identification; we pass it through
  def update({:tool_result, %Result{} = result, session_id}, state),
    do: MessageHandlers.handle_tool_result(session_id, result, state)

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

        # Sync system message to active session's ConversationView
        updated_state =
          Model.update_active_ui_state(state, fn ui ->
            if ui.conversation_view do
              new_conversation_view =
                ConversationView.add_message(ui.conversation_view, %{
                  id: generate_message_id(),
                  role: :system,
                  content: message,
                  timestamp: DateTime.utc_now()
                })

              %{ui | conversation_view: new_conversation_view}
            else
              ui
            end
          end)

        new_state = %{
          updated_state
          | messages: [system_msg | updated_state.messages],
            config: updated_config,
            agent_status: new_status
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

        viewport_props =
          Viewport.new(
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

        # Sync error message to active session's ConversationView
        updated_state =
          Model.update_active_ui_state(state, fn ui ->
            if ui.conversation_view do
              new_conversation_view =
                ConversationView.add_message(ui.conversation_view, %{
                  id: generate_message_id(),
                  role: :system,
                  content: error_message,
                  timestamp: DateTime.utc_now()
                })

              %{ui | conversation_view: new_conversation_view}
            else
              ui
            end
          end)

        new_state = %{updated_state | messages: [error_msg | updated_state.messages]}
        {new_state, []}

      {:session, subcommand} ->
        # Handle session commands by executing the subcommand
        handle_session_command(subcommand, state)

      {:resume, subcommand} ->
        # Handle resume commands
        handle_resume_command(subcommand, state)
    end
  end

  # Handle session command execution and results
  defp handle_session_command(subcommand, state) do
    case Commands.execute_session(subcommand, state) do
      {:session_action, {:add_session, session}} ->
        # Add session to model and subscribe to its PubSub topic
        new_state =
          state
          |> Model.add_session(session)
          |> focus_active_session_input()

        # Subscribe to session-specific events
        Phoenix.PubSub.subscribe(JidoCode.PubSub, PubSubTopics.llm_stream(session.id))

        final_state = add_session_message(new_state, "Created session: #{session.name}")
        {final_state, []}

      {:session_action, {:switch_session, session_id}} ->
        # Switch to the specified session and refresh conversation view
        new_state =
          state
          |> Model.switch_session(session_id)
          |> refresh_conversation_view_for_session(session_id)
          |> clear_session_activity(session_id)
          |> focus_active_session_input()

        # Get session name for the message
        session = Map.get(new_state.sessions, session_id)
        session_name = if session, do: session.name, else: session_id

        final_state = add_session_message(new_state, "Switched to: #{session_name}")
        {final_state, []}

      {:session_action, {:close_session, session_id, session_name}} ->
        final_state = do_close_session(state, session_id, session_name)
        {final_state, []}

      {:session_action, {:rename_session, session_id, new_name}} ->
        new_state = Model.rename_session(state, session_id, new_name)
        final_state = add_session_message(new_state, "Renamed session to: #{new_name}")
        {final_state, []}

      {:ok, message} ->
        new_state = add_session_message(state, message)
        {new_state, []}

      {:error, error_message} ->
        new_state = add_session_message(state, error_message)
        {new_state, []}
    end
  end

  # Handle resume command execution and results
  defp handle_resume_command(subcommand, state) do
    case Commands.execute_resume(subcommand, state) do
      {:session_action, {:add_session, session}} ->
        # Session resumed - add to model and subscribe
        new_state =
          state
          |> Model.add_session(session)
          |> focus_active_session_input()

        # Subscribe to session-specific events
        Phoenix.PubSub.subscribe(JidoCode.PubSub, PubSubTopics.llm_stream(session.id))

        final_state = add_session_message(new_state, "Resumed session: #{session.name}")
        {final_state, []}

      {:ok, message} ->
        # List output or informational message
        new_state = add_session_message(state, message)
        {new_state, []}

      {:error, error_message} ->
        # Error during resume
        new_state = add_session_message(state, error_message)
        {new_state, []}
    end
  end

  # Helper to add a system message to both messages list and conversation view
  defp add_session_message(state, content) do
    msg = system_message(content)

    # Add message to active session's conversation view
    new_state =
      Model.update_active_ui_state(state, fn ui ->
        if ui.conversation_view do
          new_conversation_view =
            ConversationView.add_message(ui.conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: content,
              timestamp: DateTime.utc_now()
            })

          %{ui | conversation_view: new_conversation_view}
        else
          ui
        end
      end)

    %{new_state | messages: [msg | new_state.messages]}
  end

  # Helper to close a session with proper cleanup order
  # Unsubscribes from PubSub BEFORE stopping the session to avoid race conditions
  defp do_close_session(state, session_id, session_name) do
    # Unsubscribe first to prevent receiving messages during teardown
    Phoenix.PubSub.unsubscribe(JidoCode.PubSub, PubSubTopics.llm_stream(session_id))

    # Stop the session process
    JidoCode.SessionSupervisor.stop_session(session_id)

    # Remove session from model
    new_state = Model.remove_session(state, session_id)

    # Add confirmation message
    add_session_message(new_state, "Closed session: #{session_name}")
  end

  # Helper to refresh a session's conversation_view with messages from Session.State
  # Used when switching sessions to ensure the messages are loaded
  defp refresh_conversation_view_for_session(state, session_id) do
    case Session.State.get_messages(session_id) do
      {:ok, messages} ->
        # Update the session's conversation view with its messages
        Model.update_session_ui_state(state, session_id, fn ui ->
          new_conversation_view =
            if ui.conversation_view do
              ConversationView.set_messages(ui.conversation_view, messages)
            else
              ui.conversation_view
            end

          %{ui | conversation_view: new_conversation_view, messages: messages}
        end)

      {:error, _reason} ->
        # Couldn't fetch messages, keep existing view
        # This shouldn't happen in normal operation
        state
    end
  end

  # Helper to clear session activity indicators when switching to a session
  # Clears unread count since user is now viewing the session
  defp clear_session_activity(state, session_id) do
    %{state | unread_counts: Map.delete(state.unread_counts, session_id)}
  end

  # Helper to set focus on the active session's text input when focus is on input
  # Used after switching sessions to ensure the new session's input is focused
  defp focus_active_session_input(state) do
    if state.focus == :input do
      Model.update_active_ui_state(state, fn ui ->
        new_text_input =
          if ui.text_input do
            TextInput.set_focused(ui.text_input, true)
          else
            ui.text_input
          end

        %{ui | text_input: new_text_input}
      end)
    else
      state
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
    error_content =
      "Please configure a model first. Use /model <provider>:<model> or Ctrl+M to select."

    error_msg = system_message(error_content)

    # Sync error message to active session's ConversationView
    updated_state =
      Model.update_active_ui_state(state, fn ui ->
        if ui.conversation_view do
          new_conversation_view =
            ConversationView.add_message(ui.conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: error_content,
              timestamp: DateTime.utc_now()
            })

          %{ui | conversation_view: new_conversation_view}
        else
          ui
        end
      end)

    new_state = %{updated_state | messages: [error_msg | updated_state.messages]}
    {new_state, []}
  end

  defp do_dispatch_to_agent(text, state) do
    case state.active_session_id do
      nil ->
        do_show_no_session_error(state)

      session_id ->
        # Sync user message to active session's ConversationView for display
        state_with_message =
          Model.update_active_ui_state(state, fn ui ->
            if ui.conversation_view do
              new_conversation_view =
                ConversationView.add_message(ui.conversation_view, %{
                  id: generate_message_id(),
                  role: :user,
                  content: text,
                  timestamp: DateTime.utc_now()
                })

              %{ui | conversation_view: new_conversation_view}
            else
              ui
            end
          end)

        # Send message to active session's agent
        # User message is stored in Session.State automatically by AgentAPI
        case Session.AgentAPI.send_message_stream(session_id, text) do
          :ok ->
            # Update active session's UI state to show streaming
            state_streaming =
              Model.update_active_ui_state(state_with_message, fn ui ->
                %{ui | streaming_message: "", is_streaming: true}
              end)

            # Update model-level state
            updated_state = %{
              state_streaming
              | agent_status: :processing,
                scroll_offset: 0
            }

            {updated_state, []}

          {:error, reason} ->
            do_show_agent_error(state_with_message, reason)
        end
    end
  end

  defp do_show_no_session_error(state) do
    error_content = """
    No active session. Create a session first with:
      /session new <path> --name="Session Name"

    Or switch to an existing session with:
      /session switch <index>
    """

    error_msg = system_message(error_content)

    # Add to active session's ConversationView
    updated_state =
      Model.update_active_ui_state(state, fn ui ->
        if ui.conversation_view do
          new_conversation_view =
            ConversationView.add_message(ui.conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: error_content,
              timestamp: DateTime.utc_now()
            })

          %{ui | conversation_view: new_conversation_view}
        else
          ui
        end
      end)

    new_state = %{updated_state | messages: [error_msg | updated_state.messages]}
    {new_state, []}
  end

  defp do_show_agent_error(state, reason) do
    error_content = "Failed to send message to session agent: #{inspect(reason)}"
    error_msg = system_message(error_content)

    # Add to active session's ConversationView
    updated_state =
      Model.update_active_ui_state(state, fn ui ->
        if ui.conversation_view do
          new_conversation_view =
            ConversationView.add_message(ui.conversation_view, %{
              id: generate_message_id(),
              role: :system,
              content: error_content,
              timestamp: DateTime.utc_now()
            })

          %{ui | conversation_view: new_conversation_view}
        else
          ui
        end
      end)

    new_state = %{
      updated_state
      | messages: [error_msg | updated_state.messages],
        agent_status: :error
    }

    {new_state, []}
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
    {width, height} = state.window

    # Use new MainLayout (SplitPane with sidebar + tabs)
    layout = build_main_layout(state)
    area = %{x: 0, y: 0, width: width, height: height}

    # Render input bar and help bar to pass into tabs
    input_view = ViewHelpers.render_input_bar(state)
    help_view = ViewHelpers.render_help_bar(state)

    # Render main layout with input/help inside tabs
    MainLayout.render(layout, area,
      input_view: input_view,
      help_view: help_view
    )
  end

  # Build MainLayout widget from model state
  @doc false
  @spec build_main_layout(Model.t()) :: MainLayout.t()
  defp build_main_layout(state) do
    # Convert sessions to MainLayout format
    session_data =
      Map.new(state.session_order, fn id ->
        session = Map.get(state.sessions, id)

        if session do
          # Get the tab icon - awaiting_input takes precedence over activity
          {icon, icon_style} = get_session_tab_icon(state, id)

          {id,
           %{
             id: id,
             name: session.name,
             project_path: session.project_path,
             created_at: session.created_at,
             status: get_session_status(id),
             message_count: get_message_count(id),
             content: get_conversation_content(state, id),
             activity_icon: icon,
             activity_style: icon_style
           }}
        else
          {id, %{id: id, name: "Unknown", project_path: "", created_at: DateTime.utc_now()}}
        end
      end)

    MainLayout.new(
      sessions: session_data,
      session_order: state.session_order,
      active_session_id: state.active_session_id,
      sidebar_expanded: state.sidebar_expanded,
      sidebar_proportion: 0.20
    )
  end

  defp get_session_status(session_id) do
    case Session.AgentAPI.get_status(session_id) do
      {:ok, %{ready: true}} -> :idle
      {:ok, %{ready: false}} -> :processing
      {:error, _} -> :unconfigured
    end
  end

  defp get_message_count(session_id) do
    case Session.State.get_messages(session_id, 0, 1) do
      {:ok, _messages, %{total: total}} -> total
      _ -> 0
    end
  end

  defp get_conversation_content(state, session_id) do
    # Get the session's conversation view from its UI state
    case Model.get_session_ui_state(state, session_id) do
      nil ->
        nil

      ui_state when ui_state.conversation_view != nil ->
        {width, height} = state.window
        available_height = max(height - 10, 1)
        content_width = max(width - round(width * 0.20) - 5, 30)
        area = %{x: 0, y: 0, width: content_width, height: available_height}
        ConversationView.render(ui_state.conversation_view, area)

      _ ->
        nil
    end
  end

  # Determines the tab icon for a session.
  # awaiting_input takes precedence over agent_activity.
  defp get_session_tab_icon(state, session_id) do
    awaiting = Model.get_session_awaiting_input(state, session_id)

    case Model.awaiting_input_icon_for(awaiting) do
      {nil, nil} ->
        # No awaiting input, fall back to activity icon
        activity = Model.get_session_agent_activity(state, session_id)
        Model.activity_icon_for(activity)

      icon_and_style ->
        icon_and_style
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
    viewport_view =
      Viewport.render(state.shell_viewport, %{width: viewport_width, height: viewport_height})

    # Build dialog content with title, viewport, and footer
    title = text(state.shell_dialog.title, Style.new(fg: :cyan, attrs: [:bold]))
    footer = text("[Enter/Esc/q] Close  [↑↓/PgUp/PgDn] Scroll", Style.new(fg: :bright_black))

    dialog_content =
      stack(:vertical, [
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

  # Load all active sessions from SessionRegistry.
  #
  # Returns list of Session structs sorted by creation time (oldest first).
  # If the registry is empty or not initialized, returns an empty list.
  @spec load_sessions_from_registry() :: [Session.t()]
  defp load_sessions_from_registry do
    JidoCode.SessionRegistry.list_all()
  end

  # Subscribe to PubSub topic for a single session.
  #
  # Subscribes to the session's llm_stream topic to receive
  # streaming messages, tool calls, and other session events.
  #
  # This function is public to be accessible from the nested Model module.
  @spec subscribe_to_session(String.t()) :: :ok | {:error, term()}
  def subscribe_to_session(session_id) do
    topic = PubSubTopics.llm_stream(session_id)
    Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
  end

  # Unsubscribe from PubSub topic for a single session.
  #
  # Unsubscribes from the session's llm_stream topic to stop
  # receiving events from that session.
  #
  # This function is public to be accessible from the nested Model module.
  @spec unsubscribe_from_session(String.t()) :: :ok
  def unsubscribe_from_session(session_id) do
    topic = PubSubTopics.llm_stream(session_id)
    Phoenix.PubSub.unsubscribe(JidoCode.PubSub, topic)
  end

  # Subscribe to PubSub topics for all sessions.
  #
  # Subscribes to each session's llm_stream topic for receiving
  # streaming messages, tool calls, and other session events.
  @spec subscribe_to_all_sessions([Session.t()]) :: :ok
  defp subscribe_to_all_sessions(sessions) do
    Enum.each(sessions, fn session ->
      subscribe_to_session(session.id)
    end)
  end

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
    if ProviderKeys.local_provider?(provider) do
      true
    else
      key_name = ProviderKeys.to_key_name(provider)

      case Keyring.get(key_name) do
        nil -> false
        "" -> false
        _key -> true
      end
    end
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
