# Summary: Markdown Conversation Display

**Branch:** `feature/markdown-conversation-display`
**Date:** 2025-12-26

## Overview

Added markdown rendering support to the conversation view in the TUI. Assistant messages now display with proper formatting including headers, bold, italic, code blocks, lists, and more.

## Changes Made

### New Files

1. **`lib/jido_code/tui/markdown.ex`** - Markdown processor module
   - Parses markdown using MDEx library
   - Converts markdown AST to styled segments
   - Handles text wrapping with style preservation
   - Supports headers, bold, italic, code, lists, blockquotes, links

2. **`test/jido_code/tui/markdown_test.exs`** - Test suite (26 tests)
   - Tests for all markdown element types
   - Tests for line wrapping with styles
   - Tests for edge cases and error handling

3. **`notes/features/markdown-conversation-display.md`** - Planning document

### Modified Files

1. **`mix.exs`** - Added MDEx dependency
   ```elixir
   {:mdex, "~> 0.10"}
   ```

2. **`lib/jido_code/tui/widgets/conversation_view.ex`**
   - Modified `render_message/4` to use markdown for assistant messages
   - Added `render_markdown_content/4` for styled markdown rendering
   - Added `render_plain_content/5` for user/system messages
   - Added helper functions for styled line rendering

## Technical Details

### Markdown Element Styling

| Element | Style |
|---------|-------|
| `# H1` | Bold, cyan |
| `## H2` | Bold, cyan |
| `### H3+` | Bold, white |
| `**bold**` | Bold attribute |
| `*italic*` | Italic attribute |
| `` `code` `` | Yellow foreground |
| Code blocks | Yellow with box border, language header |
| `> quote` | Bright black (dim) |
| `- list` | Cyan bullet |
| `[link](url)` | Blue, underline |

### Code Block Rendering

Code blocks are rendered with a box-style border:
```
┌─ elixir ────────────────────────────────────────
│ defmodule Example do
│   def hello, do: :world
│ end
└────────────────────────────────────────────
```

- Language is normalized to lowercase and displayed in header
- Code content is styled in yellow
- Box borders use unicode box-drawing characters

### Architecture

```
Content → MDEx Parser → AST → Styled Segments → Wrapped Lines → Render Nodes
```

1. MDEx parses markdown to AST
2. `process_document/1` converts AST to styled segments
3. `wrap_styled_lines/2` handles line wrapping preserving styles
4. `render_styled_line_with_indent/2` creates TermUI render nodes

### Key Design Decisions

- **Assistant messages only** - User and system messages remain plain text
- **Render-time processing** - No storage changes, markdown converted during rendering
- **Fallback handling** - Parse errors fall back to plain text display
- **Style preservation** - Styles maintained across word wraps

## Testing

```bash
mix test test/jido_code/tui/markdown_test.exs
```

All 26 tests pass covering:
- Basic text rendering
- All markdown element types
- Line wrapping
- Edge cases (empty, nil, malformed)

## Dependencies Added

- **MDEx 0.10** - Fast Rust-based CommonMark parser
- **Autumn** - Syntax highlighting (MDEx dependency)
- **rustler_precompiled** - Rust NIF support

## Additional Enhancement: Language-Aware System Prompt

Modified `lib/jido_code/agents/llm_agent.ex` to include language-specific instructions in the system prompt:

- When a session has a detected programming language, the system prompt includes:
  ```
  Language Context:
  This project uses [Language]. When providing code snippets, write them in [Language] unless a different language is specifically requested.
  ```
- Uses `JidoCode.Language.display_name/1` to get human-readable language name
- Falls back to base prompt for sessions without language detection

## Future Improvements

- Syntax highlighting for code blocks (language-specific)
- Table rendering support
- Image placeholders
- Clickable links (with terminal capability detection)
