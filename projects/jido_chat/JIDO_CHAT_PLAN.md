# Jido.Chat Modernization Plan

**Status:** DRAFT for review  
**Target:** Unreleased modernization - no backwards compatibility constraints  
**Constraint:** Support up to 1000 participants per room  
**Goal:** Modernize jido_chat to align with GENERIC_PACKAGE_QA standards, use Zoi + Splode like other Jido projects, and enhance resilience

---

## Executive Summary

The current jido_chat implementation has a sound architectural foundation (signal bus + OTP rooms + strategy abstraction) but needs modernization to:

1. **Replace TypedStruct with Zoi** - Match jido_character, llm_db patterns for runtime validation
2. **Add Splode error handling** - Align with jido, jido_action, req_llm error patterns
3. **Scale to 1000 participants** - Add limits, persistence, and performance optimizations
4. **Achieve GENERIC_PACKAGE_QA compliance** - Quality, docs, CI, tooling standards
5. **Enhance resilience** - Message limits, backpressure, graceful degradation

**Recommendation:** Modernize in place (not rewrite). The core architecture is excellent for Jido's event-driven model.

---

## Part 1: Dependencies & Tooling

### 1.1 Update mix.exs Dependencies

**Add:**
```elixir
{:zoi, "~> 0.14"},
{:splode, "~> 0.2"},
{:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
{:git_ops, "~> 2.9", only: :dev, runtime: false}
```

**Update versions:**
```elixir
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:ex_doc, "~> 0.31", only: :dev, runtime: false},
{:excoveralls, "~> 0.18", only: [:dev, :test]}
```

**Remove:**
```elixir
{:typed_struct, "~> 0.3.0"}  # Replace with Zoi
```

### 1.2 Add Quality Alias

```elixir
defp aliases do
  [
    setup: ["deps.get", "git_hooks.install"],
    test: "test --exclude flaky",
    q: ["quality"],
    quality: [
      "format --check-formatted",
      "compile --warnings-as-errors",
      "credo --min-priority higher",
      "dialyzer"
    ]
  ]
end
```

### 1.3 Git Hooks Configuration

Create `config/dev.exs`:
```elixir
import Config

config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    commit_msg: [
      tasks: [
        {:cmd, "mix git_ops.check_message"}
      ]
    ],
    pre_commit: [
      tasks: [
        {:mix_task, :format, ["--check-formatted"]}
      ]
    ],
    pre_push: [
      tasks: [
        {:mix_task, :quality}
      ]
    ]
  ]
```

### 1.4 Test Coverage Configuration

```elixir
# In mix.exs project/0
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 90],
  export: "cov"
],
dialyzer: [
  plt_local_path: "priv/plts/project.plt",
  plt_core_path: "priv/plts/core.plt"
]
```

---

## Part 2: Error Handling with Splode

### 2.1 Create Jido.Chat.Error Module

**File:** `lib/jido_chat/error.ex`

```elixir
defmodule Jido.Chat.Error do
  @moduledoc """
  Unified error handling for Jido.Chat using Splode.
  
  Integrates with Jido.Error ecosystem for consistent cross-package error handling.
  
  ## Error Classes
  
  - `:invalid` - Validation errors, malformed messages, invalid participants
  - `:execution` - Runtime errors in room operations, message processing
  - `:routing` - Signal routing and bus errors
  - `:internal` - Unexpected failures
  """

  # Error class modules for Splode
  defmodule Invalid do
    @moduledoc "Invalid input error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule Routing do
    @moduledoc "Routing error class"
    use Splode.ErrorClass, class: :routing
  end

  defmodule Internal do
    @moduledoc "Internal error class"
    use Splode.ErrorClass, class: :internal
  end

  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution,
      routing: Routing,
      internal: Internal
    ],
    unknown_error: Jido.Error.Internal.UnknownError

  # Specific error types
  defmodule InvalidParticipantError do
    @moduledoc "Error for invalid participant definitions"
    defexception [:message, :participant_id, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid participant"),
        participant_id: Keyword.get(opts, :participant_id),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule InvalidMessageError do
    @moduledoc "Error for invalid message format"
    defexception [:message, :message_id, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Invalid message"),
        message_id: Keyword.get(opts, :message_id),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RoomNotFoundError do
    @moduledoc "Error when room doesn't exist"
    defexception [:message, :room_id, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Room not found"),
        room_id: Keyword.get(opts, :room_id),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule RoomFullError do
    @moduledoc "Error when room exceeds participant limit"
    defexception [:message, :room_id, :limit, :current_count, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Room is full"),
        room_id: Keyword.get(opts, :room_id),
        limit: Keyword.get(opts, :limit),
        current_count: Keyword.get(opts, :current_count),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  defmodule MessageTooLargeError do
    @moduledoc "Error when message exceeds size limit"
    defexception [:message, :size, :limit, :details]

    @impl true
    def exception(opts) do
      %__MODULE__{
        message: Keyword.get(opts, :message, "Message too large"),
        size: Keyword.get(opts, :size),
        limit: Keyword.get(opts, :limit),
        details: Keyword.get(opts, :details, %{})
      }
    end
  end

  # Convenience functions
  def invalid_participant(message, details \\ %{}) do
    InvalidParticipantError.exception(
      message: message,
      participant_id: details[:participant_id],
      details: details
    )
  end

  def invalid_message(message, details \\ %{}) do
    InvalidMessageError.exception(
      message: message,
      message_id: details[:message_id],
      details: details
    )
  end

  def room_not_found(room_id) do
    RoomNotFoundError.exception(
      message: "Room not found: #{room_id}",
      room_id: room_id
    )
  end

  def room_full(room_id, limit, current_count) do
    RoomFullError.exception(
      message: "Room #{room_id} is full (#{current_count}/#{limit})",
      room_id: room_id,
      limit: limit,
      current_count: current_count
    )
  end

  def message_too_large(size, limit) do
    MessageTooLargeError.exception(
      message: "Message size #{size} bytes exceeds limit of #{limit} bytes",
      size: size,
      limit: limit
    )
  end
end
```

### 2.2 Update Error Returns Throughout

**Pattern to apply everywhere:**
```elixir
# Old (TypedStruct validation failure)
{:error, "Invalid participant"}

# New (Splode error)
{:error, Jido.Chat.Error.invalid_participant("Missing required field", field: :id)}
```

---

## Part 3: Migrate Structs from TypedStruct to Zoi

### 3.1 Zoi Struct Pattern

Reference pattern from `jido_character`:

```elixir
defmodule MyStruct do
  @schema Zoi.struct(
    __MODULE__,
    %{
      required_field: Zoi.string(min_length: 1),
      optional_field: Zoi.string() |> Zoi.optional(),
      with_default: Zoi.integer() |> Zoi.default(0)
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, errors} -> raise ArgumentError, "Validation failed: #{inspect(errors)}"
    end
  end
end
```

### 3.2 Convert Jido.Chat.Participant

**Current (TypedStruct):**
```elixir
defmodule Jido.Chat.Participant do
  use TypedStruct

  typedstruct do
    field :id, String.t(), enforce: true
    field :type, atom(), enforce: true
    field :display_name, String.t()
    field :metadata, map(), default: %{}
  end
end
```

**New (Zoi):**
```elixir
defmodule Jido.Chat.Participant do
  @moduledoc """
  Represents a participant in a chat room (human or agent).
  
  Validated using Zoi for runtime type checking and coercion.
  """

  @schema Zoi.struct(
    __MODULE__,
    %{
      id: Zoi.string(min_length: 1, description: "Unique participant identifier"),
      type: Zoi.enum([:human, :agent], description: "Participant type"),
      display_name: Zoi.string(max_length: 100) |> Zoi.trim() |> Zoi.optional(),
      metadata: Zoi.map() |> Zoi.default(%{})
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Participant"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, [Zoi.Error.t()]}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, participant} -> {:ok, participant}
      {:error, errors} -> {:error, errors}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, participant} -> participant
      {:error, errors} -> 
        raise Jido.Chat.Error.invalid_participant("Validation failed", errors: errors)
    end
  end
end
```

### 3.3 Convert Jido.Chat.Message

**Add size limit and enhanced validation:**

```elixir
defmodule Jido.Chat.Message do
  @moduledoc """
  Represents a chat message with validation and size limits.
  
  ## Limits
  
  - Content: 10KB max
  - Metadata: 1KB max
  """

  @max_content_bytes 10_240  # 10KB
  @max_metadata_bytes 1_024   # 1KB

  @schema Zoi.struct(
    __MODULE__,
    %{
      id: Zoi.string(min_length: 1, description: "Unique message ID"),
      room_id: Zoi.string(min_length: 1, description: "Room identifier"),
      sender_id: Zoi.string(min_length: 1, description: "Participant ID of sender"),
      content: Zoi.string(description: "Message content"),
      type: Zoi.enum([:text, :system, :rich, :turn], description: "Message type") 
            |> Zoi.default(:text),
      metadata: Zoi.map() |> Zoi.default(%{}),
      timestamp: Zoi.datetime() |> Zoi.default(&DateTime.utc_now/0),
      thread_id: Zoi.string() |> Zoi.optional()
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, message} <- Zoi.parse(@schema, attrs),
         :ok <- validate_size(message) do
      {:ok, message}
    end
  end

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, message} -> message
      {:error, error} -> raise error
    end
  end

  defp validate_size(%__MODULE__{content: content, metadata: metadata}) do
    content_size = byte_size(content)
    metadata_size = byte_size(:erlang.term_to_binary(metadata))

    cond do
      content_size > @max_content_bytes ->
        {:error, Jido.Chat.Error.message_too_large(content_size, @max_content_bytes)}
      
      metadata_size > @max_metadata_bytes ->
        {:error, Jido.Chat.Error.message_too_large(metadata_size, @max_metadata_bytes)}
      
      true ->
        :ok
    end
  end
end
```

### 3.4 Convert Jido.Chat.Room.State

**Add participant limit enforcement:**

```elixir
defmodule Jido.Chat.Room.State do
  @moduledoc """
  Internal state for a chat room process.
  
  Enforces limits for resilient operation at scale.
  """

  @max_participants 1_000
  @max_messages 500

  @schema Zoi.struct(
    __MODULE__,
    %{
      room_id: Zoi.string(min_length: 1),
      name: Zoi.string() |> Zoi.optional(),
      bus: Zoi.atom(),
      participants: Zoi.array(Zoi.any()) |> Zoi.default([]),  # List of Participant.t()
      messages: Zoi.array(Zoi.any()) |> Zoi.default([]),      # List of Message.t()
      strategy_module: Zoi.atom(),
      strategy_state: Zoi.any() |> Zoi.default(nil),
      metadata: Zoi.map() |> Zoi.default(%{}),
      created_at: Zoi.datetime() |> Zoi.default(&DateTime.utc_now/0)
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
  def max_participants, do: @max_participants
  def max_messages, do: @max_messages

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, state} -> state
      {:error, errors} -> raise ArgumentError, "Invalid room state: #{inspect(errors)}"
    end
  end
end
```

---

## Part 4: Resilience & Scalability for 1000 Participants

### 4.1 Participant Limit Enforcement

**In `lib/jido_chat/room.ex`:**

```elixir
def handle_call({:join, participant}, _from, state) do
  participant_count = length(state.participants)
  max = Jido.Chat.Room.State.max_participants()

  if participant_count >= max do
    error = Jido.Chat.Error.room_full(state.room_id, max, participant_count)
    {:reply, {:error, error}, state}
  else
    # ... existing join logic
  end
end
```

### 4.2 Message History Limits

**Add circular buffer for messages:**

```elixir
defp add_message_to_state(state, message) do
  messages = [message | state.messages]
  max = Jido.Chat.Room.State.max_messages()
  
  messages = 
    if length(messages) > max do
      Enum.take(messages, max)  # Keep most recent N
    else
      messages
    end
  
  %{state | messages: messages}
end
```

### 4.3 Bus Subscription Optimization

**Per-room topics instead of wildcard:**

```elixir
# Current: Subscribe to all chat signals, filter in handle_info
Jido.Signal.Bus.subscribe(bus, "chat.*")

# Improved: Subscribe to room-specific topic
Jido.Signal.Bus.subscribe(bus, "chat.room.#{room_id}.*")

# Update signal subjects when publishing:
subject = "jido://chat/room/#{room_id}/message"
```

### 4.4 Backpressure & Rate Limiting (Optional - Phase 2)

**Add rate limiting per participant:**

```elixir
defmodule Jido.Chat.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for chat messages.
  
  Prevents spam and ensures fair resource usage.
  """
  
  use GenServer
  
  @default_bucket_size 10
  @default_refill_rate 1  # per second
  
  # ... implementation using ETS or GenServer state
end
```

---

## Part 5: Documentation & GENERIC_PACKAGE_QA Compliance

### 5.1 Update README.md

**Fix API drift - align examples with real API:**

```markdown
## Basic Usage

### Creating a Room

```elixir
# Start a chat room
{:ok, pid} = Jido.Chat.create_room("main-room", %{max_participants: 50})

# Access an existing room
case Jido.Chat.get_room("main-room") do
  {:ok, pid} -> pid
  {:error, error} -> # handle error
end
```

### Managing Participants

```elixir
# Create a participant
{:ok, alice} = Jido.Chat.Participant.new(%{
  id: "user123",
  type: :human,
  display_name: "Alice"
})

# Join room
:ok = Jido.Chat.join_room("main-room", alice)
```

### Sending Messages

```elixir
# Send a message
{:ok, msg} = Jido.Chat.send_message("main-room", "user123", "Hello!")
```
```

### 5.2 Create usage-rules.md

**For LLM agent instructions:**

```markdown
# Jido.Chat Usage Rules

## When to Use

Use Jido.Chat when you need:
- Real-time chat rooms with human and AI agent participants
- Event-driven message processing via Jido.Signal.Bus
- Turn-based or free-form conversation strategies
- Integration with Jido agent workflows

## Key Patterns

### Participant Management
- Always validate participants with `Participant.new/1` before joining
- Check room capacity before joining (1000 participant limit)
- Use `:human` or `:agent` types

### Message Handling
- Messages are limited to 10KB content, 1KB metadata
- Use appropriate message types: `:text`, `:system`, `:rich`, `:turn`
- Messages are automatically assigned IDs and timestamps

### Error Handling
- All functions return `{:ok, result}` or `{:error, Splode.Error.t()}`
- Use `Jido.Chat.Error.*` for chat-specific errors
- Errors integrate with Jido.Error ecosystem

## Examples

[... practical examples ...]
```

### 5.3 Update AGENTS.md

**Add architecture details and constraints:**

```markdown
# AGENTS.md - Jido.Chat Development Guide

## Architecture

### Signal Bus Integration
- All rooms subscribe to `chat.room.#{room_id}.*` topics
- Messages publish to `jido://chat/room/#{room_id}/message`
- Bus: `Jido.Chat.Bus` (named bus started by Application)

### Scalability Limits
- **Participants per room:** 1000 (configurable via Room.State)
- **Message history:** 500 messages (circular buffer)
- **Message size:** 10KB content + 1KB metadata

### Schema Validation
- Uses Zoi for all struct validation (not TypedStruct)
- Runtime validation with descriptive errors
- All structs expose `new/1` and `new!/1`

## Quality Commands

```bash
mix quality      # Run all checks
mix test         # Tests with >90% coverage
mix docs         # Generate documentation
```

## Common Patterns

[... development patterns ...]
```

### 5.4 Add CHANGELOG.md Entry

```markdown
# Changelog

## [0.6.0] - Unreleased

### Breaking Changes
- Replaced TypedStruct with Zoi for runtime validation
- Error handling now uses Splode errors instead of plain tuples
- API changes to align with actual implementation (see README)

### Added
- Participant limit enforcement (1000 per room)
- Message size limits (10KB content, 1KB metadata)
- Message history limit (500 messages, circular buffer)
- Structured error types via Jido.Chat.Error
- Quality tooling: git_hooks, git_ops, improved CI

### Improved
- Bus subscription optimized to per-room topics
- Documentation aligned with actual API
- Test coverage increased to >90%
- GENERIC_PACKAGE_QA compliance
```

---

## Part 6: Testing & Validation

### 6.1 Add Property Tests for Limits

**File:** `test/jido_chat/room_limits_test.exs`

```elixir
defmodule Jido.Chat.RoomLimitsTest do
  use ExUnit.Case
  use Mimic
  
  alias Jido.Chat.{Room, Participant, Message}
  
  describe "participant limits" do
    test "enforces max participants" do
      {:ok, room_pid} = Room.Supervisor.start_room(%{
        name: "test-room",
        room_id: "test-1"
      })
      
      max = Room.State.max_participants()
      
      # Join max participants - should succeed
      for i <- 1..max do
        {:ok, p} = Participant.new(%{id: "user#{i}", type: :human})
        assert :ok = GenServer.call(room_pid, {:join, p})
      end
      
      # Try to join one more - should fail
      {:ok, extra} = Participant.new(%{id: "user#{max + 1}", type: :human})
      assert {:error, %Jido.Chat.Error.RoomFullError{}} = 
        GenServer.call(room_pid, {:join, extra})
    end
  end
  
  describe "message limits" do
    test "enforces max message size" do
      large_content = String.duplicate("a", 11_000)
      
      assert {:error, %Jido.Chat.Error.MessageTooLargeError{}} = 
        Message.new(%{
          id: "msg1",
          room_id: "room1",
          sender_id: "user1",
          content: large_content
        })
    end
    
    test "enforces message history limit" do
      # ... test circular buffer behavior
    end
  end
end
```

### 6.2 Coverage Requirements

**In mix.exs:**
```elixir
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 90],
  export: "cov",
  ignore_modules: [
    ~r/^Jido.ChatTest\./,  # Ignore test support
  ]
]
```

### 6.3 Integration Tests

**Test full workflow with 1000 participants:**

```elixir
@tag :slow
test "handles 1000 participants joining and sending messages" do
  {:ok, room_pid} = create_test_room()
  
  # Join 1000 participants
  participants = for i <- 1..1000 do
    {:ok, p} = Participant.new(%{id: "user#{i}", type: :human})
    assert :ok = GenServer.call(room_pid, {:join, p})
    p
  end
  
  # Each sends a message
  for p <- Enum.take_random(participants, 100) do
    {:ok, _msg} = send_message(room_pid, p.id, "Hello")
  end
  
  # Verify room state
  state = :sys.get_state(room_pid)
  assert length(state.participants) == 1000
  assert length(state.messages) <= 500  # Respects limit
end
```

---

## Part 7: GitHub Actions & CI

### 7.1 Update .github/workflows/ci.yml

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: "28"
          elixir-version: "1.19"
      - run: mix deps.get
      - run: mix quality

  test:
    name: Test (Elixir ${{ matrix.elixir }} / OTP ${{ matrix.otp }})
    runs-on: ubuntu-latest
    strategy:
      matrix:
        otp: ["27", "28"]
        elixir: ["1.18", "1.19"]
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: ${{ matrix.otp }}
          elixir-version: ${{ matrix.elixir }}
      - run: mix deps.get
      - run: mix test
      - run: mix coveralls.github
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 7.2 Add Release Workflow

**`.github/workflows/release.yml`:**

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

jobs:
  publish:
    name: Publish to Hex
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: "28"
          elixir-version: "1.19"
      - run: mix deps.get
      - run: mix quality
      - run: mix test
      - run: mix hex.publish --yes
        env:
          HEX_API_KEY: ${{ secrets.HEX_API_KEY }}
```

---

## Part 8: Migration Checklist

### Phase 1: Foundation (High Priority)
- [ ] Add zoi, splode, git_hooks, git_ops dependencies
- [ ] Create `Jido.Chat.Error` module with Splode errors
- [ ] Create `config/dev.exs` with git hooks
- [ ] Add `quality` alias to mix.exs
- [ ] Update test coverage config (90% threshold)
- [ ] Run `mix quality` and fix any issues

### Phase 2: Struct Migration (High Priority)
- [ ] Convert `Jido.Chat.Participant` to Zoi
- [ ] Convert `Jido.Chat.Message` to Zoi (add size limits)
- [ ] Convert `Jido.Chat.Room.State` to Zoi (add participant/message limits)
- [ ] Convert `Jido.Chat.ParticipantRef` to Zoi
- [ ] Update all call sites to use `new/1` instead of direct struct creation
- [ ] Remove `typed_struct` dependency

### Phase 3: Error Handling (High Priority)
- [ ] Replace all `{:error, string}` with Splode errors
- [ ] Update `Room` GenServer to return proper errors
- [ ] Update public API functions in `Jido.Chat` module
- [ ] Add error handling tests

### Phase 4: Limits & Resilience (Medium Priority)
- [ ] Add participant limit enforcement in `Room.handle_call({:join, _})`
- [ ] Add message history circular buffer
- [ ] Add message size validation
- [ ] Optimize bus subscription to per-room topics
- [ ] Update signal subjects for targeted routing

### Phase 5: Documentation (Medium Priority)
- [ ] Update README.md with accurate API examples
- [ ] Create `usage-rules.md` for LLMs
- [ ] Update `AGENTS.md` with architecture details and limits
- [ ] Update `guides/architecture.md` to reflect Zoi/Splode patterns
- [ ] Add CHANGELOG.md entry for 0.6.0

### Phase 6: Testing (Medium Priority)
- [ ] Add property tests for participant limits
- [ ] Add property tests for message limits
- [ ] Add integration test with 1000 participants
- [ ] Increase coverage to >90%
- [ ] Add benchmark tests for scalability

### Phase 7: CI & Tooling (Low Priority)
- [ ] Update GitHub Actions workflows
- [ ] Add release workflow
- [ ] Configure Dialyzer PLT paths
- [ ] Set up git commit hooks
- [ ] Verify `mix git_ops.release` works

### Phase 8: Polish (Low Priority)
- [ ] Add .credo.exs configuration
- [ ] Update .formatter.exs if needed
- [ ] Add CONTRIBUTING.md
- [ ] Review and update all moduledocs
- [ ] Generate docs with `mix docs` and review

---

## Part 9: Optional Enhancements (Phase 2)

These can be added after initial modernization:

### 9.1 Persistence Layer
- [ ] Add `Jido.Chat.Persistence` behaviour
- [ ] Implement ETS adapter for message history
- [ ] Implement optional database adapter (Ecto)
- [ ] Add message archiving for old messages

### 9.2 Performance Monitoring
- [ ] Add Telemetry events for room operations
- [ ] Track participant count metrics
- [ ] Track message throughput
- [ ] Add health check endpoint

### 9.3 Advanced Rate Limiting
- [ ] Implement `Jido.Chat.RateLimiter` GenServer
- [ ] Add per-participant message rate limits
- [ ] Add burst allowance with token bucket
- [ ] Add backpressure signals when limits exceeded

### 9.4 Message Threading
- [ ] Implement thread storage in Room.State
- [ ] Add `get_thread/2` function
- [ ] Add thread depth limits
- [ ] Update Promptable for thread context

---

## Questions for Review

1. **Participant limit:** Is 1000 the right max, or should it be configurable per room?
2. **Message history:** Should we persist older messages or just keep in-memory circular buffer?
3. **Bus topics:** Should we use `chat.room.#{room_id}.*` or keep wildcard `chat.*`?
4. **Error strategy:** Should we fail fast with Splode errors or provide fallback behaviors?
5. **Breaking changes:** Since unreleased, are we okay breaking the current API completely?
6. **Phase 2 features:** Which optional enhancements (persistence, rate limiting) should be prioritized?

---

## Estimated Effort

| Phase | Effort | Duration |
|-------|--------|----------|
| Phase 1: Foundation | S | 1-2h |
| Phase 2: Struct Migration | M | 3-4h |
| Phase 3: Error Handling | M | 2-3h |
| Phase 4: Limits & Resilience | M | 3-4h |
| Phase 5: Documentation | S-M | 2-3h |
| Phase 6: Testing | M | 4-5h |
| Phase 7: CI & Tooling | S | 1-2h |
| Phase 8: Polish | S | 1-2h |
| **Total Core** | **L** | **17-25h** |
| Phase 9: Optional | L | 10-15h |

**Recommendation:** Execute phases 1-8 as a single modernization effort, defer phase 9 based on real-world usage.

---

## Success Criteria

- [ ] `mix quality` passes with no warnings
- [ ] `mix test` passes with >90% coverage
- [ ] `mix docs` builds without warnings
- [ ] README examples match actual API
- [ ] All structs use Zoi (zero TypedStruct)
- [ ] All errors use Splode (zero plain tuples)
- [ ] Room handles 1000 participants without errors
- [ ] Message history respects 500 message limit
- [ ] Per-room bus topics reduce fanout
- [ ] Git hooks enforce quality on commits/pushes
- [ ] CI runs quality checks and tests on all PRs
