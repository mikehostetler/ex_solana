defmodule JidoCode.TUI.Widgets.FolderTabs do
  @moduledoc """
  Folder-style tabs widget that renders tabs as overlapping file folder tabs.

  Each tab is 2 rows tall with a centered label and a rounded curve (╮/╰) on
  the right edge, creating the appearance of stacked file folders.

  ## Usage

      FolderTabs.new(
        tabs: [
          %{id: :session1, label: "Session 1", closeable: true, content: session1_content},
          %{id: :session2, label: "Session 2", closeable: true, content: session2_content},
          %{id: :session3, label: "Session 3", content: session3_content}
        ],
        selected: :session1,
        on_change: fn tab_id -> IO.puts("Selected: \#{tab_id}") end,
        on_close: fn tab_id -> IO.puts("Closed: \#{tab_id}") end
      )

  ## Visual Appearance

      ╭───────────╮╭───────────╮╭─────────╮
      │ Tab 1   × ╰│ Tab 2   × ╰│ Tab 3   │
      ┌─────────────────────────────────────┐
      │ Status Bar                          │
      ├─────────────────────────────────────┤
      │                                     │
      │   Conversation View (padded)        │
      │                                     │
      ├─────────────────────────────────────┤
      │ Control Keys: Ctrl+W Close | ...    │
      └─────────────────────────────────────┘

  Each tab can have content that includes a status bar, conversation view, and control keys.
  Closeable tabs show an × button. The active tab is highlighted with a different color.
  """

  import TermUI.Component.Helpers

  alias TermUI.Renderer.Style

  # Box drawing characters for rounded tabs
  @top_left "╭"
  @top_right "╮"
  @bottom_left "╰"
  @bottom_right "╯"
  @vertical "│"
  @horizontal "─"

  # Close button character
  @close_button "×"

  @type tab :: %{
          id: term(),
          label: String.t(),
          closeable: boolean() | nil,
          disabled: boolean() | nil,
          content: TermUI.View.t() | nil,
          status: String.t() | nil,
          controls: String.t() | nil,
          activity_icon: String.t() | nil,
          activity_style: Style.t() | nil
        }

  @type t :: %{
          tabs: [tab()],
          selected: term(),
          focused: term(),
          on_change: (term() -> any()) | nil,
          on_close: (term() -> any()) | nil,
          min_tab_width: pos_integer(),
          active_style: Style.t() | nil,
          inactive_style: Style.t() | nil,
          disabled_style: Style.t() | nil,
          close_style: Style.t() | nil
        }

  @doc """
  Creates new FolderTabs props.

  ## Options

  - `:tabs` - List of tab definitions (required)
  - `:selected` - Initially selected tab ID
  - `:on_change` - Callback when selection changes
  - `:on_close` - Callback when a tab is closed
  - `:min_tab_width` - Minimum width for each tab (default: 12)
  - `:active_style` - Style for the selected tab
  - `:inactive_style` - Style for unselected tabs
  - `:disabled_style` - Style for disabled tabs
  - `:close_style` - Style for the close button (default: red)

  ## Tab Options

  - `:id` - Unique identifier for the tab (required)
  - `:label` - Display text in tab (required)
  - `:closeable` - Whether tab shows close button (default: false)
  - `:disabled` - Whether tab can be selected (default: false)
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    tabs = Keyword.fetch!(opts, :tabs)
    first_enabled = get_first_enabled_id(tabs)

    %{
      tabs: tabs,
      selected: Keyword.get(opts, :selected, first_enabled),
      focused: Keyword.get(opts, :selected, first_enabled),
      on_change: Keyword.get(opts, :on_change),
      on_close: Keyword.get(opts, :on_close),
      min_tab_width: Keyword.get(opts, :min_tab_width, 12),
      active_style: Keyword.get(opts, :active_style, default_active_style()),
      inactive_style: Keyword.get(opts, :inactive_style, default_inactive_style()),
      disabled_style: Keyword.get(opts, :disabled_style, default_disabled_style()),
      close_style: Keyword.get(opts, :close_style, default_close_style())
    }
  end

  @doc """
  Renders the folder tabs as a 2-row view element (tab bar only).
  """
  @spec render(t()) :: TermUI.View.t()
  def render(state) do
    tabs = state.tabs

    if tabs == [] do
      empty()
    else
      {top_row, middle_row, bottom_row} = build_tab_rows(tabs, state)

      stack(:vertical, [
        stack(:horizontal, top_row),
        stack(:horizontal, middle_row),
        stack(:horizontal, bottom_row)
      ])
    end
  end

  @doc """
  Renders the folder tabs with the selected tab's content panel.

  This renders:
  1. The tab bar (2 rows)
  2. The selected tab's content panel with:
     - Status bar at top
     - Padded conversation view in middle
     - Control keys at bottom

  ## Options

  - `:width` - Width of the content panel (default: 80)
  - `:height` - Height of the content panel (default: 20)
  - `:padding` - Horizontal padding for conversation view (default: 1)
  - `:status_style` - Style for status bar (default: inverted)
  - `:controls_style` - Style for control keys (default: dim)
  - `:border_style` - Style for content panel border (default: nil)
  """
  @spec render_with_content(t(), keyword()) :: TermUI.View.t()
  def render_with_content(state, opts \\ []) do
    tabs = state.tabs

    if tabs == [] do
      empty()
    else
      tab_bar = render(state)
      content_panel = render_content_panel(state, opts)

      stack(:vertical, [tab_bar, content_panel])
    end
  end

  @doc """
  Gets the content of the currently selected tab.
  """
  @spec get_selected_content(t()) :: TermUI.View.t() | nil
  def get_selected_content(state) do
    case Enum.find(state.tabs, &(&1.id == state.selected)) do
      nil -> nil
      tab -> Map.get(tab, :content)
    end
  end

  @doc """
  Gets the status text of the currently selected tab.
  """
  @spec get_selected_status(t()) :: String.t() | nil
  def get_selected_status(state) do
    case Enum.find(state.tabs, &(&1.id == state.selected)) do
      nil -> nil
      tab -> Map.get(tab, :status)
    end
  end

  @doc """
  Gets the controls text of the currently selected tab.
  """
  @spec get_selected_controls(t()) :: String.t() | nil
  def get_selected_controls(state) do
    case Enum.find(state.tabs, &(&1.id == state.selected)) do
      nil -> nil
      tab -> Map.get(tab, :controls)
    end
  end

  @doc """
  Updates the content of a tab by ID.
  """
  @spec update_tab_content(t(), term(), TermUI.View.t()) :: t()
  def update_tab_content(state, tab_id, content) do
    update_tab_field(state, tab_id, :content, content)
  end

  @doc """
  Updates the status text of a tab by ID.
  """
  @spec update_tab_status(t(), term(), String.t()) :: t()
  def update_tab_status(state, tab_id, status) do
    update_tab_field(state, tab_id, :status, status)
  end

  @doc """
  Updates the controls text of a tab by ID.
  """
  @spec update_tab_controls(t(), term(), String.t()) :: t()
  def update_tab_controls(state, tab_id, controls) do
    update_tab_field(state, tab_id, :controls, controls)
  end

  @doc """
  Updates the activity indicator of a tab by ID.

  Set both icon and style to nil to hide the activity indicator.
  """
  @spec update_tab_activity(t(), term(), String.t() | nil, Style.t() | nil) :: t()
  def update_tab_activity(state, tab_id, icon, style) do
    state
    |> update_tab_field(tab_id, :activity_icon, icon)
    |> update_tab_field(tab_id, :activity_style, style)
  end

  @doc """
  Selects a tab by ID.
  """
  @spec select(t(), term()) :: t()
  def select(state, tab_id) do
    if tab_enabled?(state.tabs, tab_id) do
      new_state = %{state | selected: tab_id, focused: tab_id}
      notify_change(new_state)
      new_state
    else
      state
    end
  end

  @doc """
  Gets the currently selected tab ID.
  """
  @spec get_selected(t()) :: term()
  def get_selected(state), do: state.selected

  @doc """
  Moves focus to the next tab.
  """
  @spec focus_next(t()) :: t()
  def focus_next(state), do: move_focus(state, 1)

  @doc """
  Moves focus to the previous tab.
  """
  @spec focus_prev(t()) :: t()
  def focus_prev(state), do: move_focus(state, -1)

  @doc """
  Selects the currently focused tab.
  """
  @spec select_focused(t()) :: t()
  def select_focused(state) do
    if tab_enabled?(state.tabs, state.focused) do
      new_state = %{state | selected: state.focused}
      notify_change(new_state)
      new_state
    else
      state
    end
  end

  @doc """
  Closes the currently selected tab if it's closeable.
  This is the handler for Ctrl+W.

  Returns `{:closed, new_state}` if tab was closed, `{:not_closeable, state}` otherwise.
  """
  @spec close_selected(t()) :: {:closed, t()} | {:not_closeable, t()}
  def close_selected(state) do
    if closeable?(state, state.selected) do
      {:closed, close_tab(state, state.selected)}
    else
      {:not_closeable, state}
    end
  end

  @doc """
  Handles keyboard events for the tab bar.

  Supported keys:
  - `Ctrl+W` - Close the currently selected tab (if closeable)
  - `Left` / `Shift+Tab` - Move focus to previous tab
  - `Right` / `Tab` - Move focus to next tab
  - `Enter` / `Space` - Select the focused tab
  - `Home` - Focus first tab
  - `End` - Focus last tab

  Returns `{:ok, new_state}` if event was handled, `:ignore` otherwise.

  ## Example

      case FolderTabs.handle_key(state, event) do
        {:ok, new_state} -> new_state
        :ignore -> state
      end
  """
  @spec handle_key(t(), TermUI.Event.Key.t()) :: {:ok, t()} | :ignore
  def handle_key(state, %{key: "w", modifiers: [:ctrl]}) do
    case close_selected(state) do
      {:closed, new_state} -> {:ok, new_state}
      {:not_closeable, _} -> :ignore
    end
  end

  def handle_key(state, %{key: "w", modifiers: modifiers}) do
    if :ctrl in modifiers do
      case close_selected(state) do
        {:closed, new_state} -> {:ok, new_state}
        {:not_closeable, _} -> :ignore
      end
    else
      :ignore
    end
  end

  def handle_key(state, %{key: :left}) do
    {:ok, focus_prev(state)}
  end

  def handle_key(state, %{key: :right}) do
    {:ok, focus_next(state)}
  end

  def handle_key(state, %{key: :tab, modifiers: [:shift]}) do
    {:ok, focus_prev(state)}
  end

  def handle_key(state, %{key: :tab, modifiers: modifiers}) do
    if :shift in modifiers do
      {:ok, focus_prev(state)}
    else
      {:ok, focus_next(state)}
    end
  end

  def handle_key(state, %{key: :tab}) do
    {:ok, focus_next(state)}
  end

  def handle_key(state, %{key: key}) when key in [:enter, " "] do
    {:ok, select_focused(state)}
  end

  def handle_key(state, %{key: :home}) do
    first_id = get_first_enabled_id(state.tabs)
    {:ok, %{state | focused: first_id}}
  end

  def handle_key(state, %{key: :end}) do
    last_id = get_last_enabled_id(state.tabs)
    {:ok, %{state | focused: last_id}}
  end

  def handle_key(_state, _event), do: :ignore

  @doc """
  Closes a tab by ID. Calls the on_close callback and removes the tab.
  Returns the updated state with the tab removed.
  """
  @spec close_tab(t(), term()) :: t()
  def close_tab(state, tab_id) do
    tab = Enum.find(state.tabs, &(&1.id == tab_id))

    # Only close if tab exists and is closeable
    if tab && Map.get(tab, :closeable, false) do
      # Notify via callback
      notify_close(state, tab_id)

      # Remove the tab
      new_tabs = Enum.reject(state.tabs, &(&1.id == tab_id))

      # If closed tab was selected, select next available
      new_selected =
        if state.selected == tab_id do
          get_first_enabled_id(new_tabs)
        else
          state.selected
        end

      # If closed tab was focused, focus next available
      new_focused =
        if state.focused == tab_id do
          get_first_enabled_id(new_tabs)
        else
          state.focused
        end

      %{state | tabs: new_tabs, selected: new_selected, focused: new_focused}
    else
      state
    end
  end

  @doc """
  Closes the currently focused tab if it's closeable.
  """
  @spec close_focused(t()) :: t()
  def close_focused(state) do
    close_tab(state, state.focused)
  end

  @doc """
  Adds a new tab.
  """
  @spec add_tab(t(), tab()) :: t()
  def add_tab(state, tab) do
    %{state | tabs: state.tabs ++ [tab]}
  end

  @doc """
  Returns the number of tabs.
  """
  @spec tab_count(t()) :: non_neg_integer()
  def tab_count(state), do: length(state.tabs)

  @doc """
  Checks if a tab is closeable.
  """
  @spec closeable?(t(), term()) :: boolean()
  def closeable?(state, tab_id) do
    case Enum.find(state.tabs, &(&1.id == tab_id)) do
      nil -> false
      tab -> Map.get(tab, :closeable, false)
    end
  end

  @doc """
  Handles a mouse click at position (x, y) and returns the action to take.

  Returns:
  - `{:close, tab_id}` - Click was on a close button
  - `{:select, tab_id}` - Click was on a tab (not close button)
  - `:none` - Click was outside any tab

  The y coordinate should be 0 or 1 (the two rows of the tab bar).

  ## Example

      case FolderTabs.handle_click(state, x, y) do
        {:close, tab_id} ->
          FolderTabs.close_tab(state, tab_id)
        {:select, tab_id} ->
          FolderTabs.select(state, tab_id)
        :none ->
          state
      end
  """
  @spec handle_click(t(), non_neg_integer(), non_neg_integer()) ::
          {:close, term()} | {:select, term()} | :none
  def handle_click(state, x, y) when y in [0, 1] do
    tab_positions = calculate_tab_positions(state)

    Enum.find_value(tab_positions, :none, fn {tab_id, tab_start, tab_end, close_start, close_end} ->
      cond do
        # Click on close button (only on bottom row, y == 1)
        y == 1 && close_start != nil && x >= close_start && x < close_end ->
          {:close, tab_id}

        # Click on tab body
        x >= tab_start && x < tab_end ->
          {:select, tab_id}

        true ->
          nil
      end
    end)
  end

  def handle_click(_state, _x, _y), do: :none

  @doc """
  Convenience function that handles a click and automatically updates state.

  Returns `{action, new_state}` where action is `:closed`, `:selected`, or `:none`.
  """
  @spec click(t(), non_neg_integer(), non_neg_integer()) ::
          {:closed, t()} | {:selected, t()} | {:none, t()}
  def click(state, x, y) do
    case handle_click(state, x, y) do
      {:close, tab_id} ->
        {:closed, close_tab(state, tab_id)}

      {:select, tab_id} ->
        {:selected, select(state, tab_id)}

      :none ->
        {:none, state}
    end
  end

  @doc """
  Calculates the pixel positions of each tab for hit testing.

  Returns a list of `{tab_id, tab_start, tab_end, close_start, close_end}` tuples.
  For non-closeable tabs, close_start and close_end are nil.
  """
  @spec calculate_tab_positions(t()) :: [
          {term(), non_neg_integer(), non_neg_integer(), non_neg_integer() | nil,
           non_neg_integer() | nil}
        ]
  def calculate_tab_positions(state) do
    {positions, _} =
      Enum.reduce(state.tabs, {[], 0}, fn tab, {acc, offset} ->
        label_width = String.length(tab.label)
        is_closeable = Map.get(tab, :closeable, false)
        activity_icon = Map.get(tab, :activity_icon)
        close_width = if is_closeable, do: 2, else: 0
        activity_width = if activity_icon, do: 2, else: 0
        tab_width = max(label_width + 4 + close_width + activity_width, state.min_tab_width)

        # Close button position (if closeable)
        # Close button is at: offset + 1 (border) + inner_width - 2 (before curve)
        # Inner width = tab_width - 2
        {close_start, close_end} =
          if is_closeable do
            # The × is positioned at inner_width - 2 from the left border
            inner_width = tab_width - 2
            close_pos = offset + 1 + inner_width - 2
            {close_pos, close_pos + 1}
          else
            {nil, nil}
          end

        position = {tab.id, offset, offset + tab_width, close_start, close_end}
        {acc ++ [position], offset + tab_width}
      end)

    positions
  end

  # Private functions

  defp build_tab_rows(tabs, state) do
    tab_count = length(tabs)

    {top_elements, middle_elements, bottom_elements} =
      tabs
      |> Enum.with_index()
      |> Enum.reduce({[], [], []}, fn {tab, index}, {top_acc, mid_acc, bottom_acc} ->
        is_selected = tab.id == state.selected
        is_last = index == tab_count - 1
        is_disabled = Map.get(tab, :disabled, false)
        is_closeable = Map.get(tab, :closeable, false)
        activity_icon = Map.get(tab, :activity_icon)
        activity_style = Map.get(tab, :activity_style)

        style = determine_style(is_selected, is_disabled, state)

        # Calculate tab width (label + padding + close button if closeable + activity icon if present)
        label_width = String.length(tab.label)
        close_width = if is_closeable, do: 2, else: 0
        # Activity icon takes 2 chars (icon + space)
        activity_width = if activity_icon, do: 2, else: 0
        tab_width = max(label_width + 4 + close_width + activity_width, state.min_tab_width)

        {top_part, middle_part, bottom_part} =
          render_single_tab(
            tab.label,
            tab_width,
            is_last,
            is_closeable,
            style,
            state.close_style,
            activity_icon,
            activity_style
          )

        # Add space between tabs (except after last)
        space = if is_last, do: [], else: [text(" ", nil)]

        {top_acc ++ [top_part] ++ space, mid_acc ++ [middle_part] ++ space, bottom_acc ++ [bottom_part] ++ space}
      end)

    {top_elements, middle_elements, bottom_elements}
  end

  defp render_single_tab(label, width, _is_last, is_closeable, style, close_style, activity_icon \\ nil, activity_style \\ nil) do
    # Simple rounded box style: ╭───────╮ on top, ╰───────╯ on bottom
    inner_width = width - 2
    top_line = @top_left <> String.duplicate(@horizontal, inner_width) <> @top_right
    bottom_line = @bottom_left <> String.duplicate(@horizontal, inner_width) <> @bottom_right

    # Build label with padding (accounting for activity icon space)
    has_activity = activity_icon != nil
    {label_part, _close_part} = build_label_with_close(label, inner_width, is_closeable, has_activity)

    # Top element: ╭───────╮
    top_element = text(top_line, style)

    # Bottom element: │ [icon] Label │ (with optional activity icon and close button)
    bottom_element =
      cond do
        # Has both activity icon and close button
        has_activity and is_closeable ->
          stack(:horizontal, [
            text(@vertical, style),
            text(activity_icon <> " ", activity_style || style),
            text(label_part, style),
            text(@close_button, close_style),
            text(" " <> @vertical, style)
          ])

        # Has activity icon only
        has_activity ->
          stack(:horizontal, [
            text(@vertical, style),
            text(activity_icon <> " ", activity_style || style),
            text(label_part <> @vertical, style)
          ])

        # Has close button only
        is_closeable ->
          stack(:horizontal, [
            text(@vertical <> label_part, style),
            text(@close_button, close_style),
            text(" " <> @vertical, style)
          ])

        # Neither
        true ->
          text(@vertical <> label_part <> @vertical, style)
      end

    # Return 3-row structure but we'll flatten in build_tab_rows
    {top_element, bottom_element, text(bottom_line, style)}
  end

  defp build_label_with_close(label, inner_width, is_closeable, has_activity \\ false) do
    # Activity icon takes 2 chars (icon + space), handled separately in render
    activity_width = if has_activity, do: 2, else: 0

    if is_closeable do
      # Reserve 2 chars for "× " at the end
      available_width = inner_width - 2 - activity_width
      padded_label = pad_label_left(label, available_width)
      {padded_label, @close_button}
    else
      available_width = inner_width - activity_width
      padded_label = center_label(label, available_width)
      {padded_label, ""}
    end
  end

  defp center_label(label, width) do
    label_len = String.length(label)

    if label_len >= width do
      String.slice(label, 0, width)
    else
      padding = width - label_len
      left_pad = div(padding, 2)
      right_pad = padding - left_pad
      String.duplicate(" ", left_pad) <> label <> String.duplicate(" ", right_pad)
    end
  end

  defp pad_label_left(label, width) do
    label_len = String.length(label)

    if label_len >= width do
      String.slice(label, 0, width)
    else
      padding = width - label_len
      " " <> label <> String.duplicate(" ", padding - 1)
    end
  end

  defp determine_style(is_selected, is_disabled, state) do
    cond do
      is_disabled -> state.disabled_style
      is_selected -> state.active_style
      true -> state.inactive_style
    end
  end

  defp get_first_enabled_id(tabs) do
    tabs
    |> Enum.find(fn tab -> not Map.get(tab, :disabled, false) end)
    |> case do
      nil -> nil
      tab -> tab.id
    end
  end

  defp get_last_enabled_id(tabs) do
    tabs
    |> Enum.reverse()
    |> Enum.find(fn tab -> not Map.get(tab, :disabled, false) end)
    |> case do
      nil -> nil
      tab -> tab.id
    end
  end

  defp tab_enabled?(tabs, tab_id) do
    case Enum.find(tabs, &(&1.id == tab_id)) do
      nil -> false
      tab -> not Map.get(tab, :disabled, false)
    end
  end

  defp move_focus(state, direction) do
    enabled_tabs = Enum.filter(state.tabs, fn tab -> not Map.get(tab, :disabled, false) end)
    ids = Enum.map(enabled_tabs, & &1.id)

    case Enum.find_index(ids, &(&1 == state.focused)) do
      nil ->
        state

      current_idx ->
        new_idx = rem(current_idx + direction + length(ids), length(ids))
        %{state | focused: Enum.at(ids, new_idx)}
    end
  end

  defp notify_change(state) do
    if state.on_change do
      state.on_change.(state.selected)
    end
  end

  defp notify_close(state, tab_id) do
    if state.on_close do
      state.on_close.(tab_id)
    end
  end

  defp default_active_style do
    Style.new(fg: :white, bg: :blue, attrs: [:bold])
  end

  defp default_inactive_style do
    Style.new(fg: :bright_black)
  end

  defp default_disabled_style do
    Style.new(fg: :bright_black, attrs: [:dim])
  end

  defp default_close_style do
    Style.new(fg: :red, attrs: [:bold])
  end

  defp update_tab_field(state, tab_id, field, value) do
    new_tabs =
      Enum.map(state.tabs, fn tab ->
        if tab.id == tab_id do
          Map.put(tab, field, value)
        else
          tab
        end
      end)

    %{state | tabs: new_tabs}
  end

  # Content panel rendering

  defp render_content_panel(state, opts) do
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 20)
    padding = Keyword.get(opts, :padding, 1)
    status_style = Keyword.get(opts, :status_style, default_status_style())
    controls_style = Keyword.get(opts, :controls_style, default_controls_style())
    border_style = Keyword.get(opts, :border_style)

    selected_tab = Enum.find(state.tabs, &(&1.id == state.selected))

    status_text = if selected_tab, do: Map.get(selected_tab, :status, ""), else: ""
    content = if selected_tab, do: Map.get(selected_tab, :content), else: nil
    controls_text = if selected_tab, do: Map.get(selected_tab, :controls, ""), else: ""

    # Build the panel components
    status_bar = render_status_bar(status_text, width, status_style)
    content_view = render_padded_content(content, width, height - 2, padding)
    controls_bar = render_controls_bar(controls_text, width, controls_style)

    panel_content =
      stack(:vertical, [
        status_bar,
        content_view,
        controls_bar
      ])

    # Optionally wrap in border
    if border_style do
      render_bordered_panel(panel_content, width, height, border_style)
    else
      panel_content
    end
  end

  defp render_status_bar(status_text, width, style) do
    # Pad status text to full width
    padded_text = String.pad_trailing(status_text || "", width)
    text(padded_text, style)
  end

  defp render_padded_content(nil, width, _height, padding) do
    # Empty content - just show padding
    padding_str = String.duplicate(" ", padding)
    inner_width = width - (padding * 2)
    empty_line = padding_str <> String.duplicate(" ", inner_width) <> padding_str
    text(empty_line)
  end

  defp render_padded_content(content, _width, _height, padding) do
    # Wrap content with horizontal padding
    padding_element = text(String.duplicate(" ", padding))

    stack(:horizontal, [
      padding_element,
      content,
      padding_element
    ])
  end

  defp render_controls_bar(controls_text, width, style) do
    # Pad controls text to full width
    padded_text = String.pad_trailing(controls_text || "", width)
    text(padded_text, style)
  end

  defp render_bordered_panel(content, width, _height, style) do
    # Box drawing characters for panel border
    top_border = "┌" <> String.duplicate("─", width - 2) <> "┐"
    bottom_border = "└" <> String.duplicate("─", width - 2) <> "┘"

    stack(:vertical, [
      text(top_border, style),
      stack(:horizontal, [
        text("│", style),
        content,
        text("│", style)
      ]),
      text(bottom_border, style)
    ])
  end

  defp default_status_style do
    Style.new(fg: :black, bg: :white)
  end

  defp default_controls_style do
    Style.new(fg: :bright_black, attrs: [:dim])
  end
end
