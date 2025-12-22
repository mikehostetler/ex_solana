# Feature: WS-3.2.4 Web Handlers Session Context

## Problem Statement

The web handlers (Fetch, Search) currently don't track session context. While they don't need path validation (they access external URLs, not local files), they should include session_id in result metadata for:
1. Correlation of web requests with sessions
2. Logging and debugging
3. Consistent handler pattern across all tool types

Task 3.2.4 requires updating web handlers to include session context in results.

## Current State

### Current Handler Pattern

```elixir
# Fetch - doesn't track session
def execute(%{"url" => url} = args, context) when is_binary(url) do
  with {:ok, validated_url} <- WebSecurity.validate_url(url, ...),
       {:ok, response} <- fetch_url(validated_url),
       {:ok, content} <- process_response(response) do
    {:ok, Jason.encode!(content)}  # No session_id
  end
end

# Search - ignores context entirely
def execute(%{"query" => query} = args, _context) when is_binary(query) do
  case search_duckduckgo(query, max_results) do
    {:ok, results} -> {:ok, Jason.encode!(results)}  # No session_id
  end
end
```

## Solution Overview

Update web handlers to:
1. Include `session_id` in result metadata when present in context
2. Keep backwards compatibility (no session_id if not provided)
3. No path validation needed (web URLs are external)

### New Handler Pattern

```elixir
def execute(%{"url" => url} = args, context) when is_binary(url) do
  with {:ok, validated_url} <- WebSecurity.validate_url(url, ...),
       {:ok, response} <- fetch_url(validated_url),
       {:ok, content} <- process_response(response) do
    result = add_session_metadata(content, context)
    {:ok, Jason.encode!(result)}
  end
end

defp add_session_metadata(result, %{session_id: session_id}) do
  Map.put(result, :session_id, session_id)
end
defp add_session_metadata(result, _context), do: result
```

## Implementation Plan

### Step 1: Update Fetch handler
- [x] Add helper to include session metadata
- [x] Include session_id in result when present

### Step 2: Update Search handler
- [x] Use context parameter (currently ignored)
- [x] Include session_id in result when present

### Step 3: Write unit tests
- [x] Test Fetch includes session_id when provided
- [x] Test Search includes session_id when provided
- [x] Test handlers work without session_id (backwards compatibility)

## Success Criteria

- [x] Web handlers include session_id in results when provided
- [x] Handlers work without session_id (backwards compatibility)
- [x] All existing tests pass
- [x] New tests cover session context usage

## Current Status

**Status**: Complete

## Test Results

- 30 web handler tests pass (26 existing + 4 new)
- 4 new session-aware tests:
  - Fetch includes session_id in result when provided
  - Fetch works without session_id (backwards compatibility)
  - Search includes session_id in result when provided
  - Search works without session_id (backwards compatibility)

## Files Changed

### Modified
- `lib/jido_code/tools/handlers/web.ex` - Session metadata in results
- `test/jido_code/tools/handlers/web_test.exs` - Session context tests
