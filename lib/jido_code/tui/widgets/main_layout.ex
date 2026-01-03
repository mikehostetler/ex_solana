defmodule JidoCode.TUI.Widgets.MainLayout do
  @moduledoc """
  Main application layout using SplitPane with sidebar and tabs.

  Provides a two-pane layout:
  - **Left pane (20%)**: Session list accordion
  - **Right pane (80%)**: FolderTabs with session content

  ## Usage

      MainLayout.new(
        sessions: sessions,
        session_order: order,
        active_session_id: active_id
      )
      |> MainLayout.render(area)

  ## Visual Layout

      ╭──────────╮
      │ JidoCode ╰───────│╭───────────╮╭───────────╮
      → Session 1        ││ Session 1 ╰│ Session 2 │
        Session 2        ││ Status Bar                        │
                         │├───────────────────────────────────┤
                         ││                                   │
                         ││   Conversation View               │
                         ││                                   │
                         │├───────────────────────────────────┤
                         ││ Controls                          │
                         │└───────────────────────────────────┘

  """

  import TermUI.Component.Helpers

  alias TermUI.Widgets.SplitPane, as: SP
  alias JidoCode.TUI.Widgets.{FolderTabs, Accordion, Frame}
  # alias JidoCode.Session
  alias TermUI.Renderer.Style

  # Single-line box drawing characters for sidebar border
  @border %{
    top_left: "┌",
    top_right: "┐",
    bottom_left: "└",
    bottom_right: "┘",
    horizontal: "─",
    vertical: "│"
  }

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type session_data :: %{
          id: String.t(),
          name: String.t(),
          project_path: String.t(),
          created_at: DateTime.t(),
          status: atom(),
          message_count: non_neg_integer(),
          content: TermUI.View.t() | nil
        }

  @type t :: %__MODULE__{
          split_state: map() | nil,
          sidebar_state: Accordion.t() | nil,
          tabs_state: FolderTabs.t() | nil,
          sessions: %{String.t() => session_data()},
          session_order: [String.t()],
          active_session_id: String.t() | nil,
          sidebar_expanded: MapSet.t(),
          focused_pane: :sidebar | :tabs,
          sidebar_proportion: float()
        }

  defstruct split_state: nil,
            sidebar_state: nil,
            tabs_state: nil,
            sessions: %{},
            session_order: [],
            active_session_id: nil,
            sidebar_expanded: MapSet.new(),
            focused_pane: :tabs,
            sidebar_proportion: 0.20

  # ============================================================================
  # Constructor
  # ============================================================================

  @doc """
  Creates a new MainLayout with the given options.

  ## Options

    * `:sessions` - Map of session_id => session_data (default: %{})
    * `:session_order` - List of session IDs in display order (default: [])
    * `:active_session_id` - ID of the active session (default: nil)
    * `:sidebar_expanded` - MapSet of expanded session IDs (default: empty)
    * `:sidebar_proportion` - Sidebar width as proportion 0.0-1.0 (default: 0.20)

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    sessions = Keyword.get(opts, :sessions, %{})
    session_order = Keyword.get(opts, :session_order, [])
    active_session_id = Keyword.get(opts, :active_session_id)
    sidebar_expanded = Keyword.get(opts, :sidebar_expanded, MapSet.new())
    sidebar_proportion = Keyword.get(opts, :sidebar_proportion, 0.20)

    state = %__MODULE__{
      sessions: sessions,
      session_order: session_order,
      active_session_id: active_session_id,
      sidebar_expanded: sidebar_expanded,
      sidebar_proportion: sidebar_proportion,
      focused_pane: :tabs
    }

    # Build initial component states
    state
    |> build_sidebar_state()
    |> build_tabs_state()
    |> build_split_state()
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the main layout to a TermUI view tree.

  ## Parameters

    * `state` - The MainLayout state
    * `area` - Render area with x, y, width, height

  """
  @spec render(t(), map(), keyword()) :: TermUI.View.t()
  def render(%__MODULE__{} = state, area, opts \\ []) do
    # Rebuild component states with current data
    state = state |> build_sidebar_state() |> build_tabs_state()

    # Get optional views
    # input_view and mode_bar_view go inside tabs (per-session), help_view at bottom of whole layout
    input_view = Keyword.get(opts, :input_view)
    mode_bar_view = Keyword.get(opts, :mode_bar_view)
    help_view = Keyword.get(opts, :help_view)

    # Calculate heights for bottom bar (only help, input is inside tabs)
    help_height = if help_view, do: 1, else: 0
    main_height = area.height - help_height

    # Gap between sidebar and tabs (always 1 character)
    gap_width = 1

    # Render sidebar content (with full height)
    sidebar_width = round(area.width * state.sidebar_proportion)
    sidebar_view = render_sidebar(state, sidebar_width, main_height)

    # Render tabs content (status bar + conversation + input + mode bar)
    tabs_width = area.width - sidebar_width - gap_width
    tabs_view = render_tabs_pane(state, tabs_width, main_height, input_view, mode_bar_view)

    # Render gap (empty space between panes)
    gap_view = render_gap(main_height)

    # Compose horizontal layout (sidebar + gap + tabs)
    main_content = stack(:horizontal, [sidebar_view, gap_view, tabs_view])

    # Add help bar at bottom of whole layout
    if help_view do
      stack(:vertical, [main_content, help_view])
    else
      main_content
    end
  end

  @doc """
  Renders the layout using SplitPane for resizable panes.

  Use this for interactive resizing support.
  """
  @spec render_with_splitpane(t(), map()) :: TermUI.View.t()
  def render_with_splitpane(%__MODULE__{} = state, area) do
    if state.split_state do
      SP.render(state.split_state, area)
    else
      render(state, area)
    end
  end

  # ============================================================================
  # State Updates
  # ============================================================================

  @doc """
  Updates the sessions in the layout.
  """
  @spec update_sessions(t(), %{String.t() => session_data()}, [String.t()]) :: t()
  def update_sessions(state, sessions, order) do
    %{state | sessions: sessions, session_order: order}
    |> build_sidebar_state()
    |> build_tabs_state()
  end

  @doc """
  Sets the active session.
  """
  @spec set_active_session(t(), String.t() | nil) :: t()
  def set_active_session(state, session_id) do
    %{state | active_session_id: session_id}
    |> build_sidebar_state()
    |> build_tabs_state()
  end

  @doc """
  Updates the content for a specific session tab.
  """
  @spec update_session_content(t(), String.t(), TermUI.View.t()) :: t()
  def update_session_content(state, session_id, content) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session_data ->
        updated = Map.put(session_data, :content, content)
        sessions = Map.put(state.sessions, session_id, updated)
        %{state | sessions: sessions}
    end
  end

  @doc """
  Updates the status for a specific session.
  """
  @spec update_session_status(t(), String.t(), atom()) :: t()
  def update_session_status(state, session_id, status) do
    case Map.get(state.sessions, session_id) do
      nil ->
        state

      session_data ->
        updated = Map.put(session_data, :status, status)
        sessions = Map.put(state.sessions, session_id, updated)
        %{state | sessions: sessions}
    end
  end

  @doc """
  Toggles sidebar expansion for a session.
  """
  @spec toggle_sidebar_expanded(t(), String.t()) :: t()
  def toggle_sidebar_expanded(state, session_id) do
    expanded =
      if MapSet.member?(state.sidebar_expanded, session_id) do
        MapSet.delete(state.sidebar_expanded, session_id)
      else
        MapSet.put(state.sidebar_expanded, session_id)
      end

    %{state | sidebar_expanded: expanded}
    |> build_sidebar_state()
  end

  @doc """
  Switches focus between sidebar and tabs pane.
  """
  @spec toggle_focus(t()) :: t()
  def toggle_focus(state) do
    new_focus = if state.focused_pane == :sidebar, do: :tabs, else: :sidebar
    %{state | focused_pane: new_focus}
  end

  @doc """
  Sets the focused pane.
  """
  @spec set_focus(t(), :sidebar | :tabs) :: t()
  def set_focus(state, pane) when pane in [:sidebar, :tabs] do
    %{state | focused_pane: pane}
  end

  # ============================================================================
  # Event Handling
  # ============================================================================

  @doc """
  Handles keyboard/mouse events for the layout.

  Returns `{:ok, new_state}` if handled, `:ignore` otherwise.
  """
  @spec handle_event(t(), TermUI.Event.t()) :: {:ok, t()} | :ignore
  def handle_event(state, %{key: :tab, modifiers: []}) do
    # Tab cycles focus between panes
    {:ok, toggle_focus(state)}
  end

  def handle_event(state, event) do
    # Route to focused pane
    case state.focused_pane do
      :tabs -> handle_tabs_event(state, event)
      :sidebar -> handle_sidebar_event(state, event)
    end
  end

  defp handle_tabs_event(state, event) do
    if state.tabs_state do
      case FolderTabs.handle_key(state.tabs_state, event) do
        {:ok, new_tabs} ->
          # Sync active session with selected tab
          selected = FolderTabs.get_selected(new_tabs)
          {:ok, %{state | tabs_state: new_tabs, active_session_id: selected}}

        :ignore ->
          :ignore
      end
    else
      :ignore
    end
  end

  defp handle_sidebar_event(_state, event) do
    # Handle sidebar navigation
    case event do
      %{key: :enter} ->
        # Toggle expansion of focused session
        # For now, just ignore - can be enhanced later
        :ignore

      %{key: :up} ->
        :ignore

      %{key: :down} ->
        :ignore

      _ ->
        :ignore
    end
  end

  # ============================================================================
  # Tab Management
  # ============================================================================

  @doc """
  Selects a tab by session ID.
  """
  @spec select_tab(t(), String.t()) :: t()
  def select_tab(state, session_id) do
    tabs_state =
      if state.tabs_state do
        FolderTabs.select(state.tabs_state, session_id)
      else
        state.tabs_state
      end

    %{state | tabs_state: tabs_state, active_session_id: session_id}
  end

  @doc """
  Closes a tab by session ID, enforcing minimum one tab.

  Returns `{:ok, state}` if closed, `{:error, :last_tab}` if cannot close.
  """
  @spec close_tab(t(), String.t()) :: {:ok, t()} | {:error, :last_tab}
  def close_tab(state, session_id) do
    if length(state.session_order) <= 1 do
      {:error, :last_tab}
    else
      # Remove from order
      new_order = Enum.reject(state.session_order, &(&1 == session_id))
      new_sessions = Map.delete(state.sessions, session_id)

      # Update active session if needed
      new_active =
        if state.active_session_id == session_id do
          List.first(new_order)
        else
          state.active_session_id
        end

      new_state =
        %{state | sessions: new_sessions, session_order: new_order, active_session_id: new_active}
        |> build_tabs_state()
        |> build_sidebar_state()

      {:ok, new_state}
    end
  end

  @doc """
  Gets the number of tabs.
  """
  @spec tab_count(t()) :: non_neg_integer()
  def tab_count(state), do: length(state.session_order)

  # ============================================================================
  # Private: Build Component States
  # ============================================================================

  defp build_sidebar_state(state) do
    sections =
      Enum.map(state.session_order, fn session_id ->
        session_data = Map.get(state.sessions, session_id, %{})

        %{
          id: session_id,
          title: build_sidebar_title(state, session_id, session_data),
          badge: build_sidebar_badge(session_data),
          content: build_sidebar_content(session_data),
          icon_open: "▼",
          icon_closed: "▶",
          activity_icon: Map.get(session_data, :activity_icon),
          activity_style: Map.get(session_data, :activity_style)
        }
      end)

    sidebar_state =
      Accordion.new(
        sections: sections,
        active_ids: MapSet.to_list(state.sidebar_expanded),
        indent: 2
      )

    %{state | sidebar_state: sidebar_state}
  end

  defp build_sidebar_title(state, session_id, session_data) do
    prefix = if session_id == state.active_session_id, do: "→ ", else: "  "
    name = Map.get(session_data, :name, "Session")
    truncated = truncate(name, 15)
    prefix <> truncated
  end

  defp build_sidebar_badge(session_data) do
    count = Map.get(session_data, :message_count, 0)
    status = Map.get(session_data, :status, :idle)
    icon = status_icon(status)
    "(#{count}) #{icon}"
  end

  defp build_sidebar_content(_session_data) do
    # Sidebar only shows session names - all content is in tabs
    []
  end

  defp build_tabs_state(state) do
    tabs =
      Enum.map(state.session_order, fn session_id ->
        session_data = Map.get(state.sessions, session_id, %{})

        %{
          id: session_id,
          label: truncate(Map.get(session_data, :name, "Session"), 15),
          closeable: length(state.session_order) > 1,
          status: build_tab_status(session_data),
          content: Map.get(session_data, :content),
          controls: "Ctrl+W Close | Ctrl+Tab Next | /help",
          activity_icon: Map.get(session_data, :activity_icon),
          activity_style: Map.get(session_data, :activity_style)
        }
      end)

    # Ensure at least one tab
    tabs =
      if tabs == [] do
        [%{id: :new, label: "New Session", closeable: false}]
      else
        tabs
      end

    tabs_state =
      FolderTabs.new(
        tabs: tabs,
        selected: state.active_session_id || List.first(state.session_order)
      )

    %{state | tabs_state: tabs_state}
  end

  defp build_tab_status(session_data) do
    provider = Map.get(session_data, :provider)
    model = Map.get(session_data, :model)
    status = Map.get(session_data, :status, :idle)

    provider_text = if provider, do: "#{provider}", else: "none"
    model_text = if model, do: "#{model}", else: "none"
    status_text = format_status(status)

    # ⬢ = provider, ◆ = model
    "⬢ #{provider_text} | ◆ #{model_text} | #{status_text}"
  end

  defp format_status(:idle), do: "⚙  Idle"
  defp format_status(:processing), do: "⚙  Processing"
  defp format_status(:error), do: "⚙  Error"
  defp format_status(:unconfigured), do: "⚙  Idle"
  defp format_status(other), do: "⚙  " <> (Atom.to_string(other) |> String.capitalize())

  defp build_split_state(state) do
    # Build SplitPane state for resizable layout
    split_state =
      SP.init(
        SP.new(
          orientation: :horizontal,
          panes: [
            SP.pane(:sidebar, nil, size: state.sidebar_proportion, min_size: 15),
            SP.pane(:content, nil, size: 1.0 - state.sidebar_proportion, min_size: 30)
          ],
          resizable: true
        )
      )

    %{state | split_state: split_state}
  end

  # ============================================================================
  # Private: Rendering Helpers
  # ============================================================================

  defp render_sidebar(state, width, height) do
    border_style = Style.new(fg: :bright_black)

    # Content dimensions (inside top/bottom borders)
    inner_height = max(height - 2, 1)

    # Render header and session list
    header_view = render_sidebar_header(width)
    session_list = render_session_list(state, width)
    content = stack(:vertical, [header_view, session_list])

    # Wrap content in box to fill inner height
    content_box = box([content], width: width, height: inner_height)

    # Top and bottom borders only
    top_border = text(String.duplicate(@border.horizontal, width), border_style)
    bottom_border = text(String.duplicate(@border.horizontal, width), border_style)

    # Stack: top border, content, bottom border
    stack(:vertical, [top_border, content_box, bottom_border])
  end

  defp render_session_list(state, width) do
    if state.session_order == [] do
      muted_style = Style.new(fg: :bright_black)
      text(String.pad_trailing("  No sessions", width), muted_style)
    else
      session_items =
        Enum.map(state.session_order, fn session_id ->
          session_data = Map.get(state.sessions, session_id, %{})
          render_session_item(state, session_id, session_data, width)
        end)

      stack(:vertical, session_items)
    end
  end

  defp render_session_item(state, session_id, session_data, width) do
    is_active = session_id == state.active_session_id
    name = Map.get(session_data, :name, "Session")
    truncated = truncate(name, width - 4)

    # Style based on active state
    style =
      if is_active do
        Style.new(fg: :white, attrs: [:bold])
      else
        Style.new(fg: :bright_black)
      end

    # Active indicator
    prefix = if is_active, do: "→ ", else: "  "
    line = prefix <> truncated

    text(String.pad_trailing(line, width), style)
  end

  # Render sidebar header (2 lines to match tab height)
  defp render_sidebar_header(width) do
    title = "JidoCode"
    header_style = Style.new(fg: :cyan, attrs: [:bold])
    separator_style = Style.new(fg: :bright_black)

    # Line 1: Title
    line1 = String.pad_trailing(" " <> title, width)

    # Line 2: Horizontal separator
    separator = String.duplicate(@border.horizontal, width)

    stack(:vertical, [
      text(line1, header_style),
      text(separator, separator_style)
    ])
  end

  defp render_tabs_pane(state, width, height, input_view, mode_bar_view) do
    border_style = Style.new(fg: :bright_black)

    if state.tabs_state do
      # Render folder tabs (tab bar only - 2 rows) - outside the frame
      tab_bar = FolderTabs.render(state.tabs_state)
      tab_bar_height = 2

      # Frame dimensions (below tab bar)
      frame_height = max(height - tab_bar_height, 3)
      inner_width = max(width - 2, 1)
      inner_height = max(frame_height - 2, 1)

      # Get selected tab's status and content
      status_text = FolderTabs.get_selected_status(state.tabs_state) || ""
      content = FolderTabs.get_selected_content(state.tabs_state)

      # Build status bar (top of frame content)
      status_style = Style.new(fg: :bright_black)
      status_bar = text(String.pad_trailing(status_text, inner_width), status_style)

      # Build separator bar below status
      separator_style = Style.new(fg: :bright_black)
      separator = text(String.duplicate("─", inner_width), separator_style)

      # Calculate content height (inner - status(1) - separator(1) - input(1) - mode_bar(1) if present)
      input_height = if input_view, do: 1, else: 0
      mode_bar_height = if mode_bar_view, do: 1, else: 0
      content_height = max(inner_height - 2 - input_height - mode_bar_height, 1)

      # Build content area - conversation view (fills remaining space)
      content_view = if content, do: content, else: empty()
      content_box = box([content_view], width: inner_width, height: content_height)

      # Layout inside frame: status_bar | separator | conversation | input | mode_bar
      frame_elements = [status_bar, separator, content_box]
      frame_elements = if input_view, do: frame_elements ++ [input_view], else: frame_elements

      frame_elements =
        if mode_bar_view, do: frame_elements ++ [mode_bar_view], else: frame_elements

      frame_content = stack(:vertical, frame_elements)

      # Frame around content (not including tab bar)
      content_frame =
        Frame.render(
          content: frame_content,
          width: width,
          height: frame_height,
          style: border_style,
          charset: :rounded
        )

      # Stack: tab_bar above frame
      stack(:vertical, [tab_bar, content_frame])
    else
      # No tabs - just render empty frame
      Frame.render(
        content: empty(),
        width: width,
        height: height,
        style: border_style
      )
    end
  end

  defp render_gap(height) do
    # Single column of spaces to create gap between panes
    gap_line = String.duplicate(" \n", height) |> String.trim_trailing("\n")
    text(gap_line, nil)
  end

  # ============================================================================
  # Private: Utility Functions
  # ============================================================================

  defp truncate(text, max_len) when is_binary(text) do
    if String.length(text) > max_len do
      String.slice(text, 0, max_len - 1) <> "…"
    else
      text
    end
  end

  defp truncate(_, _), do: ""

  defp status_icon(:idle), do: "✓"
  defp status_icon(:processing), do: "⟳"
  defp status_icon(:error), do: "✗"
  defp status_icon(_), do: "○"
end
