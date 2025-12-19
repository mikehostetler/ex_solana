# Feature: ConversationView Clipboard Integration (Phase 9.8)

## Status: COMPLETE

## Problem Statement

The ConversationView widget has a copy functionality triggered by the 'y' key, but it relies on an `on_copy` callback that isn't wired to actual system clipboard integration. Users need to be able to copy message content to the system clipboard for sharing or pasting elsewhere.

## Solution Overview

Create a cross-platform clipboard module that:
1. Detects available clipboard commands based on the operating system
2. Provides a `copy_to_clipboard/1` function that pipes text to the clipboard
3. Wire this function as the `on_copy` callback for ConversationView

## Technical Details

### New Files
- `lib/jido_code/tui/clipboard.ex` - Clipboard detection and copy implementation
- `test/jido_code/tui/clipboard_test.exs` - Unit tests for clipboard module

### Modified Files
- `lib/jido_code/tui.ex` - Pass clipboard callback to ConversationView init

### Platform-Specific Clipboard Commands
| Platform | Command | Notes |
|----------|---------|-------|
| macOS | `pbcopy` | Built-in |
| Linux X11 | `xclip -selection clipboard` | Requires xclip package |
| Linux X11 | `xsel --clipboard --input` | Alternative to xclip |
| Linux Wayland | `wl-copy` | Requires wl-clipboard package |
| WSL/Windows | `clip.exe` | Available in WSL |

## Implementation Plan

### Task 9.8.1: Clipboard Detection
- [x] Create `lib/jido_code/tui/clipboard.ex` module
- [x] Implement `detect_clipboard_command/0`
- [x] Check for `pbcopy` (macOS)
- [x] Check for `xclip` (Linux X11)
- [x] Check for `xsel` (Linux X11 alternative)
- [x] Check for `wl-copy` (Linux Wayland)
- [x] Check for `clip.exe` (WSL/Windows)
- [x] Return `nil` if no clipboard available
- [x] Write unit tests for clipboard detection

### Task 9.8.2: Copy Implementation
- [x] Implement `copy_to_clipboard/1` function
- [x] Use detected clipboard command
- [x] Pipe text content to clipboard command via stdin
- [x] Handle command execution errors gracefully
- [x] Log warning if no clipboard available
- [x] Return `:ok` or `{:error, reason}`
- [x] Write unit tests (mocked command execution)

### Task 9.8.3: ConversationView Callback
- [x] Pass `on_copy: &Clipboard.copy_to_clipboard/1` in ConversationView init
- [x] Ensure callback receives message content string
- [x] Write integration test for copy flow

## Success Criteria

1. `detect_clipboard_command/0` correctly identifies available clipboard tool
2. `copy_to_clipboard/1` successfully copies text to system clipboard
3. Error handling is graceful when no clipboard is available
4. ConversationView 'y' key triggers actual clipboard copy
5. Tests cover all clipboard commands and error paths

## Notes

- Clipboard detection runs once at module load time (cached)
- Copy errors should not crash the TUI, only log warnings
- Consider adding visual feedback for successful copy (status bar message)
