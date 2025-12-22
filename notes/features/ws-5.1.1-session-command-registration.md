# WS-5.1.1 Session Command Registration

**Branch:** `feature/ws-5.1.1-session-command-registration`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Add session commands to the command registry. This enables users to manage sessions via slash commands (/session new, /session list, etc.).

## Problem Statement

The TUI supports multiple sessions (Phase 4), but users have no command-line interface to create, list, switch, close, or rename sessions. This task adds the `/session` command family to the Commands module.

## Implementation Plan

### Step 1: Update command pattern matching in Commands.parse/1
- [x] Add `/session` command routing to parse_and_execute/2
- [x] Add `/session <args>` pattern to route to session subcommand handler

### Step 2: Define session subcommands
- [x] `new [path] [--name=name]` - Create new session
- [x] `list` - List all sessions
- [x] `switch <id|index>` - Switch to session
- [x] `close [id|index]` - Close session
- [x] `rename <name>` - Rename current session

### Step 3: Implement parse_session_args/1
- [x] Parse `new` subcommand with optional path and --name flag
- [x] Parse `list` subcommand
- [x] Parse `switch` subcommand with target
- [x] Parse `close` subcommand with optional target
- [x] Parse `rename` subcommand with name
- [x] Return `:help` for unknown subcommands

### Step 4: Write unit tests
- [x] Test `/session new /path/to/project` parses correctly
- [x] Test `/session new /path --name=MyProject` parses name flag
- [x] Test `/session list` parses to :list
- [x] Test `/session switch 1` parses index
- [x] Test `/session switch abc123` parses ID
- [x] Test `/session close` parses with no target
- [x] Test `/session close 2` parses with index
- [x] Test `/session rename NewName` parses name
- [x] Test `/session` shows help

### Step 5: Update help text
- [x] Add session commands to @help_text

## Files Modified

- `lib/jido_code/commands.ex` - Added session command parsing (72 lines)
- `test/jido_code/commands_test.exs` - Added 17 tests for session commands

## Technical Notes

The session command returns `{:session, subcommand}` tuple that the TUI will handle:
- `{:session, :help}` - Show session help
- `{:session, :list}` - List sessions
- `{:session, {:new, %{path: path, name: name}}}` - Create new session
- `{:session, {:switch, target}}` - Switch to session
- `{:session, {:close, target}}` - Close session (nil = active)
- `{:session, {:rename, name}}` - Rename session
- `{:session, {:error, reason}}` - Parse error

## Test Results

```
47 tests, 0 failures
- 30 existing tests
- 17 new session command tests
```

## Success Criteria

1. `/session` command recognized and routed - DONE
2. All subcommands parsed correctly - DONE
3. Help text updated - DONE
4. Unit tests pass - DONE (47 tests)
5. No breaking changes to existing commands - DONE
