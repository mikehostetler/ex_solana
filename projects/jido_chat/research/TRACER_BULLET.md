# JIDO_CHAT_V2: Tracer Bullet Implementation Guide

## Overview

This guide shows how to build a **minimal working version** of JIDO_CHAT_V2 that demonstrates the core concepts end-to-end, using:
- `Jido.Signal.Bus` for all messaging
- `Jido.Signal.Journal` for persistence
- Signal-driven architecture throughout

**Goal**: Get a single message flowing from a test channel → room → agent → back to channel, all via signals.

---

## Architecture: Minimal Version

```
TestChannel (emits signals)
    ↓ signal: "chat.message.received"
    ↓
RoomServer (subscribes, processes)
    ↓ signal: "chat.agent.request"
    ↓
AgentServer (subscribes, processes)
    ↓ signal: "chat.agent.response"
    ↓
RoomServer (receives response)
    ↓ signal: "chat.message.send"
    ↓
TestChannel (subscribes, sends)
```

**Key Principle**: Everything communicates via `Jido.Signal.Bus`. No direct GenServer calls except within the same component.

---

## Step 1: Custom Signal Definitions

Define each signal type as its own module using `use Jido.Signal`.

```elixir
# lib/jido_chat/signals/message_received.ex
defmodule Jido.Chat.Signals.MessageReceived do
  @moduledoc """
  Signal emitted when a message is received from a channel.
  """
  
  use Jido.Signal,
    type: "chat.message.received",
    default_source: "/jido_chat/channel",
    schema: [
      room_id: [type: :string, required: true],
      from: [type: :string, required: true],
      text: [type: :string, required: true]
    ]
end

# lib/jido_chat/signals/agent_request.ex
defmodule Jido.Chat.Signals.AgentRequest do
  @moduledoc """
  Signal emitted when a room requests agent processing.
  """
  
  use Jido.Signal,
    type: "chat.agent.request",
    default_source: "/jido_chat/room",
    schema: [
      room_id: [type: :string, required: true],
      message: [type: :map, required: true],
      history: [type: {:list, :map}, required: false, default: []]
    ]
end

# lib/jido_chat/signals/agent_response.ex
defmodule Jido.Chat.Signals.AgentResponse do
  @moduledoc """
  Signal emitted when agent completes processing.
  """
  
  use Jido.Signal,
    type: "chat.agent.response",
    default_source: "/jido_chat/agent",
    schema: [
      room_id: [type: :string, required: true],
      text: [type: :string, required: true],
      reply_to: [type: :string, required: true]
    ]
end

# lib/jido_chat/signals/message_send.ex
defmodule Jido.Chat.Signals.MessageSend do
  @moduledoc """
  Signal emitted when a message should be sent to a channel.
  """
  
  use Jido.Signal,
    type: "chat.message.send",
    default_source: "/jido_chat/room",
    schema: [
      room_id: [type: :string, required: true],
      to: [type: :string, required: true],
      text: [type: :string, required: true]
    ]
end
```

---

## Step 2: Minimal Domain Model

Start with the absolute minimum structs needed.

```elixir
# lib/jido_chat/message.ex
defmodule Jido.Chat.Message do
  @moduledoc """
  Minimal message representation.
  """
  
  use Zoi.Struct
  
  @schema Zoi.struct(
    id: {:string, required: true},
    room_id: {:string, required: true},
    from: {:string, required: true},      # Participant ID
    role: {:enum, values: [:user, :assistant, :system], required: true},
    text: {:string, required: true},
    timestamp: {:datetime, required: true}
  )
  
  def new(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Util.generate_id())
    |> Map.put_new(:timestamp, DateTime.utc_now())
    |> Zoi.validate(__MODULE__)
  end
end
```

```elixir
# lib/jido_chat/room.ex
defmodule Jido.Chat.Room do
  @moduledoc """
  Minimal room state.
  """
  
  use Zoi.Struct
  
  @schema Zoi.struct(
    id: {:string, required: true},
    messages: {:list, item_type: :map, default: []},
    participant_ids: {:list, item_type: :string, default: []}
  )
  
  def new(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Util.generate_id())
    |> Zoi.validate(__MODULE__)
  end
  
  def add_message(room, message) do
    %{room | messages: [message | room.messages]}
  end
end
```

---

## Step 3: Room Server (Signal-Driven)

GenServer that:
1. Subscribes to `chat.message.received`
2. Stores messages
3. Emits `chat.agent.request` for agent processing
4. Subscribes to `chat.agent.response`
5. Emits `chat.message.send` to channel

```elixir
# lib/jido_chat/room_server.ex
defmodule Jido.Chat.RoomServer do
  use GenServer
  require Logger
  
  alias Jido.Chat.{Room, Message, Signals}
  
  # Client API
  
  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end
  
  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    bus = Keyword.get(opts, :bus, Jido.Signal.Bus)
    
    # Create initial room
    {:ok, room} = Room.new(%{id: room_id})
    
    # Subscribe to signal types
    {:ok, _} = Jido.Signal.Bus.subscribe(bus, Jido.Chat.Signals.MessageReceived.type())
    {:ok, _} = Jido.Signal.Bus.subscribe(bus, Jido.Chat.Signals.AgentResponse.type())
    
    state = %{
      room: room,
      bus: bus
    }
    
    Logger.info("RoomServer started for room: #{room_id}")
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.room, state}
  end
  
  @impl true
  def handle_info({:signal, signal}, state) do
    case signal.type do
      type when type == Jido.Chat.Signals.MessageReceived.type() ->
        handle_message_received(signal, state)
      
      type when type == Jido.Chat.Signals.AgentResponse.type() ->
        handle_agent_response(signal, state)
      
      _ ->
        {:noreply, state}
    end
  end
  
  # Private Functions
  
  defp handle_message_received(signal, state) do
    # Signal data is validated by the custom signal definition
    %{room_id: room_id, from: from, text: text} = signal.data
    
    # Only process if for this room
    if room_id == state.room.id do
      Logger.info("Room #{state.room.id} received message: #{text}")
      
      # Create message
      {:ok, message} = Message.new(%{
        room_id: state.room.id,
        from: from,
        role: :user,
        text: text
      })
      
      # Store message
      updated_room = Room.add_message(state.room, message)
      
      # Persist to journal
      persist_message(message, state.bus)
      
      # Request agent response
      {:ok, request_signal} = Jido.Chat.Signals.AgentRequest.new(%{
        room_id: state.room.id,
        message: message,
        history: Enum.take(updated_room.messages, 10)  # Last 10 messages
      })
      
      Jido.Signal.Bus.publish(state.bus, [request_signal])
      
      {:noreply, %{state | room: updated_room}}
    else
      {:noreply, state}
    end
  end
  
  defp handle_agent_response(signal, state) do
    # Signal data is validated by the custom signal definition
    %{room_id: room_id, text: text, reply_to: reply_to} = signal.data
    
    if room_id == state.room.id do
      Logger.info("Room #{state.room.id} received agent response: #{text}")
      
      # Create assistant message
      {:ok, message} = Message.new(%{
        room_id: state.room.id,
        from: "agent",
        role: :assistant,
        text: text
      })
      
      # Store message
      updated_room = Room.add_message(state.room, message)
      
      # Persist to journal
      persist_message(message, state.bus)
      
      # Send message to channel
      {:ok, send_signal} = Jido.Chat.Signals.MessageSend.new(%{
        room_id: state.room.id,
        to: reply_to,
        text: text
      })
      
      Jido.Signal.Bus.publish(state.bus, [send_signal])
      
      {:noreply, %{state | room: updated_room}}
    else
      {:noreply, state}
    end
  end
  
  defp persist_message(message, bus) do
    # Store in journal for persistence
    event = %Jido.Signal{
      type: "chat.message.stored",
      source: "room_server",
      payload: message,
      timestamp: DateTime.utc_now()
    }
    
    Jido.Signal.Journal.append(bus, event)
  end
  
  defp via_tuple(room_id) do
    {:via, Registry, {Jido.Chat.Registry, {:room, room_id}}}
  end
end
```

---

## Step 4: Agent Server (Simple Echo)

Start with the simplest possible agent - just echo back.

```elixir
# lib/jido_chat/agent_server.ex
defmodule Jido.Chat.AgentServer do
  use GenServer
  require Logger
  
  alias Jido.Chat.Signals
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    bus = Keyword.get(opts, :bus, Jido.Signal.Bus)
    
    # Subscribe to agent request signal type
    {:ok, _} = Jido.Signal.Bus.subscribe(bus, Signals.AgentRequest.type())
    
    Logger.info("AgentServer started")
    {:ok, %{bus: bus}}
  end
  
  @impl true
  def handle_info({:signal, signal}, state) 
      when signal.type == "chat.agent.request" do
    # Signal data is validated by the custom signal definition
    %{room_id: room_id, message: message} = signal.data
    
    Logger.info("Agent processing request for room: #{room_id}")
    
    # Simple echo response (replace with ReqLLM later)
    response_text = "Echo: #{message.text}"
    
    # Emit response signal
    {:ok, response_signal} = Signals.AgentResponse.new(%{
      room_id: room_id,
      text: response_text,
      reply_to: message.from
    })
    
    Jido.Signal.Bus.publish(state.bus, [response_signal])
    
    {:noreply, state}
  end
end
```

---

## Step 5: Test Channel (Signal Emitter/Receiver)

A minimal channel that emits and receives signals for testing.

```elixir
# lib/jido_chat/test_channel.ex
defmodule Jido.Chat.TestChannel do
  use GenServer
  require Logger
  
  alias Jido.Chat.Signals
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def send_message(room_id, from, text) do
    GenServer.call(__MODULE__, {:send_message, room_id, from, text})
  end
  
  def get_received_messages do
    GenServer.call(__MODULE__, :get_received_messages)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    bus = Keyword.get(opts, :bus, Jido.Signal.Bus)
    
    # Subscribe to outbound message signal type
    {:ok, _} = Jido.Signal.Bus.subscribe(bus, Signals.MessageSend.type())
    
    Logger.info("TestChannel started")
    {:ok, %{bus: bus, received: []}}
  end
  
  @impl true
  def handle_call({:send_message, room_id, from, text}, _from, state) do
    Logger.info("TestChannel sending message from #{from}: #{text}")
    
    # Emit message received signal (validated by custom signal)
    {:ok, signal} = Signals.MessageReceived.new(%{
      room_id: room_id,
      from: from,
      text: text
    })
    
    Jido.Signal.Bus.publish(state.bus, [signal])
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call(:get_received_messages, _from, state) do
    {:reply, state.received, state}
  end
  
  @impl true
  def handle_info({:signal, signal}, state) 
      when signal.type == "chat.message.send" do
    # Signal data is validated by the custom signal definition
    %{text: text} = signal.data
    
    Logger.info("TestChannel received outbound message: #{text}")
    
    # Store received message data
    updated_received = [signal.data | state.received]
    
    {:noreply, %{state | received: updated_received}}
  end
end
```

---

## Step 6: Application Supervisor

Wire everything together.

```elixir
# lib/jido_chat/application.ex
defmodule Jido.Chat.Application do
  use Application
  
  @impl true
  def start(_type, _args) do
    children = [
      # Registry for room lookup
      {Registry, keys: :unique, name: Jido.Chat.Registry},
      
      # Signal bus (if not already started globally)
      {Jido.Signal.Bus, name: Jido.Signal.Bus},
      
      # Core servers
      Jido.Chat.AgentServer,
      Jido.Chat.TestChannel,
      
      # Dynamic supervisor for rooms
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Chat.RoomSupervisor}
    ]
    
    opts = [strategy: :one_for_one, name: Jido.Chat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

---

## Step 7: Helper Module for Starting Rooms

```elixir
# lib/jido_chat.ex
defmodule Jido.Chat do
  @moduledoc """
  Minimal API for JIDO_CHAT tracer bullet.
  """
  
  alias Jido.Chat.{RoomServer, TestChannel}
  
  @doc """
  Start a new room.
  """
  def start_room(room_id) do
    child_spec = {RoomServer, room_id: room_id, bus: Jido.Signal.Bus}
    DynamicSupervisor.start_child(Jido.Chat.RoomSupervisor, child_spec)
  end
  
  @doc """
  Send a message to a room (via test channel).
  """
  def send_message(room_id, from, text) do
    TestChannel.send_message(room_id, from, text)
  end
  
  @doc """
  Get room state.
  """
  def get_room(room_id) do
    RoomServer.get_state(room_id)
  end
  
  @doc """
  Get messages received by test channel.
  """
  def get_channel_messages do
    TestChannel.get_received_messages()
  end
end
```

---

## Step 8: End-to-End Test

```elixir
# test/jido_chat_test.exs
defmodule Jido.ChatTest do
  use ExUnit.Case
  
  test "end-to-end message flow via signals" do
    # Start a room
    room_id = "test_room_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Jido.Chat.start_room(room_id)
    
    # Give processes time to subscribe
    Process.sleep(100)
    
    # Send a message via test channel
    :ok = Jido.Chat.send_message(room_id, "alice", "Hello, agent!")
    
    # Wait for signal processing
    Process.sleep(500)
    
    # Check room received and stored message
    room = Jido.Chat.get_room(room_id)
    assert length(room.messages) == 2  # User message + agent response
    
    user_msg = Enum.find(room.messages, &(&1.role == :user))
    assert user_msg.text == "Hello, agent!"
    assert user_msg.from == "alice"
    
    agent_msg = Enum.find(room.messages, &(&1.role == :assistant))
    assert agent_msg.text == "Echo: Hello, agent!"
    
    # Check agent response was sent to channel
    channel_messages = Jido.Chat.get_channel_messages()
    assert length(channel_messages) > 0
    
    sent_msg = List.first(channel_messages)
    assert sent_msg.text == "Echo: Hello, agent!"
  end
end
```

---

## Step 9: Persistence with Signal.Journal

Integrate signal journal for message persistence.

```elixir
# lib/jido_chat/journal.ex
defmodule Jido.Chat.Journal do
  @moduledoc """
  Persistence layer using Jido.Signal.Journal.
  """
  
  @journal_name :jido_chat_journal
  
  def start_link(_opts \\ []) do
    Jido.Signal.Journal.start_link(name: @journal_name)
  end
  
  def append(signal) do
    Jido.Signal.Journal.append(@journal_name, signal)
  end
  
  def replay_room(room_id) do
    # Get all messages for a room from journal
    Jido.Signal.Journal.stream(@journal_name)
    |> Stream.filter(fn signal ->
      signal.type == "chat.message.stored" and 
      signal.payload.room_id == room_id
    end)
    |> Enum.to_list()
  end
  
  def rebuild_room_state(room_id) do
    # Rebuild room state from journal
    messages = replay_room(room_id)
    |> Enum.map(& &1.payload)
    |> Enum.reverse()
    
    Jido.Chat.Room.new(%{
      id: room_id,
      messages: messages,
      participant_ids: Enum.uniq(Enum.map(messages, & &1.from))
    })
  end
end
```

**Update RoomServer to use Journal**:

```elixir
defp persist_message(message, _bus) do
  event = %Jido.Signal{
    type: "chat.message.stored",
    source: "room_server",
    payload: message,
    timestamp: DateTime.utc_now()
  }
  
  Jido.Chat.Journal.append(event)
end
```

---

## Step 10: Running the Tracer Bullet

### Start in IEx

```elixir
# Start application
iex -S mix

# Start a room
{:ok, _pid} = Jido.Chat.start_room("room1")

# Send a message
Jido.Chat.send_message("room1", "alice", "Hello!")

# Check room state
room = Jido.Chat.get_room("room1")
IO.inspect(room.messages)

# Check channel received response
Jido.Chat.get_channel_messages()
```

### Expected Output

```
[info] RoomServer started for room: room1
[info] TestChannel sending message from alice: Hello!
[info] Room room1 received message: Hello!
[info] Agent processing request for room: room1
[info] Room room1 received agent response: Echo: Hello!
[info] TestChannel received outbound message: Echo: Hello!

# room.messages
[
  %Jido.Chat.Message{
    id: "msg_123",
    room_id: "room1",
    from: "agent",
    role: :assistant,
    text: "Echo: Hello!",
    timestamp: ~U[2025-12-23 ...]
  },
  %Jido.Chat.Message{
    id: "msg_456",
    room_id: "room1",
    from: "alice",
    role: :user,
    text: "Hello!",
    timestamp: ~U[2025-12-23 ...]
  }
]
```

---

## Growing the Tracer Bullet

### Phase 1: Real Channel Integration

Replace `TestChannel` with `WhatsAppChannel`:

```elixir
defmodule Jido.Chat.Channel.WhatsApp do
  use GenServer
  
  def init(opts) do
    # Connect to Evolution API
    # Subscribe to chat.message.send
    # Setup webhook receiver
  end
  
  def handle_info({:webhook, payload}, state) do
    # Emit chat.message.received signal
  end
  
  def handle_info({:signal, %{type: "chat.message.send"}}, state) do
    # Send via Evolution API
  end
end
```

### Phase 2: Real Agent (ReqLLM)

Replace echo agent with ReqLLM:

```elixir
defmodule Jido.Chat.AgentServer do
  def handle_info({:signal, %{type: "chat.agent.request", payload: p}}, state) do
    # Build ReqLLM context
    req = %ReqLLM.Request{
      messages: format_history(p.history) ++ [
        %{role: :user, content: p.message.text}
      ],
      model: "gpt-4"
    }
    
    # Call LLM
    {:ok, response} = ReqLLM.chat(req)
    
    # Emit response signal
    response_signal = Signals.build(
      Signals.agent_response(),
      %{room_id: p.room_id, text: response.message.content, reply_to: p.message.from}
    )
    
    Jido.Signal.Bus.publish(state.bus, [response_signal])
    {:noreply, state}
  end
end
```

### Phase 3: Multi-Instance Support

Add instance layer:

```elixir
defmodule Jido.Chat.InstanceServer do
  def init(opts) do
    # Subscribe to chat.message.received.{instance_id}
    # Route to appropriate rooms
  end
end
```

### Phase 4: Jido.Character Integration

```elixir
defmodule Jido.Chat.AgentServer do
  def handle_info({:signal, payload}, state) do
    # Get character for room
    character = Jido.Character.get(payload.character_id)
    
    # Build context with character
    req = ContextBuilder.build(payload.history, character)
    
    # ... rest of agent logic
  end
end
```

### Phase 5: Jido.Action as Tools

```elixir
defmodule Jido.Chat.AgentServer do
  def handle_info({:signal, payload}, state) do
    # Build tools from character.available_actions
    tools = Enum.map(character.available_actions, &action_to_tool/1)
    
    req = %ReqLLM.Request{
      messages: [...],
      tools: tools
    }
    
    # If LLM calls tool, emit signal
    case response.message.tool_calls do
      nil -> emit_response(...)
      calls -> emit_tool_execution_request(calls, ...)
    end
  end
end
```

---

## Signal Flow Diagram

```
┌─────────────────┐
│  TestChannel    │
└────────┬────────┘
         │ emit: chat.message.received
         ↓
┌─────────────────┐
│   RoomServer    │◄─────┐
└────────┬────────┘      │
         │ emit: chat.agent.request
         ↓                │
┌─────────────────┐      │
│  AgentServer    │      │
└────────┬────────┘      │
         │ emit: chat.agent.response
         └───────────────┘
         │ (received by RoomServer)
         │ emit: chat.message.send
         ↓
┌─────────────────┐
│  TestChannel    │
└─────────────────┘
```

---

## Key Principles

1. **Everything is a signal** - No direct GenServer calls between components
2. **Subscribe, don't poll** - Components subscribe to relevant signal topics
3. **Emit and forget** - Publishers don't wait for subscribers
4. **Journal for persistence** - All important events go to Signal.Journal
5. **Replay for recovery** - Rebuild state from journal on restart

---

## Checklist: Tracer Bullet Complete

- [ ] Signal definitions created
- [ ] Minimal Message and Room structs with Zoi
- [ ] RoomServer subscribes and emits signals
- [ ] AgentServer (echo) responds via signals
- [ ] TestChannel emits/receives signals
- [ ] Application supervisor wires everything
- [ ] End-to-end test passes
- [ ] Journal persistence integrated
- [ ] IEx demo works

**Once working**: Incrementally replace TestChannel with real channels, echo agent with ReqLLM, and expand domain model.

---

## Next Steps After Tracer Bullet

1. **Add WhatsApp channel** (replace TestChannel)
2. **Add ReqLLM agent** (replace echo)
3. **Add Jido.Character** for personalities
4. **Add Jido.Action** as tools
5. **Add InstanceServer** for multi-tenancy
6. **Add Router** for pattern matching
7. **Add streaming support**
8. **Add more channels** (Slack, Discord)

**The tracer bullet proves the architecture works - then grow it organically!**
