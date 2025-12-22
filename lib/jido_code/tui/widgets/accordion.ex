defmodule JidoCode.TUI.Widgets.Accordion do
  @moduledoc """
  Accordion widget for displaying collapsible sections.

  A reusable accordion component that displays multiple collapsible sections
  with expand/collapse icons, badges, and nested content. Designed for
  organizing hierarchical information in the TUI sidebar.

  ## Usage

      Accordion.new(
        sections: [
          %{id: :files, title: "Files", content: [], badge: "12"},
          %{id: :tools, title: "Tools", content: [], badge: "5"}
        ],
        active_ids: [:files]
      )

  ## Features

  - Expand/collapse sections with visual indicators
  - Badge support for counts and status
  - Customizable icons and styling
  - Clean API for section management
  - Minimal initial scope (infrastructure only)

  ## Visual Layout

      ▼ Files (12)        ← Expanded section with badge
        [content...]      ← Indented content (2 spaces)

      ▶ Tools (5)         ← Collapsed section with badge

      ▶ Context           ← Collapsed section, no badge

  """

  import TermUI.Component.Helpers
  alias TermUI.Renderer.Style

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc "Unique identifier for a section"
  @type section_id :: term()

  @typedoc "An accordion section with content"
  @type section :: %{
          id: section_id(),
          title: String.t(),
          content: [TermUI.View.t()],
          badge: String.t() | nil,
          icon_open: String.t(),
          icon_closed: String.t(),
          activity_icon: String.t() | nil,
          activity_style: Style.t() | nil
        }

  @typedoc "Style configuration for accordion components"
  @type accordion_style :: %{
          title_style: Style.t() | nil,
          badge_style: Style.t() | nil,
          content_style: Style.t() | nil,
          icon_style: Style.t() | nil
        }

  @typedoc "Accordion state"
  @type t :: %__MODULE__{
          sections: [section()],
          active_ids: MapSet.t(section_id()),
          style: accordion_style(),
          indent: pos_integer()
        }

  defstruct sections: [],
            active_ids: MapSet.new(),
            style: %{
              title_style: nil,
              badge_style: nil,
              content_style: nil,
              icon_style: nil
            },
            indent: 2

  # ============================================================================
  # Constructor & Initialization
  # ============================================================================

  @doc """
  Creates a new Accordion with the given options.

  ## Options

    * `:sections` - List of section maps (default: [])
    * `:active_ids` - List of initially expanded section IDs (default: [])
    * `:style` - Style configuration map (default: nil for all styles)
    * `:indent` - Number of spaces to indent content (default: 2)

  ## Examples

      iex> Accordion.new(sections: [%{id: :files, title: "Files", content: []}])
      %Accordion{sections: [...], active_ids: #MapSet<[]>}

      iex> Accordion.new(sections: [...], active_ids: [:files])
      %Accordion{active_ids: #MapSet<[:files]>}

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    sections = Keyword.get(opts, :sections, [])
    active_ids = Keyword.get(opts, :active_ids, [])
    style = Keyword.get(opts, :style, %{})
    indent = Keyword.get(opts, :indent, 2)

    # Normalize sections to ensure all required fields exist
    normalized_sections = Enum.map(sections, &normalize_section/1)

    %__MODULE__{
      sections: normalized_sections,
      active_ids: MapSet.new(active_ids),
      style: Map.merge(default_style(), style),
      indent: indent
    }
  end

  @doc """
  Normalizes a section map to ensure all required fields exist with defaults.

  ## Examples

      iex> Accordion.normalize_section(%{id: :files, title: "Files"})
      %{
        id: :files,
        title: "Files",
        content: [],
        badge: nil,
        icon_open: "▼",
        icon_closed: "▶"
      }

  """
  @spec normalize_section(map()) :: section()
  def normalize_section(section) do
    %{
      id: Map.fetch!(section, :id),
      title: Map.get(section, :title, ""),
      content: Map.get(section, :content, []),
      badge: Map.get(section, :badge),
      icon_open: Map.get(section, :icon_open, "▼"),
      icon_closed: Map.get(section, :icon_closed, "▶")
    }
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  @doc """
  Renders the accordion to a TermUI view tree.

  ## Parameters

    * `accordion` - The accordion state
    * `width` - Available width for rendering (optional, defaults to 20)

  ## Returns

  A TermUI view tree (typically a vertical stack of elements).

  """
  @spec render(t(), pos_integer()) :: TermUI.View.t()
  def render(%__MODULE__{} = accordion, width \\ 20) do
    if Enum.empty?(accordion.sections) do
      # Empty state
      text("(no sections)", Style.new(fg: :bright_black))
    else
      # Render all sections
      section_views =
        Enum.map(accordion.sections, fn section ->
          render_section(accordion, section, width)
        end)

      stack(:vertical, List.flatten(section_views))
    end
  end

  @doc false
  @spec render_section(t(), section(), pos_integer()) :: [TermUI.View.t()]
  defp render_section(accordion, section, width) do
    is_expanded = MapSet.member?(accordion.active_ids, section.id)
    icon = if is_expanded, do: section.icon_open, else: section.icon_closed

    # Build title line
    title_line = build_title_line(accordion, section, icon, width)

    if is_expanded do
      # Render title + content
      content_views = render_content(accordion, section.content)
      [title_line | content_views]
    else
      # Render title only
      [title_line]
    end
  end

  @doc false
  @spec build_title_line(t(), section(), String.t(), pos_integer()) :: TermUI.View.t()
  defp build_title_line(accordion, section, icon, width) do
    _icon_style = accordion.style.icon_style || Style.new(fg: :cyan)
    title_style = accordion.style.title_style || Style.new(fg: :white)
    badge_style = accordion.style.badge_style || Style.new(fg: :yellow)

    # Extract activity icon info
    activity_icon = Map.get(section, :activity_icon)
    activity_style = Map.get(section, :activity_style) || title_style

    # Calculate activity icon width (icon + space if present)
    activity_width = if activity_icon, do: String.length(activity_icon) + 1, else: 0

    # Format: "▶ [activity] Title (badge)"
    if section.badge do
      badge_text = " (#{section.badge})"
      # Calculate max title length to fit width
      max_title_len = width - String.length(icon) - String.length(badge_text) - activity_width - 2

      truncated_title =
        if String.length(section.title) > max_title_len do
          String.slice(section.title, 0, max(max_title_len - 3, 0)) <> "..."
        else
          section.title
        end

      if activity_icon do
        stack(:horizontal, [
          text("#{icon} ", title_style),
          text("#{activity_icon} ", activity_style),
          text(truncated_title, title_style),
          text(badge_text, badge_style)
        ])
      else
        formatted_title = "#{icon} #{truncated_title}"

        stack(:horizontal, [
          text(formatted_title, title_style),
          text(badge_text, badge_style)
        ])
      end
    else
      # No badge, truncate to width
      title_text = "#{icon} #{section.title}"
      max_len = width - activity_width - 1

      truncated =
        if String.length(title_text) > max_len do
          String.slice(title_text, 0, max(max_len - 3, 0)) <> "..."
        else
          title_text
        end

      if activity_icon do
        stack(:horizontal, [
          text("#{icon} ", title_style),
          text("#{activity_icon} ", activity_style),
          text(String.trim_leading(truncated, "#{icon} "), title_style)
        ])
      else
        text(truncated, title_style)
      end
    end
  end

  @doc false
  @spec render_content(t(), [TermUI.View.t()]) :: [TermUI.View.t()]
  defp render_content(accordion, content) do
    indent_str = String.duplicate(" ", accordion.indent)
    content_style = accordion.style.content_style || Style.new(fg: :white)

    Enum.map(content, fn item ->
      # Indent each content item
      stack(:horizontal, [
        text(indent_str, content_style),
        item
      ])
    end)
  end

  # ============================================================================
  # Expansion API
  # ============================================================================

  @doc """
  Expands a section by its ID.

  ## Examples

      iex> accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      iex> expanded = Accordion.expand(accordion, :files)
      iex> Accordion.expanded?(expanded, :files)
      true

  """
  @spec expand(t(), section_id()) :: t()
  def expand(%__MODULE__{} = accordion, section_id) do
    %{accordion | active_ids: MapSet.put(accordion.active_ids, section_id)}
  end

  @doc """
  Collapses a section by its ID.

  ## Examples

      iex> accordion = Accordion.new(active_ids: [:files])
      iex> collapsed = Accordion.collapse(accordion, :files)
      iex> Accordion.expanded?(collapsed, :files)
      false

  """
  @spec collapse(t(), section_id()) :: t()
  def collapse(%__MODULE__{} = accordion, section_id) do
    %{accordion | active_ids: MapSet.delete(accordion.active_ids, section_id)}
  end

  @doc """
  Toggles a section's expansion state.

  ## Examples

      iex> accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      iex> toggled = Accordion.toggle(accordion, :files)
      iex> Accordion.expanded?(toggled, :files)
      true
      iex> toggled2 = Accordion.toggle(toggled, :files)
      iex> Accordion.expanded?(toggled2, :files)
      false

  """
  @spec toggle(t(), section_id()) :: t()
  def toggle(%__MODULE__{} = accordion, section_id) do
    if expanded?(accordion, section_id) do
      collapse(accordion, section_id)
    else
      expand(accordion, section_id)
    end
  end

  @doc """
  Expands all sections.

  ## Examples

      iex> accordion = Accordion.new(sections: [
      ...>   %{id: :files, title: "Files"},
      ...>   %{id: :tools, title: "Tools"}
      ...> ])
      iex> expanded = Accordion.expand_all(accordion)
      iex> Accordion.expanded?(expanded, :files) and Accordion.expanded?(expanded, :tools)
      true

  """
  @spec expand_all(t()) :: t()
  def expand_all(%__MODULE__{} = accordion) do
    all_ids = Enum.map(accordion.sections, & &1.id)
    %{accordion | active_ids: MapSet.new(all_ids)}
  end

  @doc """
  Collapses all sections.

  ## Examples

      iex> accordion = Accordion.new(active_ids: [:files, :tools])
      iex> collapsed = Accordion.collapse_all(accordion)
      iex> Accordion.expanded?(collapsed, :files) or Accordion.expanded?(collapsed, :tools)
      false

  """
  @spec collapse_all(t()) :: t()
  def collapse_all(%__MODULE__{} = accordion) do
    %{accordion | active_ids: MapSet.new()}
  end

  # ============================================================================
  # Section Management
  # ============================================================================

  @doc """
  Adds a section to the accordion.

  ## Examples

      iex> accordion = Accordion.new()
      iex> section = %{id: :files, title: "Files", content: []}
      iex> updated = Accordion.add_section(accordion, section)
      iex> Accordion.section_count(updated)
      1

  """
  @spec add_section(t(), map()) :: t()
  def add_section(%__MODULE__{} = accordion, section) do
    normalized = normalize_section(section)
    %{accordion | sections: accordion.sections ++ [normalized]}
  end

  @doc """
  Removes a section by its ID.

  ## Examples

      iex> accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      iex> updated = Accordion.remove_section(accordion, :files)
      iex> Accordion.section_count(updated)
      0

  """
  @spec remove_section(t(), section_id()) :: t()
  def remove_section(%__MODULE__{} = accordion, section_id) do
    updated_sections = Enum.reject(accordion.sections, &(&1.id == section_id))
    updated_active = MapSet.delete(accordion.active_ids, section_id)

    %{accordion | sections: updated_sections, active_ids: updated_active}
  end

  @doc """
  Updates a section by its ID.

  ## Examples

      iex> accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      iex> updated = Accordion.update_section(accordion, :files, %{title: "My Files"})
      iex> section = Accordion.get_section(updated, :files)
      iex> section.title
      "My Files"

  """
  @spec update_section(t(), section_id(), map()) :: t()
  def update_section(%__MODULE__{} = accordion, section_id, updates) do
    updated_sections =
      Enum.map(accordion.sections, fn section ->
        if section.id == section_id do
          Map.merge(section, updates)
        else
          section
        end
      end)

    %{accordion | sections: updated_sections}
  end

  # ============================================================================
  # Accessor Functions
  # ============================================================================

  @doc """
  Checks if a section is expanded.

  ## Examples

      iex> accordion = Accordion.new(active_ids: [:files])
      iex> Accordion.expanded?(accordion, :files)
      true
      iex> Accordion.expanded?(accordion, :tools)
      false

  """
  @spec expanded?(t(), section_id()) :: boolean()
  def expanded?(%__MODULE__{} = accordion, section_id) do
    MapSet.member?(accordion.active_ids, section_id)
  end

  @doc """
  Gets a section by its ID.

  ## Examples

      iex> accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      iex> section = Accordion.get_section(accordion, :files)
      iex> section.title
      "Files"

  """
  @spec get_section(t(), section_id()) :: section() | nil
  def get_section(%__MODULE__{} = accordion, section_id) do
    Enum.find(accordion.sections, &(&1.id == section_id))
  end

  @doc """
  Returns the number of sections in the accordion.

  ## Examples

      iex> accordion = Accordion.new(sections: [%{id: :files, title: "Files"}])
      iex> Accordion.section_count(accordion)
      1

  """
  @spec section_count(t()) :: non_neg_integer()
  def section_count(%__MODULE__{} = accordion) do
    length(accordion.sections)
  end

  @doc """
  Returns the number of expanded sections.

  ## Examples

      iex> accordion = Accordion.new(
      ...>   sections: [%{id: :files, title: "Files"}, %{id: :tools, title: "Tools"}],
      ...>   active_ids: [:files]
      ...> )
      iex> Accordion.expanded_count(accordion)
      1

  """
  @spec expanded_count(t()) :: non_neg_integer()
  def expanded_count(%__MODULE__{} = accordion) do
    MapSet.size(accordion.active_ids)
  end

  @doc """
  Returns all section IDs.

  ## Examples

      iex> accordion = Accordion.new(sections: [
      ...>   %{id: :files, title: "Files"},
      ...>   %{id: :tools, title: "Tools"}
      ...> ])
      iex> Accordion.section_ids(accordion)
      [:files, :tools]

  """
  @spec section_ids(t()) :: [section_id()]
  def section_ids(%__MODULE__{} = accordion) do
    Enum.map(accordion.sections, & &1.id)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec default_style() :: accordion_style()
  defp default_style do
    %{
      title_style: nil,
      badge_style: nil,
      content_style: nil,
      icon_style: nil
    }
  end
end
