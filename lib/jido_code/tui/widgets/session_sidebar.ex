defmodule JidoCode.TUI.Widgets.SessionSidebar do
  @moduledoc """
  Session sidebar widget displaying all sessions in accordion format.

  Shows session list with:
  - Active session indicator (→ prefix)
  - Session badges (message count, status)
  - Collapsible session details (Info, Files, Tools - minimal/empty)

  ## Usage

      SessionSidebar.new(
        sessions: sessions,
        order: session_ids,
        active_id: active_session_id,
        expanded: MapSet.new([session_id])
      )
      |> SessionSidebar.render(20)

  ## Features

  - Accordion-based session display
  - Active session indicator (→)
  - Badge with message count and status icon
  - Session details sections (Info, Files, Tools) with placeholders
  - Name truncation (15 chars) for consistency with tabs
  - Width-aware rendering

  ## Visual Layout

      SESSIONS

      ▼ → My Project (msgs: 12) ✓   ← Active, expanded
          Info
            Created: 2h ago
            Path: ~/projects/myproject
          Files
            (empty)
          Tools
            (empty)

      ▶ Backend API (msgs: 5) ⟳     ← Collapsed, processing

  """

  import TermUI.Component.Helpers
  alias JidoCode.TUI.Widgets.Accordion
  alias JidoCode.Session
  alias JidoCode.Session.State, as: SessionState
  alias TermUI.Renderer.Style

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc "Session sidebar state"
  @type t :: %__MODULE__{
          sessions: [Session.t()],
          order: [String.t()],
          active_id: String.t() | nil,
          expanded: MapSet.t(String.t()),
          width: pos_integer(),
          # Activity tracking (Phase 4.7.3)
          streaming_sessions: MapSet.t(String.t()),
          unread_counts: %{String.t() => non_neg_integer()},
          active_tools: %{String.t() => non_neg_integer()},
          # Per-session accordion state (Phase 4.7.4)
          session_accordions: %{String.t() => Accordion.t()}
        }

  defstruct sessions: [],
            order: [],
            active_id: nil,
            expanded: MapSet.new(),
            width: 20,
            # Activity tracking (Phase 4.7.3)
            streaming_sessions: MapSet.new(),
            unread_counts: %{},
            active_tools: %{},
            # Per-session accordion state (Phase 4.7.4)
            session_accordions: %{}

  # Status icon mapping (from Task 4.3.3)
  @status_icons %{
    idle: "✓",
    processing: "⟳",
    error: "✗",
    unconfigured: "○"
  }

  # ============================================================================
  # Constructor
  # ============================================================================

  @doc """
  Creates a new SessionSidebar with the given options.

  ## Options

    * `:sessions` - List of Session structs (default: [])
    * `:order` - List of session IDs in display order (default: [])
    * `:active_id` - ID of the active session (default: nil)
    * `:expanded` - MapSet of expanded session IDs (default: empty)
    * `:width` - Sidebar width in characters (default: 20)
    * `:streaming_sessions` - MapSet of session IDs currently streaming (default: empty)
    * `:unread_counts` - Map of session_id => unread count (default: %{})
    * `:active_tools` - Map of session_id => active tool count (default: %{})
    * `:session_accordions` - Map of session_id => Accordion state (default: %{})

  ## Examples

      iex> SessionSidebar.new(sessions: [session], active_id: session.id)
      %SessionSidebar{sessions: [...], active_id: "session_id", ...}

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      sessions: Keyword.get(opts, :sessions, []),
      order: Keyword.get(opts, :order, []),
      active_id: Keyword.get(opts, :active_id),
      expanded: Keyword.get(opts, :expanded, MapSet.new()),
      width: Keyword.get(opts, :width, 20),
      # Activity tracking (Phase 4.7.3)
      streaming_sessions: Keyword.get(opts, :streaming_sessions, MapSet.new()),
      unread_counts: Keyword.get(opts, :unread_counts, %{}),
      active_tools: Keyword.get(opts, :active_tools, %{}),
      # Per-session accordion state (Phase 4.7.4)
      session_accordions: Keyword.get(opts, :session_accordions, %{})
    }
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the session sidebar to a TermUI view tree.

  ## Parameters

    * `sidebar` - The SessionSidebar state
    * `width` - Available width for rendering (optional, uses sidebar.width if not specified)

  ## Returns

  A TermUI view tree (vertical stack with header and accordion).

  """
  @spec render(t(), pos_integer() | nil) :: TermUI.View.t()
  def render(%__MODULE__{} = sidebar, width \\ nil) do
    render_width = width || sidebar.width

    # Build header
    header = render_header(render_width)

    # Build header separator
    separator = render_header_separator(render_width)

    # Build accordion from sessions
    accordion = build_accordion(sidebar)

    # Render accordion
    accordion_view = Accordion.render(accordion, render_width)

    # Stack header, separator, and accordion
    stack(:vertical, [header, separator, accordion_view])
  end

  @doc false
  @spec render_header(pos_integer()) :: TermUI.View.t()
  defp render_header(width) do
    header_style = Style.new(fg: :cyan, attrs: [:bold])
    header_text = "SESSIONS"

    # Pad header to width
    padded = String.pad_trailing(header_text, width)

    text(padded, header_style)
  end

  @doc false
  @spec render_header_separator(pos_integer()) :: TermUI.View.t()
  defp render_header_separator(width) do
    separator_style = Style.new(fg: :bright_black)
    separator_line = String.duplicate("─", width)
    text(separator_line, separator_style)
  end

  # ============================================================================
  # Accordion Building
  # ============================================================================

  @doc false
  @spec build_accordion(t()) :: Accordion.t()
  defp build_accordion(sidebar) do
    # Build sections from sessions in display order
    sections =
      Enum.map(sidebar.order, fn session_id ->
        session = Enum.find(sidebar.sessions, &(&1.id == session_id))

        if session do
          build_section(sidebar, session)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Create accordion with expanded state
    Accordion.new(
      sections: sections,
      active_ids: MapSet.to_list(sidebar.expanded),
      indent: 2
    )
  end

  @doc false
  @spec build_section(t(), Session.t()) :: map()
  defp build_section(sidebar, session) do
    # Build title with active indicator
    title = build_title(sidebar, session)

    # Build badge (message count + status)
    badge = build_badge(session.id)

    # Build content using per-session accordion if available
    content = build_session_details(sidebar, session)

    %{
      id: session.id,
      title: title,
      badge: badge,
      content: content,
      icon_open: "▼",
      icon_closed: "▶"
    }
  end

  # ============================================================================
  # Title Formatting
  # ============================================================================

  @doc """
  Builds the session title with active indicator and activity badges.

  Active session gets "→ " prefix, others have no prefix.
  Activity indicators show streaming, unread count, and active tool count.
  Session name is truncated to fit available space.

  ## Activity Badges

  - `[...]` - Session is currently streaming a response
  - `[N]` - N unread messages
  - `⚙N` - N tools currently executing

  ## Examples

      iex> build_title(sidebar, %{id: "123", name: "My Project"})
      "→ My Project"

      iex> build_title(sidebar_with_unread, %{id: "456", name: "Backend"})
      "[3] Backend"

      iex> build_title(sidebar_streaming, %{id: "789", name: "Frontend"})
      "[...] Frontend"

  """
  @spec build_title(t(), Session.t()) :: String.t()
  def build_title(sidebar, session) do
    # Active indicator
    prefix = if session.id == sidebar.active_id, do: "→ ", else: ""

    # Activity indicators (Phase 4.7.3)
    streaming_indicator =
      if MapSet.member?(sidebar.streaming_sessions, session.id), do: "[...] ", else: ""

    unread_badge =
      case Map.get(sidebar.unread_counts, session.id, 0) do
        0 -> ""
        count -> "[#{count}] "
      end

    tools_badge =
      case Map.get(sidebar.active_tools, session.id, 0) do
        0 -> ""
        count -> "⚙#{count} "
      end

    # Truncate session name to 15 chars (matching tab truncation)
    truncated_name = truncate(session.name, 15)

    # Combined format: "→ [...] [3] ⚙2 Session Name"
    "#{prefix}#{streaming_indicator}#{unread_badge}#{tools_badge}#{truncated_name}"
  end

  @doc false
  @spec truncate(String.t(), pos_integer()) :: String.t()
  defp truncate(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 1) <> "…"
    else
      text
    end
  end

  # ============================================================================
  # Badge Calculation
  # ============================================================================

  @doc """
  Builds the session badge showing message count and status icon.

  Format: "(msgs: N) [status_icon]"

  ## Status Icons

    * `✓` - :idle (agent ready)
    * `⟳` - :processing (agent busy)
    * `✗` - :error (agent error)
    * `○` - :unconfigured (no agent)

  ## Examples

      iex> build_badge("session_123")
      "(msgs: 5) ✓"

  """
  @spec build_badge(String.t()) :: String.t()
  def build_badge(session_id) do
    # Get message count via pagination metadata (efficient)
    message_count = get_message_count(session_id)

    # Get status icon
    status = get_session_status(session_id)
    status_icon = Map.get(@status_icons, status, "○")

    "(msgs: #{message_count}) #{status_icon}"
  end

  @doc false
  @spec get_message_count(String.t()) :: non_neg_integer()
  defp get_message_count(session_id) do
    # Use pagination metadata to get total count (efficient, no fetching all messages)
    case SessionState.get_messages(session_id, 0, 1) do
      {:ok, _messages, metadata} ->
        Map.get(metadata, :total, 0)

      {:error, _} ->
        0
    end
  end

  @doc false
  @spec get_session_status(String.t()) :: atom()
  defp get_session_status(session_id) do
    # Reuse status logic from TUI (Task 4.3.3)
    case Session.AgentAPI.get_status(session_id) do
      {:ok, %{ready: true}} -> :idle
      {:ok, %{ready: false}} -> :processing
      {:error, :agent_not_found} -> :unconfigured
      {:error, _} -> :error
    end
  end

  # ============================================================================
  # Session Details Rendering
  # ============================================================================

  @doc """
  Builds session details content using the per-session accordion.

  Uses the session's accordion from session_accordions if available,
  with dynamic content for each section:
  - **Info**: Created time and project path
  - **Files**: Empty placeholder (future: file list)
  - **Tools**: Empty placeholder (future: tool list)

  Falls back to static content if no accordion is available.
  """
  @spec build_session_details(t(), Session.t()) :: [TermUI.View.t()]
  def build_session_details(sidebar, session) do
    case Map.get(sidebar.session_accordions, session.id) do
      nil ->
        # Fallback to static content if no accordion
        build_static_session_details(session)

      accordion ->
        # Use the per-session accordion with dynamic content
        build_accordion_session_details(accordion, session)
    end
  end

  @doc false
  @spec build_static_session_details(Session.t()) :: [TermUI.View.t()]
  defp build_static_session_details(session) do
    info_style = Style.new(fg: :white)
    muted_style = Style.new(fg: :bright_black)
    label_style = Style.new(fg: :cyan)

    # Format created time
    created_text = format_created_time(session.created_at)

    # Format project path with ~ substitution
    path_text = format_project_path(session.project_path)

    [
      # Info section
      text("Info", label_style),
      text("  Created: #{created_text}", info_style),
      text("  Path: #{path_text}", info_style),
      # Files section (empty)
      text("Files", label_style),
      text("  (empty)", muted_style),
      # Tools section (empty)
      text("Tools", label_style),
      text("  (empty)", muted_style)
    ]
  end

  @doc false
  @spec build_accordion_session_details(Accordion.t(), Session.t()) :: [TermUI.View.t()]
  defp build_accordion_session_details(accordion, session) do
    info_style = Style.new(fg: :white)
    muted_style = Style.new(fg: :bright_black)

    # Build dynamic content for each section based on accordion state
    # Update the accordion's section content with session-specific data
    updated_accordion =
      accordion
      |> update_info_section(session, info_style)
      |> update_files_section(muted_style)
      |> update_tools_section(muted_style)

    # Render the accordion as a flat list of views
    # We return the rendered views as content for the parent accordion
    [Accordion.render(updated_accordion, 18)]
  end

  @doc false
  defp update_info_section(accordion, session, style) do
    created_text = format_created_time(session.created_at)
    path_text = format_project_path(session.project_path)

    content = [
      text("Created: #{created_text}", style),
      text("Path: #{path_text}", style)
    ]

    Accordion.update_section(accordion, :info, %{content: content})
  end

  @doc false
  defp update_files_section(accordion, style) do
    content = [text("(empty)", style)]
    Accordion.update_section(accordion, :files, %{content: content})
  end

  @doc false
  defp update_tools_section(accordion, style) do
    content = [text("(empty)", style)]
    Accordion.update_section(accordion, :tools, %{content: content})
  end

  @doc false
  @spec format_created_time(DateTime.t()) :: String.t()
  defp format_created_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  @doc false
  @spec format_project_path(String.t()) :: String.t()
  defp format_project_path(path) do
    # Replace home directory with ~
    home_dir = System.user_home!()

    if String.starts_with?(path, home_dir) do
      String.replace_prefix(path, home_dir, "~")
    else
      path
    end
  end

  # ============================================================================
  # Accessor Functions
  # ============================================================================

  @doc """
  Checks if a session is expanded.

  ## Examples

      iex> sidebar = SessionSidebar.new(expanded: MapSet.new(["session_123"]))
      iex> SessionSidebar.expanded?(sidebar, "session_123")
      true

  """
  @spec expanded?(t(), String.t()) :: boolean()
  def expanded?(sidebar, session_id) do
    MapSet.member?(sidebar.expanded, session_id)
  end

  @doc """
  Returns the number of sessions in the sidebar.

  ## Examples

      iex> sidebar = SessionSidebar.new(sessions: [session1, session2])
      iex> SessionSidebar.session_count(sidebar)
      2

  """
  @spec session_count(t()) :: non_neg_integer()
  def session_count(sidebar) do
    length(sidebar.sessions)
  end

  @doc """
  Checks if the sidebar has an active session.

  ## Examples

      iex> sidebar = SessionSidebar.new(active_id: "session_123")
      iex> SessionSidebar.has_active_session?(sidebar)
      true

  """
  @spec has_active_session?(t()) :: boolean()
  def has_active_session?(sidebar) do
    sidebar.active_id != nil
  end
end
