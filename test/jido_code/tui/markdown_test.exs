defmodule JidoCode.TUI.MarkdownTest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI.Markdown
  alias TermUI.Renderer.Style

  describe "render/2" do
    test "renders empty string" do
      result = Markdown.render("", 80)
      assert result == [[{"", nil}]]
    end

    test "renders nil content" do
      result = Markdown.render(nil, 80)
      assert result == [[{"", nil}]]
    end

    test "renders plain text" do
      result = Markdown.render("Hello world", 80)

      assert [[{"Hello world", nil}], [{"", nil}]] = result
    end

    test "renders bold text" do
      result = Markdown.render("**bold**", 80)

      assert [[{text, style}] | _] = result
      assert text == "bold"
      assert :bold in style.attrs
    end

    test "renders italic text" do
      result = Markdown.render("*italic*", 80)

      assert [[{text, style}] | _] = result
      assert text == "italic"
      assert :italic in style.attrs
    end

    test "renders inline code" do
      result = Markdown.render("`code`", 80)

      assert [[{text, style}] | _] = result
      assert text == "`code`"
      assert style.fg == :yellow
    end

    test "renders mixed bold and normal text" do
      result = Markdown.render("**bold** text", 80)

      # First line should have segments
      assert [[bold_seg, text_seg] | _] = result
      assert {"bold", bold_style} = bold_seg
      assert :bold in bold_style.attrs
      assert {" text", nil} = text_seg
    end

    test "renders header level 1" do
      result = Markdown.render("# Header", 80)

      assert [[{text, style}] | _] = result
      assert String.starts_with?(text, "# ")
      assert String.contains?(text, "Header")
      assert :bold in style.attrs
      assert style.fg == :cyan
    end

    test "renders header level 2" do
      result = Markdown.render("## Header", 80)

      assert [[{text, style}] | _] = result
      assert String.starts_with?(text, "## ")
      assert :bold in style.attrs
    end

    test "renders header level 3" do
      result = Markdown.render("### Header", 80)

      assert [[{text, style}] | _] = result
      assert String.starts_with?(text, "### ")
      assert :bold in style.attrs
    end

    test "renders code block" do
      result = Markdown.render("```\ncode\n```", 80)

      # Should have opening border, code line, closing border
      assert length(result) >= 3

      # Check code line has yellow color (with │ prefix for border)
      code_lines = Enum.filter(result, fn segments when is_list(segments) ->
        Enum.any?(segments, fn
          {text, style} when is_struct(style, Style) ->
            String.contains?(text, "code") and style.fg == :yellow
          _ -> false
        end)
      end)
      assert length(code_lines) >= 1
    end

    test "renders code block with language" do
      result = Markdown.render("```elixir\nIO.puts(\"hello\")\n```", 80)

      # Find line containing language info (may be in multiple segments)
      has_lang = Enum.any?(result, fn segments when is_list(segments) ->
        full_text = Enum.map_join(segments, "", fn {text, _style} -> text end)
        String.contains?(full_text, "elixir")
      end)
      assert has_lang
    end

    test "renders bullet list" do
      result = Markdown.render("- item 1\n- item 2", 80)

      # Should have bullet markers
      has_bullets = Enum.any?(result, fn
        segments when is_list(segments) ->
          Enum.any?(segments, fn
            {"• ", _style} -> true
            {text, _} -> String.contains?(text, "•")
            _ -> false
          end)
        _ -> false
      end)
      assert has_bullets
    end

    test "renders ordered list" do
      result = Markdown.render("1. first\n2. second", 80)

      # Should have number markers
      has_numbers = Enum.any?(result, fn
        segments when is_list(segments) ->
          Enum.any?(segments, fn
            {text, _style} -> Regex.match?(~r/^\d+\.\s/, text)
            _ -> false
          end)
        _ -> false
      end)
      assert has_numbers
    end

    test "renders blockquote" do
      result = Markdown.render("> quoted text", 80)

      # Should have quote marker
      has_quote = Enum.any?(result, fn
        [{text, style}] when is_struct(style, Style) ->
          String.starts_with?(text, "│") and style.fg == :bright_black
        _ -> false
      end)
      assert has_quote
    end

    test "renders link" do
      result = Markdown.render("[text](https://example.com)", 80)

      # Should have underlined link text
      has_link = Enum.any?(result, fn
        segments when is_list(segments) ->
          Enum.any?(segments, fn
            {text, style} when is_struct(style, Style) ->
              text == "text" and :underline in style.attrs
            _ -> false
          end)
        _ -> false
      end)
      assert has_link
    end

    test "renders thematic break" do
      result = Markdown.render("---", 80)

      # Should have horizontal rule
      has_hr = Enum.any?(result, fn
        [{text, _style}] -> String.contains?(text, "───")
        _ -> false
      end)
      assert has_hr
    end

    test "wraps long lines" do
      long_text = String.duplicate("word ", 20)
      result = Markdown.render(long_text, 40)

      # Should produce multiple lines
      non_empty_lines = Enum.filter(result, fn
        [{"", nil}] -> false
        _ -> true
      end)
      assert length(non_empty_lines) > 1
    end

    test "handles malformed markdown gracefully" do
      # Unclosed code block
      result = Markdown.render("```\ncode without closing", 80)
      # Should not crash, should return some result
      assert is_list(result)
    end

    test "preserves explicit newlines" do
      result = Markdown.render("line1\n\nline2", 80)

      # Should have multiple lines with empty lines in between
      assert length(result) >= 3
    end
  end

  describe "render_line/1" do
    test "renders empty list" do
      result = Markdown.render_line([])
      assert %TermUI.Component.RenderNode{type: :text, content: ""} = result
    end

    test "renders single segment" do
      style = Style.new(fg: :cyan)
      result = Markdown.render_line([{"hello", style}])

      assert %TermUI.Component.RenderNode{type: :text, content: "hello"} = result
    end

    test "renders multiple segments as horizontal stack" do
      style1 = Style.new(fg: :cyan)
      style2 = Style.new(attrs: [:bold])

      result = Markdown.render_line([{"hello ", style1}, {"world", style2}])

      assert %TermUI.Component.RenderNode{type: :stack, direction: :horizontal} = result
      assert length(result.children) == 2
    end
  end

  describe "wrap_styled_lines/2" do
    test "wraps lines that exceed max width" do
      long_line = [{String.duplicate("a", 100), nil}]
      result = Markdown.wrap_styled_lines([long_line], 50)

      # Should produce multiple lines
      assert length(result) > 1
    end

    test "preserves style across word wrap" do
      style = Style.new(fg: :cyan)
      line = [{"word1 word2 word3", style}]
      result = Markdown.wrap_styled_lines([line], 10)

      # All segments should have the same style
      for line <- result do
        for {_text, seg_style} <- line do
          if seg_style do
            assert seg_style.fg == :cyan
          end
        end
      end
    end

    test "handles explicit newlines in segments" do
      line = [{"line1\nline2", nil}]
      result = Markdown.wrap_styled_lines([line], 80)

      # Should split on newline
      assert length(result) >= 2
    end
  end

  describe "render_with_elements/2" do
    test "returns empty elements for plain text" do
      result = Markdown.render_with_elements("Hello world", 80)

      assert %{lines: lines, elements: elements} = result
      assert length(lines) >= 1
      assert elements == []
    end

    test "returns code block elements with metadata" do
      markdown = """
      Some text

      ```elixir
      def hello, do: :world
      ```

      More text
      """

      result = Markdown.render_with_elements(markdown, 80)

      assert %{lines: _lines, elements: elements} = result
      assert length(elements) == 1

      [element] = elements
      assert element.type == :code_block
      assert element.language == "elixir"
      assert element.content == "def hello, do: :world"
      assert is_binary(element.id)
      assert element.start_line >= 0
      assert element.end_line > element.start_line
    end

    test "returns multiple code block elements" do
      markdown = """
      ```python
      print("hello")
      ```

      Some text

      ```javascript
      console.log("world")
      ```
      """

      result = Markdown.render_with_elements(markdown, 80)

      assert %{elements: elements} = result
      assert length(elements) == 2

      [first, second] = elements
      assert first.language == "python"
      assert second.language == "javascript"
      # Second block should start after first block ends
      assert second.start_line > first.end_line
    end

    test "generates deterministic IDs for code blocks" do
      markdown = """
      ```elixir
      def hello, do: :world
      ```
      """

      result1 = Markdown.render_with_elements(markdown, 80)
      result2 = Markdown.render_with_elements(markdown, 80)

      # Same content should produce same IDs
      assert hd(result1.elements).id == hd(result2.elements).id
    end

    test "handles empty and nil content" do
      assert %{lines: _, elements: []} = Markdown.render_with_elements("", 80)
      assert %{lines: _, elements: []} = Markdown.render_with_elements(nil, 80)
    end
  end
end
