# Feature: Markdown Conversation Display

## Problem Statement

Currently, the JidoCode TUI conversation view renders all message content as plain text. Assistant responses often contain markdown formatting (headers, bold, italic, code blocks, lists, etc.) that is displayed as raw text rather than being properly rendered with terminal styling.

### Impact
- Poor readability of structured responses
- Code blocks not visually distinguished
- Headers, bold, italic not emphasized
- Lists not properly formatted
- Links not highlighted

## Solution Overview

Create a markdown processor module that converts markdown content to styled TermUI render nodes, then integrate it into the ConversationView widget to render assistant messages with proper formatting.

### Key Decisions
1. **Use MDEx library** - Fast Rust-based CommonMark parser with AST output
2. **Process at render time** - Convert markdown during message rendering, not at storage
3. **Assistant messages only** - User messages remain plain text
4. **Terminal-appropriate styling** - Map markdown elements to ANSI styles

## Technical Details

### New Module: `JidoCode.TUI.Markdown`

Location: `lib/jido_code/tui/markdown.ex`

Responsibilities:
- Parse markdown content using MDEx
- Convert AST to list of styled segments
- Handle inline elements (bold, italic, code, links)
- Handle block elements (headers, code blocks, lists, blockquotes)
- Integrate with text wrapping

### Dependencies

Add to `mix.exs`:
```elixir
{:mdex, "~> 0.10"}
```

### Markdown Element Mapping

| Markdown | Terminal Style |
|----------|---------------|
| `# Header` | Bold, bright color |
| `## Header` | Bold |
| `**bold**` | Bold attribute |
| `*italic*` | Italic attribute (dim fallback) |
| `` `code` `` | Cyan foreground |
| ```` ```code``` ```` | Cyan fg, indented block |
| `> quote` | Dim, indented |
| `- list` | Bullet prefix |
| `[link](url)` | Underline, cyan |

### Integration Points

1. **ConversationView.render_message/4** (`conversation_view.ex:1081`)
   - Detect assistant role
   - Route content through markdown processor
   - Receive list of styled segments instead of plain lines

2. **ConversationView.wrap_text/2** (`conversation_view.ex:1172`)
   - Modify to handle styled segments
   - Preserve styles across line wraps

### API Design

```elixir
defmodule JidoCode.TUI.Markdown do
  @type styled_segment :: {String.t(), TermUI.Style.t() | nil}
  @type styled_line :: [styled_segment]

  @spec render(String.t(), pos_integer()) :: [styled_line]
  def render(markdown_content, max_width)

  @spec render_line(styled_line) :: TermUI.Component.RenderNode.t()
  def render_line(segments)
end
```

## Success Criteria

1. Code blocks render with cyan foreground and proper indentation
2. Headers render bold with appropriate emphasis
3. Bold and italic text render with correct attributes
4. Lists render with bullet points
5. Inline code renders with distinct styling
6. Long content still wraps correctly
7. No performance degradation for large messages
8. Plain text fallback if parsing fails

## Implementation Plan

### Step 1: Add MDEx dependency ✅
- Add `{:mdex, "~> 0.10"}` to mix.exs
- Run `mix deps.get`
- Verify compilation

### Step 2: Create Markdown module ✅
- Create `lib/jido_code/tui/markdown.ex`
- Implement `parse/1` using MDEx.parse_document
- Implement AST to styled segments conversion
- Handle inline elements (emphasis, strong, code)
- Handle block elements (headers, code blocks, lists)

### Step 3: Implement styled text wrapping ✅
- Create `wrap_styled_text/2` that preserves styles across wraps
- Handle segment boundaries during wrapping
- Maintain style continuity

### Step 4: Integrate with ConversationView ✅
- Modify `render_message/4` to detect assistant role
- Route assistant content through markdown processor
- Convert styled segments to render nodes
- Fallback to plain text on error

### Step 5: Add tests ✅
- Unit tests for markdown parsing
- Tests for styled segment generation
- Tests for text wrapping with styles
- Integration tests with ConversationView

### Step 6: Update documentation ✅
- Add module documentation
- Update CLAUDE.md if needed
- Write summary in notes/summaries

## Notes/Considerations

### Edge Cases
- Empty content
- Very long lines without breaks
- Nested formatting (bold inside italic)
- Malformed markdown
- Code blocks with special characters

### Performance
- MDEx is Rust-based and very fast
- Parse only on render, cache if needed
- Lazy evaluation for large messages

### Future Improvements
- Syntax highlighting for code blocks (language-specific)
- Clickable links (requires terminal support detection)
- Table rendering
- Image placeholders

## Current Status

- [x] Research completed
- [x] Planning document created
- [x] Implementation completed
- [x] Tests written (26 tests, all passing)
- [x] Documentation updated
