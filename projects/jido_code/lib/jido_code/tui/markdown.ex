defmodule JidoCode.TUI.Markdown do
  @moduledoc """
  Markdown processor for rendering styled text in the TUI.

  Converts markdown content to styled segments that can be rendered
  by TermUI components. Handles common markdown elements:

  - Headers (# H1, ## H2, etc.)
  - Bold (**text**)
  - Italic (*text*)
  - Inline code (`code`)
  - Code blocks (```language ... ```)
  - Lists (- item, * item, 1. item)
  - Blockquotes (> quote)
  - Links ([text](url))

  ## Usage

      iex> lines = Markdown.render("**bold** and *italic*", 80)
      iex> # Returns list of styled lines for rendering

  """

  alias TermUI.Renderer.Style

  # Type definitions
  @type styled_segment :: {String.t(), Style.t() | nil}
  @type styled_line :: [styled_segment]

  @typedoc "An interactive element that can receive focus and actions"
  @type interactive_element :: %{
          id: String.t(),
          type: :code_block,
          content: String.t(),
          language: String.t() | nil,
          start_line: non_neg_integer(),
          end_line: non_neg_integer()
        }

  @typedoc "Result of render_with_elements/2"
  @type render_result :: %{
          lines: [styled_line()],
          elements: [interactive_element()]
        }

  # Style definitions
  @header1_style Style.new(fg: :cyan, attrs: [:bold])
  @header2_style Style.new(fg: :cyan, attrs: [:bold])
  @header3_style Style.new(fg: :white, attrs: [:bold])
  @bold_style Style.new(attrs: [:bold])
  @italic_style Style.new(attrs: [:italic])
  @code_style Style.new(fg: :yellow)
  @code_block_style Style.new(fg: :yellow)
  @code_border_style Style.new(fg: :bright_black)
  @code_border_focused_style Style.new(fg: :cyan, attrs: [:bold])
  @blockquote_style Style.new(fg: :bright_black)
  @link_style Style.new(fg: :blue, attrs: [:underline])
  @list_bullet_style Style.new(fg: :cyan)

  # Syntax highlighting token styles (for code blocks)
  @token_styles %{
    # Keywords - magenta/purple
    keyword: Style.new(fg: :magenta, attrs: [:bold]),
    keyword_namespace: Style.new(fg: :magenta, attrs: [:bold]),
    keyword_pseudo: Style.new(fg: :magenta, attrs: [:bold]),
    keyword_reserved: Style.new(fg: :magenta, attrs: [:bold]),
    keyword_constant: Style.new(fg: :magenta, attrs: [:bold]),
    keyword_declaration: Style.new(fg: :magenta, attrs: [:bold]),
    keyword_type: Style.new(fg: :magenta, attrs: [:bold]),

    # Strings - green
    string: Style.new(fg: :green),
    string_char: Style.new(fg: :green),
    string_doc: Style.new(fg: :green),
    string_double: Style.new(fg: :green),
    string_single: Style.new(fg: :green),
    string_sigil: Style.new(fg: :green),
    string_regex: Style.new(fg: :green),
    string_interpol: Style.new(fg: :red),
    string_escape: Style.new(fg: :cyan),
    string_symbol: Style.new(fg: :cyan),

    # Comments - dim gray
    comment: Style.new(fg: :bright_black),
    comment_single: Style.new(fg: :bright_black),
    comment_multiline: Style.new(fg: :bright_black),
    comment_doc: Style.new(fg: :bright_black),

    # Atoms - cyan
    atom: Style.new(fg: :cyan),

    # Numbers - yellow
    number: Style.new(fg: :yellow),
    number_integer: Style.new(fg: :yellow),
    number_float: Style.new(fg: :yellow),
    number_bin: Style.new(fg: :yellow),
    number_oct: Style.new(fg: :yellow),
    number_hex: Style.new(fg: :yellow),

    # Operators - yellow
    operator: Style.new(fg: :yellow),
    operator_word: Style.new(fg: :magenta, attrs: [:bold]),

    # Names
    name: Style.new(fg: :white),
    name_function: Style.new(fg: :blue),
    name_class: Style.new(fg: :yellow, attrs: [:bold]),
    name_builtin: Style.new(fg: :cyan),
    name_builtin_pseudo: Style.new(fg: :cyan),
    name_attribute: Style.new(fg: :cyan),
    name_label: Style.new(fg: :cyan),
    name_constant: Style.new(fg: :yellow, attrs: [:bold]),
    name_exception: Style.new(fg: :red),
    name_tag: Style.new(fg: :blue),
    name_decorator: Style.new(fg: :cyan),
    name_namespace: Style.new(fg: :yellow, attrs: [:bold]),

    # Punctuation - white
    punctuation: Style.new(fg: :white),

    # Whitespace/text - no style
    whitespace: nil,
    text: nil
  }

  # Supported languages with their Makeup lexers
  @supported_lexers %{
    "elixir" => Makeup.Lexers.ElixirLexer,
    "ex" => Makeup.Lexers.ElixirLexer,
    "exs" => Makeup.Lexers.ElixirLexer,
    "iex" => Makeup.Lexers.ElixirLexer
  }

  @doc """
  Renders markdown content as a list of styled lines.

  Each line is a list of styled segments that can be combined
  into TermUI render nodes.

  ## Parameters

  - `content` - Markdown string to render
  - `max_width` - Maximum line width for wrapping

  ## Returns

  List of styled lines, where each line is a list of `{text, style}` tuples.
  """
  @spec render(String.t(), pos_integer()) :: [styled_line()]
  def render("", _max_width), do: [[{"", nil}]]
  def render(nil, _max_width), do: [[{"", nil}]]

  def render(content, max_width) when is_binary(content) and max_width > 0 do
    case MDEx.parse_document(content) do
      {:ok, document} ->
        document
        |> process_document()
        |> wrap_styled_lines(max_width)

      {:error, _reason} ->
        # Fallback to plain text on parse error
        content
        |> String.split("\n")
        |> Enum.map(fn line -> [{line, nil}] end)
        |> wrap_styled_lines(max_width)
    end
  end

  def render(content, _max_width) when is_binary(content) do
    render(content, 80)
  end

  @doc """
  Renders markdown content with interactive element tracking.

  Returns a map containing:
  - `:lines` - List of styled lines for rendering
  - `:elements` - List of interactive elements (code blocks) with their positions

  ## Parameters

  - `content` - Markdown string to render
  - `max_width` - Maximum line width for wrapping
  - `opts` - Options:
    - `:focused_element_id` - ID of the focused element (for visual highlighting)

  ## Returns

  A map with `:lines` and `:elements` keys.
  """
  @spec render_with_elements(String.t(), pos_integer(), keyword()) :: render_result()
  def render_with_elements(content, max_width, opts \\ [])

  def render_with_elements("", _max_width, _opts) do
    %{lines: [[{"", nil}]], elements: []}
  end

  def render_with_elements(nil, _max_width, _opts) do
    %{lines: [[{"", nil}]], elements: []}
  end

  def render_with_elements(content, max_width, opts) when is_binary(content) and max_width > 0 do
    focused_id = Keyword.get(opts, :focused_element_id)

    case MDEx.parse_document(content) do
      {:ok, document} ->
        # Process document and collect interactive elements
        {raw_lines, elements} = process_document_with_elements(document, focused_id)

        # Wrap lines (this may change line counts, so we need to adjust element positions)
        wrapped_lines = wrap_styled_lines(raw_lines, max_width)

        # For now, elements track pre-wrap positions. In a full implementation,
        # we'd need to track how wrapping affects line positions.
        # Since code blocks don't wrap (they have fixed-width content), this is okay.
        %{lines: wrapped_lines, elements: elements}

      {:error, _reason} ->
        # Fallback to plain text on parse error
        lines =
          content
          |> String.split("\n")
          |> Enum.map(fn line -> [{line, nil}] end)
          |> wrap_styled_lines(max_width)

        %{lines: lines, elements: []}
    end
  end

  def render_with_elements(content, _max_width, opts) when is_binary(content) do
    render_with_elements(content, 80, opts)
  end

  @doc """
  Converts a styled line to a TermUI render node.

  Joins multiple styled segments into a horizontal stack.
  """
  @spec render_line(styled_line()) :: TermUI.Component.RenderNode.t()
  def render_line([]), do: TermUI.Component.RenderNode.text("", nil)

  def render_line([{text, style}]) do
    TermUI.Component.RenderNode.text(text, style)
  end

  def render_line(segments) when is_list(segments) do
    nodes =
      Enum.map(segments, fn {text, style} ->
        TermUI.Component.RenderNode.text(text, style)
      end)

    TermUI.Component.RenderNode.stack(:horizontal, nodes)
  end

  # ============================================================================
  # Document Processing
  # ============================================================================

  defp process_document(%MDEx.Document{nodes: nodes}) do
    nodes
    |> Enum.flat_map(&process_node/1)
  end

  defp process_document(_), do: [[{"", nil}]]

  # Process document with interactive element tracking
  defp process_document_with_elements(%MDEx.Document{nodes: nodes}, focused_id) do
    {lines, elements, _line_idx} =
      Enum.reduce(nodes, {[], [], 0}, fn node, {acc_lines, acc_elements, line_idx} ->
        {node_lines, node_elements} = process_node_with_elements(node, line_idx, focused_id)
        new_line_idx = line_idx + length(node_lines)
        {acc_lines ++ node_lines, acc_elements ++ node_elements, new_line_idx}
      end)

    {lines, elements}
  end

  defp process_document_with_elements(_, _focused_id), do: {[[{"", nil}]], []}

  # Process node and return {lines, elements} tuple
  # Most nodes don't have interactive elements
  defp process_node_with_elements(%MDEx.CodeBlock{literal: code, info: info}, line_idx, focused_id) do
    lang = if info && info != "", do: String.downcase(String.trim(info)), else: nil

    # Generate deterministic ID for this code block
    element_id = generate_element_id(code, line_idx)
    is_focused = element_id == focused_id

    # Choose border style based on focus state
    border_style = if is_focused, do: @code_border_focused_style, else: @code_border_style

    # Build header with language label and optional focus hint
    header =
      if lang do
        focus_hint = if is_focused, do: " [c]", else: ""
        [[{"┌─ " <> lang <> focus_hint <> " ", @code_block_style}, {String.duplicate("─", 40 - String.length(focus_hint)), border_style}]]
      else
        focus_hint = if is_focused, do: " [c]", else: ""
        [[{"┌" <> focus_hint, @code_block_style}, {String.duplicate("─", 44 - String.length(focus_hint)), border_style}]]
      end

    # Render code with syntax highlighting if supported, otherwise plain
    code_lines = render_code_block(code, lang)

    footer = [[{"└", @code_block_style}, {String.duplicate("─", 44), border_style}], [{"", nil}]]

    lines = header ++ code_lines ++ footer

    # Create interactive element metadata
    element = %{
      id: element_id,
      type: :code_block,
      content: String.trim_trailing(code),
      language: lang,
      start_line: line_idx,
      end_line: line_idx + length(lines) - 1
    }

    {lines, [element]}
  end

  # For all other node types, delegate to regular process_node and return empty elements
  defp process_node_with_elements(node, _line_idx, _focused_id) do
    lines = process_node(node)
    {lines, []}
  end

  # Generate a deterministic ID for interactive elements based on content and position
  # This ensures the same code block gets the same ID across re-renders
  defp generate_element_id(content, line_idx) do
    :crypto.hash(:md5, "#{line_idx}:#{content}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  # Process different node types
  defp process_node(%MDEx.Heading{level: 1, nodes: children}) do
    content = extract_text(children)
    [[{"# " <> content, @header1_style}], [{"", nil}]]
  end

  defp process_node(%MDEx.Heading{level: 2, nodes: children}) do
    content = extract_text(children)
    [[{"## " <> content, @header2_style}], [{"", nil}]]
  end

  defp process_node(%MDEx.Heading{level: level, nodes: children}) when level >= 3 do
    prefix = String.duplicate("#", level) <> " "
    content = extract_text(children)
    [[{prefix <> content, @header3_style}], [{"", nil}]]
  end

  defp process_node(%MDEx.Paragraph{nodes: children}) do
    segments = process_inline_nodes(children)
    [segments, [{"", nil}]]
  end

  defp process_node(%MDEx.CodeBlock{literal: code, info: info}) do
    # Normalize language to lowercase
    lang = if info && info != "", do: String.downcase(String.trim(info)), else: nil

    # Build header with language label
    header =
      if lang do
        [[{"┌─ " <> lang <> " ", @code_block_style}, {String.duplicate("─", 40), @code_border_style}]]
      else
        [[{"┌", @code_block_style}, {String.duplicate("─", 44), @code_border_style}]]
      end

    # Render code with syntax highlighting if supported, otherwise plain
    code_lines = render_code_block(code, lang)

    footer = [[{"└", @code_block_style}, {String.duplicate("─", 44), @code_border_style}], [{"", nil}]]

    header ++ code_lines ++ footer
  end

  # Render code block with syntax highlighting for supported languages
  defp render_code_block(code, lang) do
    case Map.get(@supported_lexers, lang) do
      nil ->
        # No lexer available - plain styling
        plain_code_lines(code)

      lexer ->
        # Try syntax highlighting, fall back to plain on error
        try do
          highlighted_code_lines(code, lexer)
        rescue
          _ -> plain_code_lines(code)
        end
    end
  end

  # Plain code lines without syntax highlighting
  defp plain_code_lines(code) do
    code
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map(fn line -> [{"│ " <> line, @code_block_style}] end)
  end

  # Syntax highlighted code lines using Makeup lexer
  defp highlighted_code_lines(code, lexer) do
    tokens = lexer.lex(code |> String.trim_trailing())

    # Convert tokens to styled lines
    {lines, current_line} =
      Enum.reduce(tokens, {[], []}, fn {type, _meta, text}, {lines, current} ->
        style = Map.get(@token_styles, type) || @code_block_style
        # Makeup can return charlists or lists - normalize to string
        text_str = normalize_token_text(text)
        add_token_to_lines(text_str, style, lines, current)
      end)

    # Finalize - add any remaining content as last line
    all_lines = finalize_code_lines(lines, current_line)

    # Add border prefix to each line
    Enum.map(all_lines, fn segments ->
      [{"│ ", @code_block_style} | segments]
    end)
  end

  # Add token text to lines, handling newlines within tokens
  defp add_token_to_lines(text, style, lines, current) do
    parts = String.split(text, "\n")

    case parts do
      # Single part (no newlines)
      [single] ->
        {lines, current ++ [{single, style}]}

      # Multiple parts (has newlines)
      [first | rest] ->
        # First part finishes current line
        finished_line = current ++ [{first, style}]

        # Split remaining into middle lines and last part
        {middle_parts, [last]} = Enum.split(rest, -1)
        middle_lines = Enum.map(middle_parts, fn part -> [{part, style}] end)

        # Last part starts new current line
        {lines ++ [finished_line] ++ middle_lines, [{last, style}]}
    end
  end

  # Finalize code lines - handle empty current line
  defp finalize_code_lines(lines, []), do: lines
  defp finalize_code_lines(lines, current), do: lines ++ [current]

  # Normalize token text from Makeup (can be string, charlist, or list of chars/strings)
  defp normalize_token_text(text) when is_binary(text), do: text
  defp normalize_token_text(text) when is_list(text) do
    text
    |> List.flatten()
    |> Enum.map(fn
      char when is_integer(char) -> <<char::utf8>>
      str when is_binary(str) -> str
    end)
    |> Enum.join()
  end
  defp normalize_token_text(text), do: to_string(text)

  defp process_node(%MDEx.Code{literal: code}) do
    # Inline code - return as single segment
    [[{"`" <> code <> "`", @code_style}]]
  end

  defp process_node(%MDEx.BlockQuote{nodes: children}) do
    children
    |> Enum.flat_map(&process_node/1)
    |> Enum.map(fn segments ->
      # Prepend blockquote marker to first segment
      case segments do
        [{text, _style} | rest] ->
          [{"│ " <> text, @blockquote_style} | rest]

        [] ->
          [{"│ ", @blockquote_style}]
      end
    end)
  end

  defp process_node(%MDEx.List{list_type: :bullet, nodes: items}) do
    items
    |> Enum.flat_map(fn item ->
      process_list_item(item, "• ")
    end)
    |> Kernel.++([[{"", nil}]])
  end

  defp process_node(%MDEx.List{list_type: :ordered, nodes: items, start: start}) do
    items
    |> Enum.with_index(start || 1)
    |> Enum.flat_map(fn {item, idx} ->
      process_list_item(item, "#{idx}. ")
    end)
    |> Kernel.++([[{"", nil}]])
  end

  defp process_node(%MDEx.ListItem{nodes: children}) do
    # Process list item content
    children
    |> Enum.flat_map(&process_node/1)
  end

  defp process_node(%MDEx.ThematicBreak{}) do
    [[{"───────────────────────────────────────", Style.new(fg: :bright_black)}], [{"", nil}]]
  end

  defp process_node(%MDEx.SoftBreak{}) do
    # Soft breaks become spaces in inline content
    []
  end

  defp process_node(%MDEx.LineBreak{}) do
    # Line breaks become newlines
    [[{"", nil}]]
  end

  # Catch-all for unknown nodes - extract text content
  defp process_node(node) when is_map(node) do
    case Map.get(node, :nodes) do
      nil ->
        case Map.get(node, :literal) do
          nil -> []
          text -> [[{text, nil}]]
        end

      children ->
        Enum.flat_map(children, &process_node/1)
    end
  end

  defp process_node(_), do: []

  # ============================================================================
  # Inline Node Processing
  # ============================================================================

  defp process_inline_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.flat_map(&process_inline_node/1)
    |> merge_adjacent_segments()
  end

  defp process_inline_node(%MDEx.Text{literal: text}) do
    [{text, nil}]
  end

  defp process_inline_node(%MDEx.Strong{nodes: children}) do
    text = extract_text(children)
    [{text, @bold_style}]
  end

  defp process_inline_node(%MDEx.Emph{nodes: children}) do
    text = extract_text(children)
    [{text, @italic_style}]
  end

  defp process_inline_node(%MDEx.Code{literal: code}) do
    [{"`" <> code <> "`", @code_style}]
  end

  defp process_inline_node(%MDEx.Link{url: url, nodes: children}) do
    text = extract_text(children)
    # Show link text with URL in parentheses if different
    if text == url do
      [{text, @link_style}]
    else
      [{text, @link_style}, {" (#{url})", Style.new(fg: :bright_black)}]
    end
  end

  defp process_inline_node(%MDEx.SoftBreak{}) do
    [{" ", nil}]
  end

  defp process_inline_node(%MDEx.LineBreak{}) do
    # Line break in inline - will be handled during line wrapping
    [{"\n", nil}]
  end

  defp process_inline_node(node) when is_map(node) do
    case Map.get(node, :literal) do
      nil ->
        case Map.get(node, :nodes) do
          nil -> []
          children -> process_inline_nodes(children)
        end

      text ->
        [{text, nil}]
    end
  end

  defp process_inline_node(_), do: []

  # ============================================================================
  # List Processing
  # ============================================================================

  defp process_list_item(%MDEx.ListItem{nodes: children}, prefix) do
    children
    |> Enum.flat_map(&process_node/1)
    |> Enum.with_index()
    |> Enum.map(fn {segments, idx} ->
      if idx == 0 do
        # Add bullet/number to first line
        case segments do
          [{text, style} | rest] ->
            [{prefix, @list_bullet_style}, {text, style} | rest]

          [] ->
            [{prefix, @list_bullet_style}]
        end
      else
        # Indent continuation lines
        indent = String.duplicate(" ", String.length(prefix))

        case segments do
          [{text, style} | rest] ->
            [{indent <> text, style} | rest]

          [] ->
            segments
        end
      end
    end)
    # Filter out empty separator lines within list items
    |> Enum.reject(fn segments ->
      segments == [{"", nil}]
    end)
  end

  # ============================================================================
  # Text Extraction
  # ============================================================================

  defp extract_text(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&extract_text/1)
    |> Enum.join()
  end

  defp extract_text(%{literal: text}) when is_binary(text), do: text
  defp extract_text(%{nodes: children}), do: extract_text(children)
  defp extract_text(_), do: ""

  # ============================================================================
  # Segment Merging
  # ============================================================================

  # Merge adjacent segments with the same style
  defp merge_adjacent_segments([]), do: []

  defp merge_adjacent_segments(segments) do
    segments
    |> Enum.reduce([], fn {text, style}, acc ->
      case acc do
        [{prev_text, ^style} | rest] ->
          # Same style - merge
          [{prev_text <> text, style} | rest]

        _ ->
          # Different style - keep separate
          [{text, style} | acc]
      end
    end)
    |> Enum.reverse()
  end

  # ============================================================================
  # Line Wrapping
  # ============================================================================

  @doc """
  Wraps styled lines to fit within max_width.

  Preserves styling across line breaks.
  """
  @spec wrap_styled_lines([styled_line()], pos_integer()) :: [styled_line()]
  def wrap_styled_lines(lines, max_width) do
    lines
    |> Enum.flat_map(fn line ->
      wrap_styled_line(line, max_width)
    end)
  end

  defp wrap_styled_line([], _max_width), do: [[]]

  defp wrap_styled_line(segments, max_width) do
    # Handle explicit newlines within segments first
    expanded_segments =
      segments
      |> Enum.flat_map(fn {text, style} ->
        if String.contains?(text, "\n") do
          text
          |> String.split("\n")
          |> Enum.intersperse(:newline)
          |> Enum.map(fn
            :newline -> :newline
            t -> {t, style}
          end)
        else
          [{text, style}]
        end
      end)

    # Split on newlines first
    {current, wrapped} =
      Enum.reduce(expanded_segments, {[], []}, fn
        :newline, {current, acc} ->
          {[], acc ++ [Enum.reverse(current)]}

        segment, {current, acc} ->
          {[segment | current], acc}
      end)

    lines_from_newlines = wrapped ++ [Enum.reverse(current)]

    # Now wrap each resulting line for width
    lines_from_newlines
    |> Enum.flat_map(fn line_segments ->
      wrap_segments_for_width(line_segments, max_width)
    end)
  end

  defp wrap_segments_for_width([], _max_width), do: [[]]

  defp wrap_segments_for_width(segments, max_width) do
    {lines, current_line, _current_width} =
      Enum.reduce(segments, {[], [], 0}, fn {text, style}, {lines, current, width} ->
        wrap_segment({text, style}, lines, current, width, max_width)
      end)

    # Don't forget the last line
    all_lines = lines ++ [current_line]

    # Filter out completely empty lines that aren't intentional
    all_lines
    |> Enum.map(fn line ->
      case line do
        [] -> [{"", nil}]
        segments -> segments
      end
    end)
  end

  defp wrap_segment({text, style}, lines, current, width, max_width) do
    text_len = String.length(text)

    cond do
      # Empty text - just pass through
      text == "" ->
        {lines, current ++ [{text, style}], width}

      # Fits on current line
      width + text_len <= max_width ->
        {lines, current ++ [{text, style}], width + text_len}

      # Need to wrap - try word boundaries
      true ->
        wrap_text_at_words(text, style, lines, current, width, max_width)
    end
  end

  defp wrap_text_at_words(text, style, lines, current, width, max_width) do
    words = String.split(text, ~r/(\s+)/, include_captures: true)
    _remaining_width = max_width - width

    {final_lines, final_current, final_width} =
      Enum.reduce(words, {lines, current, width}, fn word, {ls, cur, w} ->
        word_len = String.length(word)

        cond do
          # Empty word
          word == "" ->
            {ls, cur, w}

          # Word fits on current line
          w + word_len <= max_width ->
            {ls, cur ++ [{word, style}], w + word_len}

          # Word is longer than max width - force break
          word_len > max_width ->
            {new_lines, remainder} = break_long_word(word, style, max_width - w, max_width)

            if cur == [] do
              {ls ++ new_lines, [{remainder, style}], String.length(remainder)}
            else
              {ls ++ [cur] ++ new_lines, [{remainder, style}], String.length(remainder)}
            end

          # Start new line with this word (skip leading whitespace)
          String.trim(word) == "" ->
            {ls, cur, w}

          true ->
            # Word doesn't fit - wrap to new line
            {ls ++ [cur], [{word, style}], word_len}
        end
      end)

    {final_lines, final_current, final_width}
  end

  defp break_long_word(word, style, first_chunk_size, max_width) do
    first_chunk_size = max(first_chunk_size, 1)

    chunks =
      word
      |> String.graphemes()
      |> Enum.chunk_every(max_width)
      |> Enum.map(&Enum.join/1)

    case chunks do
      [] ->
        {[], ""}

      [only] ->
        {[], only}

      [first | rest] ->
        # First chunk uses remaining space on current line
        first_part = String.slice(first, 0, first_chunk_size)
        remainder_of_first = String.slice(first, first_chunk_size..-1//1)

        all_parts = [remainder_of_first | rest]

        lines =
          all_parts
          |> Enum.slice(0..-2//1)
          |> Enum.map(fn part -> [{part, style}] end)

        last = List.last(all_parts) || ""

        if first_part == "" do
          {lines, last}
        else
          {[[{first_part, style}]] ++ lines, last}
        end
    end
  end
end
