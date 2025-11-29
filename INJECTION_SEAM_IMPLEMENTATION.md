<!--
SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# ReqLLM Injection Seam Implementation

## Summary

This document describes the implementation of a ReqLLM injection seam for `AshAi.iex_chat/2`, enabling testable integration tests without making actual LLM API calls.

## Changes Made

### 1. Added `req_llm` Option to Options Schema

**File**: `lib/ash_ai.ex`

Added a new `:req_llm` option to the `AshAi.Options` schema:

```elixir
req_llm: [
  type: :atom,
  default: ReqLLM,
  doc: """
  The ReqLLM module to use for LLM operations. Defaults to `ReqLLM`.
  
  This is primarily intended for testing purposes, allowing you to inject
  a mock ReqLLM implementation to control responses and validate behavior
  without making actual API calls.
  
  Example for testing:
  ```
  iex_chat(nil, req_llm: FakeReqLLM, ...)
  ```
  """
]
```

### 2. Updated `run_loop/5` to Use Injected Module

**File**: `lib/ash_ai.ex`

Modified the `run_loop/5` function to use the injected `req_llm` module instead of hardcoding `ReqLLM`:

```elixir
defp run_loop(model, messages, tools, registry, opts, _first?) do
  req_llm = opts.req_llm
  {:ok, response} = req_llm.stream_text(model, messages, tools: tools)
  # ... rest of implementation
end
```

### 3. Created Integration Test Example

**File**: `test/ash_ai/iex_chat_integration_test.exs`

Created a new test file demonstrating:
- How to create a `FakeReqLLM` module for testing
- How to inject it into `iex_chat`
- Example of simulating a tool-call loop
- Tests validating the `req_llm` option is properly validated and defaults correctly

## Usage

### For Production

The default behavior is unchanged - `iex_chat` uses the real `ReqLLM` module:

```elixir
AshAi.iex_chat(nil,
  otp_app: :my_app,
  model: "openai:gpt-4o-mini"
)
```

### For Testing

Inject a mock ReqLLM module to control responses:

```elixir
defmodule FakeReqLLM do
  def stream_text(_model, _messages, _opts) do
    stream = [
      %{type: :content, text: "Mocked response"}
    ]
    {:ok, %{stream: stream}}
  end
end

# Use in tests
AshAi.iex_chat(nil,
  req_llm: FakeReqLLM,
  otp_app: :my_app,
  model: "test:model"
)
```

## Benefits

1. **Testability**: Can now write integration tests for tool-call loops without hitting actual LLM APIs
2. **Deterministic Tests**: Mock responses ensure tests are predictable and fast
3. **Cost Reduction**: No API costs during development and testing
4. **Offline Development**: Can develop and test without network connectivity
5. **Consistency**: Aligns with existing patterns in prompt-backed actions and embeddings

## Alignment with Existing Patterns

This implementation follows the same pattern used elsewhere in AshAi:

- **Prompt-backed actions** (`AshAi.Actions.Prompt`) already support `req_llm` injection
- **Vectorization** uses `Process.put(:reqllm_mock)` for mocking embeddings
- **iex_chat** now completes the pattern for comprehensive testability

## Future Work

To enable truly end-to-end integration tests with `iex_chat`, we would need:

1. A non-interactive mode option to prevent the infinite user input loop
2. A way to programmatically feed user messages (vs. `Mix.shell().prompt/1`)
3. A callback or collection mechanism to capture assistant responses

Example possible API:

```elixir
AshAi.iex_chat(nil,
  req_llm: FakeReqLLM,
  interactive: false,
  user_messages: ["What data do you have?", "exit"],
  on_response: fn text -> send(self(), {:response, text}) end
)
```

## Testing

All existing tests pass with this change:
- ✅ 71 tests, 0 failures, 1 skipped
- ✅ No breaking changes to existing behavior
- ✅ New integration test validates option behavior

## References

- **OVERVIEW.md** - Updated to reflect this implementation
- **README.md** - Documents the `iex_chat` feature
- **AGENTS.md** - Testing guidance for contributors
