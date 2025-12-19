# Feature: Phase 4 Review Fixes

## Problem Statement

The Phase 4 review identified several concerns and suggestions to improve code quality. This task addresses the following issues:

**Concerns (Should Address):**
1. Message rendering duplication (lines 599-633) - three nearly identical `render_message/2` clauses
2. `@spec` inconsistency - private functions have specs (against codebase pattern), public `wrap_text/3` missing spec
3. Scroll offset performance - double `Enum.reverse()` is O(n)
4. Ctrl+M handler missing - hint displayed but no handler (planned feature - just document)

**Suggestions (Nice to Have):**
5. Remove unused test helper `find_step_node/1` (line 982) - causes compiler warning
6. Add `@spec` to public `wrap_text/3` function

## Solution Overview

### Step 1: Consolidate Message Rendering
- [x] 1.1 Create `message_config/1` helper returning {label, style} for each role
- [x] 1.2 Consolidate three `render_message/2` clauses into one

### Step 2: Fix @spec Inconsistency
- [x] 2.1 Remove `@spec` from private function `load_config/0` (line 425)
- [x] 2.2 Remove `@spec` from `determine_status/1` (line 436) but keep it public for tests
- [x] 2.3 Add `@spec` to public function `wrap_text/3` (line 664)

### Step 3: Optimize Scroll Offset
- [x] 3.1 Replace double `Enum.reverse()` with `Enum.take/2` approach
- [x] 3.2 Extract to `get_visible_messages/2` helper function

### Step 4: Remove Unused Test Helper
- [x] 4.1 Remove unused `find_step_node/1` helper (lines 982-1001)

### Step 5: Verify
- [x] 5.1 Run `mix compile` - no warnings
- [x] 5.2 Run `mix test` - all tests pass

## Implementation Details

### Message Config Consolidation

Before:
```elixir
defp render_message(%{role: :user, content: content, timestamp: timestamp}, width) do
  # ... duplicated logic with "You", Style.new(fg: :cyan)
end

defp render_message(%{role: :assistant, content: content, timestamp: timestamp}, width) do
  # ... duplicated logic with "Assistant", Style.new(fg: :white)
end

defp render_message(%{role: :system, content: content, timestamp: timestamp}, width) do
  # ... duplicated logic with "System", Style.new(fg: :bright_black)
end
```

After:
```elixir
defp message_config(:user), do: {"You", Style.new(fg: :cyan)}
defp message_config(:assistant), do: {"Assistant", Style.new(fg: :white)}
defp message_config(:system), do: {"System", Style.new(fg: :bright_black)}

defp render_message(%{role: role, content: content, timestamp: timestamp}, width) do
  {label, style} = message_config(role)
  time_str = format_timestamp(timestamp)
  prefix = "[#{time_str}] #{label}: "
  wrapped_lines = wrap_message(prefix, content, width)

  lines_as_nodes =
    wrapped_lines
    |> Enum.map(fn line -> text(line, style) end)

  stack(:vertical, lines_as_nodes)
end
```

### Scroll Offset Optimization

Before:
```elixir
visible_messages =
  if state.scroll_offset > 0 do
    messages
    |> Enum.reverse()
    |> Enum.drop(state.scroll_offset)
    |> Enum.reverse()
  else
    messages
  end
```

After:
```elixir
visible_messages = get_visible_messages(messages, state.scroll_offset)

defp get_visible_messages(messages, 0), do: messages
defp get_visible_messages(messages, scroll_offset) do
  keep_count = length(messages) - scroll_offset
  if keep_count > 0, do: Enum.take(messages, keep_count), else: messages
end
```

## Success Criteria

1. No code duplication in message rendering
2. `@spec` only on public functions
3. Scroll offset uses efficient algorithm
4. No compiler warnings
5. All 75 tests pass

## Current Status

**Status**: Complete
