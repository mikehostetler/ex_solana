defmodule JidoCode.TUI.Widgets.Frame do
  @moduledoc """
  A frame widget that draws a border around content.

  Unlike `box()` which is just a size constraint, Frame actually renders
  visible border characters around the content area.

  ## Usage

      Frame.render(
        content: my_widget,
        width: 40,
        height: 10,
        title: "My Section"
      )

  ## Options

  - `:content` - The content to render inside the frame (render node)
  - `:width` - Total frame width including borders
  - `:height` - Total frame height including borders
  - `:title` - Optional title to display in top border
  - `:style` - Style for border characters (default: bright_black)
  - `:title_style` - Style for title text (default: same as style)
  - `:charset` - Border character set: :single, :double, :rounded (default: :single)

  ## Visual Layout

      ┌─ Title ─────────────┐
      │                     │
      │   Content Area      │
      │                     │
      └─────────────────────┘

  """

  import TermUI.Component.Helpers

  alias TermUI.Renderer.Style

  @type charset :: :single | :double | :rounded

  @charsets %{
    single: %{
      tl: "┌",
      tr: "┐",
      bl: "└",
      br: "┘",
      h: "─",
      v: "│",
      t_down: "┬",
      t_up: "┴",
      t_right: "├",
      t_left: "┤",
      cross: "┼"
    },
    double: %{
      tl: "╔",
      tr: "╗",
      bl: "╚",
      br: "╝",
      h: "═",
      v: "║",
      t_down: "╦",
      t_up: "╩",
      t_right: "╠",
      t_left: "╣",
      cross: "╬"
    },
    rounded: %{
      tl: "╭",
      tr: "╮",
      bl: "╰",
      br: "╯",
      h: "─",
      v: "│",
      t_down: "┬",
      t_up: "┴",
      t_right: "├",
      t_left: "┤",
      cross: "┼"
    }
  }

  @doc """
  Renders a frame with the given options.

  Returns a TermUI render node.
  """
  @spec render(keyword()) :: TermUI.View.t()
  def render(opts) do
    content = Keyword.get(opts, :content, empty())
    width = Keyword.get(opts, :width, 40)
    height = Keyword.get(opts, :height, 10)
    title = Keyword.get(opts, :title)
    style = Keyword.get(opts, :style, Style.new(fg: :bright_black))
    title_style = Keyword.get(opts, :title_style, style)
    charset_name = Keyword.get(opts, :charset, :single)

    chars = Map.get(@charsets, charset_name, @charsets.single)

    # Calculate inner dimensions (excluding borders)
    inner_width = max(width - 2, 1)
    inner_height = max(height - 2, 1)

    # Build the frame rows
    top_row = render_top_border(chars, inner_width, title, style, title_style)
    bottom_row = render_bottom_border(chars, inner_width, style)
    content_rows = render_content_rows(chars, content, inner_width, inner_height, style)

    stack(:vertical, [top_row | content_rows] ++ [bottom_row])
  end

  @doc """
  Renders a frame around the given content with automatic sizing.

  This version takes explicit inner dimensions and wraps the content.
  """
  @spec wrap(TermUI.View.t(), keyword()) :: TermUI.View.t()
  def wrap(content, opts) do
    render(Keyword.put(opts, :content, content))
  end

  # Render top border with optional title
  defp render_top_border(chars, inner_width, nil, style, _title_style) do
    line = chars.tl <> String.duplicate(chars.h, inner_width) <> chars.tr
    text(line, style)
  end

  defp render_top_border(chars, inner_width, title, style, title_style) do
    title_text = " #{title} "
    title_len = String.length(title_text)

    if title_len >= inner_width do
      # Title too long, just show border
      render_top_border(chars, inner_width, nil, style, title_style)
    else
      # Build: ┌─ Title ───────┐
      left_segment = chars.h
      remaining = inner_width - title_len - 1
      right_segment = String.duplicate(chars.h, remaining)

      # Compose with mixed styles
      stack(:horizontal, [
        text(chars.tl <> left_segment, style),
        text(title_text, title_style),
        text(right_segment <> chars.tr, style)
      ])
    end
  end

  # Render bottom border
  defp render_bottom_border(chars, inner_width, style) do
    line = chars.bl <> String.duplicate(chars.h, inner_width) <> chars.br
    text(line, style)
  end

  # Render content rows with side borders
  defp render_content_rows(chars, content, inner_width, inner_height, style) do
    # Create a box for the content with inner dimensions
    content_box = box([content], width: inner_width, height: inner_height)

    # For each row, we need to add vertical borders
    # Since we can't easily iterate over rendered lines, we create a
    # horizontal stack for each row placeholder

    # The trick: we render the content in a box, then wrap the whole thing
    # with vertical borders using a horizontal stack
    # This works because the box constrains the content to inner_height lines

    [
      stack(:horizontal, [
        render_vertical_border_column(chars, inner_height, style),
        content_box,
        render_vertical_border_column(chars, inner_height, style)
      ])
    ]
  end

  # Render a column of vertical border characters
  # Uses a single text node with newlines instead of individual nodes per line
  # to avoid performance issues on large terminals
  defp render_vertical_border_column(chars, height, style) do
    # Create a single multi-line string with the vertical border character
    border_lines = List.duplicate(chars.v, height) |> Enum.join("\n")
    text(border_lines, style)
  end
end
