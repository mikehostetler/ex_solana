# JIDO_CHAT_V2: Multi-Tenant Conversation Fabric for AI Agents

## Executive Summary

**JIDO_CHAT_V2** is the **conversation fabric** that makes Jido agents accessible to humans across any messaging platform. It acts as a multi-tenant, multi-channel messaging broker that:

- **Normalizes** interactions across WhatsApp, Slack, Discord, SMS, and any future platform
- **Maps** participant messages to rich `ReqLLM` contexts for LLM submissions
- **Integrates** `Jido.Character` personalities for agent personas
- **Orchestrates** multi-party conversations with humans, AI agents, and integrations
- **Builds** on the Jido ecosystem (`jido_action`, `jido_signal`, `jido`, etc.)

**This is where the puzzle fits together** - the interface layer between Jido's agent intelligence and real-world messaging platforms.

---

## Table of Contents

1. [Vision & Positioning](#vision--positioning)
2. [Architecture Overview](#architecture-overview)
3. [Core Domain Model](#core-domain-model)
4. [Six-Layer Architecture](#six-layer-architecture)
5. [Integration with Jido Ecosystem](#integration-with-jido-ecosystem)
6. [Multi-Tenancy & Isolation](#multi-tenancy--isolation)
7. [ReqLLM Context Building](#reqllm-context-building)
8. [Signal-Driven Events](#signal-driven-events)
9. [Implementation Strategy](#implementation-strategy)
10. [Research Areas](#research-areas)

---

## Vision & Positioning

### What Problem Does This Solve?

**Current State**: 
- Building conversational AI agents requires platform-specific code for each messaging channel
- Agents need rich context (history, participants, personalities) to respond intelligently
- Multi-tenant deployments require instance isolation and configuration management
- Conversation orchestration (turn-taking, multi-party, threading) is complex

**JIDO_CHAT_V2 Solution**:
- **Single abstraction** for all messaging platforms (agents never see "Slack vs WhatsApp")
- **Rich context builder** that automatically constructs ReqLLM requests with full conversation state
- **Multi-tenant instances** with per-instance channel, agent, and character configuration
- **Event-driven architecture** via `jido_signal` for extensibility and observability

### Where It Fits in the Jido Ecosystem

```
┌─────────────────────────────────────────────────────────────────┐
│                    Human Users (Any Platform)                   │
│          WhatsApp │ Slack │ Discord │ SMS │ Web Chat           │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                      JIDO_CHAT_V2                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Channel    │  │   Instance   │  │     Room     │         │
│  │   Adapters   │→ │   Manager    │→ │   Servers    │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Jido Agent Runtime                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   ReqLLM     │  │   Character  │  │   Actions    │         │
│  │   Context    │→ │   Personas   │→ │   (Tools)    │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└────────────────────────────┬────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                      LLM Providers                              │
│          OpenAI │ Anthropic │ Hive │ Local Models              │
└─────────────────────────────────────────────────────────────────┘
```

**Key Principle**: JIDO_CHAT_V2 is the **normalization and orchestration layer**, not the intelligence. The intelligence lives in the agent runtime (Jido + ReqLLM + Actions).

---

## Architecture Overview

### Six-Layer Architecture

```
Layer 6: Multi-Tenant APIs & Admin Surfaces
    │ Phoenix controllers, webhooks, management APIs
    ↓
Layer 5: Signals & Events (jido_signal)
    │ Observability, extensibility, ecosystem integration
    ↓
Layer 4: Agent Gateway (ReqLLM + Jido.Character + Actions)
    │ Context building, LLM interaction, tool orchestration
    ↓
Layer 3: Conversation & Routing (Rooms, Middleware)
    │ Multi-party orchestration, turn strategies, routing
    ↓
Layer 2: Channel Normalization (Edge)
    │ Platform-specific → normalized message model
    ↓
Layer 1: Core Domain Model
    │ Instances, Rooms, Participants, Messages
```

### Process Supervision Tree

```
Jido.Chat.V2.Application.Supervisor
    ├─── Registry (InstanceRegistry)
    ├─── Registry (RoomRegistry)
    ├─── DynamicSupervisor (InstanceSupervisor)
    │       └─── InstanceServer (per tenant instance)
    │               ├─── Channel adapter state
    │               └─── Routes to RoomServers
    ├─── DynamicSupervisor (RoomSupervisor)
    │       └─── RoomServer (per conversation room)
    │               ├─── Participant list
    │               ├─── Message history
    │               └─── Turn strategy
    ├─── AgentGateway (GenServer pool or singleton)
    └─── Phoenix.PubSub (Jido.Signal.Bus integration)
```

---

## Core Domain Model

### Instance (Tenant Configuration)

```elixir
defmodule Jido.Chat.V2.Instance do
  @moduledoc """
  Represents a multi-tenant chat instance with isolated configuration.
  
  One instance = one tenant's connection to one messaging platform,
  routing to one agent backend with specific configuration.
  """
  
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},
    name: {:string, required: true},
    tenant_id: {:string, required: true},
    
    # Channel configuration
    channel_type: {:enum, values: [:whatsapp, :slack, :discord, :sms, :web], required: true},
    channel_config: {:map, required: true},  # Platform-specific: tokens, webhooks, etc.
    
    # Agent configuration
    agent_config: {:map, required: true},    # ReqLLM config, model, provider
    default_character_ref: :string,          # Default Jido.Character for this instance
    
    # Access control
    access_rules: {:map, default: %{whitelist: [], blacklist: [], default_policy: :allow}},
    
    # Operational
    is_active: {:boolean, default: true},
    enable_auto_split: {:boolean, default: false},  # Split long messages
    max_participants_per_room: {:integer, default: 1000},
    max_message_history: {:integer, default: 500},
    
    metadata: {:map, default: %{}},
    
    inserted_at: :datetime,
    updated_at: :datetime
  )
end
```

**Key Properties**:
- **Tenant isolation**: Each instance is scoped to one tenant
- **Single channel**: One instance connects to ONE platform (WhatsApp, Slack, etc.)
- **Single agent backend**: Points to one ReqLLM configuration
- **Per-instance limits**: Configurable participant and message limits

### Room (Conversation Context)

```elixir
defmodule Jido.Chat.V2.Room do
  @moduledoc """
  Represents a conversation room within an instance.
  
  A room is the fundamental unit of conversation - it contains:
  - Participants (humans, agents, integrations)
  - Message history (bounded, with persistence)
  - Active agent and character configuration
  - Conversation state (for multi-turn interactions)
  """
  
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},              # Internal UUID
    instance_id: {:string, required: true},     # Parent instance
    
    # Platform mapping
    external_room_ref: {:any, required: true},  # Slack channel ID, WhatsApp JID, etc.
    
    # Participants
    participants: {:list, item_type: :map, default: []},  # List of ParticipantRef
    participant_limit: {:integer, default: 1000},
    
    # Agent configuration
    active_agent_ref: :string,           # Which agent is "on stage"
    character_ref: :string,              # Room-specific persona override
    
    # Conversation state
    conversation_state_ref: :string,     # For wizards, forms, multi-turn flows
    turn_strategy: {:atom, default: :free_form},  # :free_form | :round_robin | :pubsub
    
    # History
    history: {:list, item_type: :map, default: []},  # Bounded in-memory buffer
    history_limit: {:integer, default: 500},
    persistence_adapter: :atom,          # Optional: :ets | :ecto | :none
    
    # Metadata
    created_at: :datetime,
    updated_at: :datetime,
    metadata: {:map, default: %{}}
  )
end
```

**Key Properties**:
- **Platform-agnostic**: Internally uses UUIDs, maps to external refs
- **Multi-participant**: Supports humans, agents, integrations
- **Bounded history**: Configurable limits with optional persistence
- **Character-aware**: Can override instance default with room-specific persona

### Participant (Actor Reference)

```elixir
defmodule Jido.Chat.V2.Participant do
  @moduledoc """
  Represents a participant in a conversation.
  
  Participants can be:
  - Humans (from Slack, WhatsApp, SMS, etc.)
  - AI Agents (Jido agents with personalities)
  - Integrations (bots, services, webhooks)
  - System (automated messages)
  """
  
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},
    type: {:enum, values: [:human, :agent, :integration, :system], required: true},
    
    # Platform identity mapping
    platform_identity: {:map, required: true},  
    # Examples:
    # %{slack: %{user_id: "U123", team_id: "T456"}}
    # %{whatsapp: %{jid: "1234567890@s.whatsapp.net"}}
    # %{discord: %{user_id: "123456789", guild_id: "987654321"}}
    
    # Agent configuration (for agent participants)
    character_ref: :string,              # Jido.Character reference
    agent_config: :map,                  # Agent-specific config
    
    # Display
    display_name: :string,
    avatar_url: :string,
    
    # Permissions
    roles: {:list, item_type: :string, default: []},
    permissions: {:map, default: %{}},
    
    metadata: {:map, default: %{}}
  )
end
```

**Key Properties**:
- **Unified abstraction**: Humans and agents are both participants
- **Platform mapping**: Maps internal ID to platform-specific identities
- **Character integration**: Agent participants reference `Jido.Character`

### Message (Normalized Communication)

```elixir
defmodule Jido.Chat.V2.Message do
  @moduledoc """
  Normalized message representation across all platforms.
  
  Messages are the fundamental unit of communication. They are:
  - Platform-agnostic (normalized content model)
  - LLM-ready (map directly to ReqLLM roles and content)
  - Traceable (include channel payloads for debugging)
  """
  
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},
    room_id: {:string, required: true},
    instance_id: {:string, required: true},
    
    # Sender
    from: {:map, required: true},        # ParticipantRef
    
    # ReqLLM mapping
    role: {:enum, values: [:user, :assistant, :system, :tool], required: true},
    
    # Content (normalized)
    content: {:map, required: true},
    # Structure:
    # %{
    #   type: :text | :attachments | :buttons | :cards | :mixed,
    #   text: "...",
    #   attachments: [%{type: :image, url: "...", caption: "..."}],
    #   buttons: [%{id: "btn1", label: "Approve", value: "approve"}],
    #   ...
    # }
    
    # Platform-specific (for debugging/tracing)
    channel_payload: :map,               # Raw platform payload
    
    # Threading
    thread_ref: :string,                 # Optional thread/reply reference
    parent_message_id: :string,          # For threaded conversations
    
    # Timestamps
    timestamp: {:datetime, required: true},
    
    # Metadata
    metadata: {:map, default: %{}}
  )
end
```

**Key Properties**:
- **ReqLLM compatible**: `role` field maps directly to LLM message roles
- **Rich content model**: Supports text, attachments, buttons, cards
- **Platform traceability**: Preserves original payload for debugging
- **Thread-aware**: Supports threaded conversations

---

## Six-Layer Architecture

### Layer 1: Core Domain Model

**Purpose**: Provide clean, channel-agnostic abstractions

**Components**:
- `Instance` - Tenant configuration
- `Room` - Conversation context  
- `Participant` - Actor reference
- `Message` - Normalized communication

**Key Decisions**:
- Use `Zoi.struct` for runtime validation (aligns with jido ecosystem)
- Separate internal IDs from external platform refs
- Map all content to ReqLLM-compatible format
- Bounded history with configurable persistence

**Implementation Effort**: L (1-2 days)

---

### Layer 2: Channel Normalization (Edge)

**Purpose**: Isolate all platform-specific complexity

**Pattern**: Behaviour-based adapters that normalize incoming events and format outgoing messages

```elixir
defmodule Jido.Chat.V2.Channel do
  @moduledoc """
  Behaviour for messaging platform adapters.
  
  Each adapter translates between platform-specific formats
  and the normalized JIDO_CHAT_V2 message model.
  """
  
  @type raw_event :: map()
  @type normalized_event :: %{
    type: :message | :reaction | :command | :join | :leave | :typing | :other,
    external_room_ref: term(),
    external_user_ref: term(),
    text: String.t() | nil,
    attachments: [map()],
    buttons: [map()],
    metadata: map()
  }
  
  @type normalized_message :: map()
  @type channel_result :: {:ok, term()} | {:error, term()}
  
  # Lifecycle
  @callback init(instance_config :: map()) :: {:ok, state :: any()} | {:error, term()}
  @callback connect(state :: any()) :: {:ok, state :: any()} | {:error, term()}
  @callback disconnect(state :: any()) :: {:ok, state :: any()} | {:error, term()}
  @callback status(state :: any()) :: :connected | :disconnected | :error
  
  # Inbound normalization
  @callback normalize_incoming(state :: any(), raw_event) ::
    {:ok, normalized_event} | {:ignore, reason :: term()} | {:error, term()}
  
  # Outbound formatting
  @callback send_text(state :: any(), to :: String.t(), text :: String.t()) :: channel_result()
  @callback send_media(state :: any(), to :: String.t(), media_url :: String.t(), opts :: keyword()) :: channel_result()
  @callback send_buttons(state :: any(), to :: String.t(), text :: String.t(), buttons :: [map()]) :: channel_result()
  @callback send_cards(state :: any(), to :: String.t(), cards :: [map()]) :: channel_result()
  
  # Platform operations (Omni-style)
  @callback get_contacts(state :: any(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback get_chats(state :: any(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback get_channel_info(state :: any()) :: {:ok, map()} | {:error, term()}
end
```

**Adapter Implementations**:

```elixir
# WhatsApp via Evolution API
defmodule Jido.Chat.V2.Channel.WhatsApp do
  @behaviour Jido.Chat.V2.Channel
  
  # Normalize Evolution API webhook to internal format
  def normalize_incoming(state, %{"data" => data}) do
    {:ok, %{
      type: detect_type(data),
      external_room_ref: data["key"]["remoteJid"],
      external_user_ref: data["key"]["remoteJid"],
      text: extract_text(data),
      attachments: extract_attachments(data),
      metadata: %{
        message_id: data["key"]["id"],
        timestamp: data["messageTimestamp"]
      }
    }}
  end
  
  def send_text(state, to, text) do
    EvolutionAPI.send_text(state.client, state.instance_name, to, text)
  end
end

# Slack via Bolt/Events API
defmodule Jido.Chat.V2.Channel.Slack do
  @behaviour Jido.Chat.V2.Channel
  
  def normalize_incoming(state, %{"event" => event}) do
    {:ok, %{
      type: event_type(event["type"]),
      external_room_ref: event["channel"],
      external_user_ref: event["user"],
      text: event["text"],
      attachments: [],
      metadata: %{
        ts: event["ts"],
        thread_ts: event["thread_ts"]
      }
    }}
  end
  
  def send_text(state, channel, text) do
    Slack.Web.Chat.post_message(channel, text, state.token)
  end
end

# Discord via Nostrum
defmodule Jido.Chat.V2.Channel.Discord do
  @behaviour Jido.Chat.V2.Channel
  
  def normalize_incoming(state, message) do
    {:ok, %{
      type: :message,
      external_room_ref: message.channel_id,
      external_user_ref: message.author.id,
      text: message.content,
      attachments: normalize_attachments(message.attachments),
      metadata: %{
        message_id: message.id,
        guild_id: message.guild_id
      }
    }}
  end
  
  def send_text(state, channel_id, text) do
    Nostrum.Api.create_message(channel_id, text)
  end
end
```

**Flow Example** (Inbound):

```
1. WhatsApp user sends "Hello" to bot
2. Evolution API sends webhook to /webhooks/customer-support
3. WebhookController extracts instance_name, raw_params
4. Calls InstanceServer.handle_incoming(instance_name, raw_params)
5. InstanceServer uses WhatsApp adapter: normalize_incoming(raw_params)
6. Returns normalized_event: %{type: :message, external_room_ref: "...", text: "Hello"}
7. InstanceServer resolves/creates RoomServer for that external_room_ref
8. Sends {:incoming_event, normalized_event} to RoomServer
9. RoomServer appends to history, routes to agent gateway
```

**Research Topics**: [See research/channel-adapters.md](#)

**Implementation Effort**: M (1-3 days for behaviour + 2-3 adapters)

---

### Layer 3: Conversation & Routing (Rooms, Middleware)

**Purpose**: Orchestrate multi-party conversations and route to appropriate handlers

**Components**:

#### RoomServer (GenServer)

```elixir
defmodule Jido.Chat.V2.RoomServer do
  use GenServer
  
  @moduledoc """
  GenServer maintaining conversation state for a single room.
  
  Responsibilities:
  - Manage participants (join/leave, limits)
  - Maintain bounded message history
  - Apply turn strategies (who responds when)
  - Route events to agent gateway or actions
  - Emit jido_signal events
  """
  
  defstruct [
    :id,
    :instance_id,
    :external_room_ref,
    :participants,
    :history,
    :turn_strategy,
    :active_agent_ref,
    :character_ref,
    :conversation_state_ref,
    :config
  ]
  
  # Client API
  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end
  
  def handle_incoming_event(room_id, normalized_event) do
    GenServer.call(via_tuple(room_id), {:incoming_event, normalized_event})
  end
  
  def send_outgoing_message(room_id, message) do
    GenServer.call(via_tuple(room_id), {:send_outgoing, message})
  end
  
  # Server Callbacks
  def handle_call({:incoming_event, event}, _from, state) do
    # 1. Create Message struct from normalized_event
    {:ok, message} = build_message(event, state)
    
    # 2. Check participant limits, add if needed
    state = ensure_participant(state, event.external_user_ref)
    
    # 3. Append to history (bounded)
    state = append_to_history(state, message)
    
    # 4. Emit signal
    emit_signal("chat.incoming.message", message, state)
    
    # 5. Route via middleware pipeline
    {:ok, response, state} = route_message(message, state)
    
    {:reply, {:ok, response}, state}
  end
  
  defp route_message(message, state) do
    # Build RoomEvent
    event = %RoomEvent{
      instance_id: state.instance_id,
      room_id: state.id,
      type: message_type(message),
      text: message.content.text,
      from: message.from,
      metadata: message.metadata
    }
    
    # Apply middleware pipeline
    context = %{event: event, room: state, config: state.config}
    
    context
    |> Middleware.Trace.call([])
    |> Middleware.AccessControl.call([])
    |> Middleware.RateLimit.call([])
    |> Router.route()
    |> Handler.execute()
  end
end
```

#### Router

```elixir
defmodule Jido.Chat.V2.Router do
  @moduledoc """
  Routes normalized room events to handlers.
  
  Supports:
  - Pattern matching on message content
  - Guard clauses for conditional routing
  - Action-based dispatch
  - Default fallback to agent gateway
  """
  
  defmacro __using__(_opts) do
    quote do
      import Jido.Chat.V2.Router
      Module.register_attribute(__MODULE__, :routes, accumulate: true)
      @before_compile Jido.Chat.V2.Router
    end
  end
  
  defmacro on(type, pattern, opts) do
    quote do
      @routes {unquote(type), unquote(pattern), unquote(opts)}
    end
  end
  
  def route(%{event: event} = context) do
    # Match routes in order
    case find_matching_route(event, context.room.routes) do
      {:ok, handler} -> Map.put(context, :handler, handler)
      :no_match -> Map.put(context, :handler, :default_agent)
    end
  end
end
```

**Example Usage**:

```elixir
defmodule MyApp.ChatRouter do
  use Jido.Chat.V2.Router
  
  # Slash commands (Slack-style)
  on :command, "/help", do: MyApp.Actions.HelpAction
  on :command, "/status", do: MyApp.Actions.StatusAction
  
  # Keyword matching
  on :message, when: &contains_keyword?(&1, "pricing"), do: MyApp.Actions.PricingAction
  on :message, when: &contains_keyword?(&1, "support"), do: MyApp.Actions.SupportAction
  
  # Button actions
  on :action, "approve_button", do: MyApp.Actions.ApprovalAction
  on :action, "reject_button", do: MyApp.Actions.RejectionAction
  
  # Default: route to agent
  # (implicit - any unmatched message goes to AgentGateway)
end
```

**Turn Strategies** (from existing jido_chat):

```elixir
defmodule Jido.Chat.V2.TurnStrategy do
  @callback is_message_allowed(state, message) :: 
    {:ok, boolean(), state, notifications :: [Message.t()]}
  
  @callback advance_turn(state, reason) :: 
    {:ok, state, notifications :: [Message.t()]}
end

# Implementations:
# - FreeForm: Anyone can speak anytime
# - RoundRobin: Participants take turns
# - PubSub: Coordinated via Phoenix.PubSub
```

**Research Topics**: [See research/routing-strategies.md](#)

**Implementation Effort**: M (1-3 days for router + middleware + turn strategies)

---

### Layer 4: Agent Gateway (ReqLLM + Jido.Character + Actions)

**Purpose**: Transform room context into rich LLM requests and orchestrate responses

**Components**:

#### Context Builder

```elixir
defmodule Jido.Chat.V2.ContextBuilder do
  @moduledoc """
  Builds rich ReqLLM context from room state.
  
  Transforms:
  - Room history → conversation messages
  - Character → system prompts
  - Available actions → tool definitions
  - Participant info → context metadata
  """
  
  def build_context(room_state, current_message, opts \\ []) do
    # 1. Resolve active character
    character = resolve_character(room_state)
    
    # 2. Build system messages from character
    system_messages = build_system_messages(character)
    
    # 3. Convert history to conversation messages
    conversation_messages = build_conversation_history(room_state.history, opts)
    
    # 4. Add current message
    user_message = build_user_message(current_message)
    
    # 5. Build tool definitions from available actions
    tools = build_tool_definitions(room_state, character)
    
    # 6. Assemble ReqLLM request
    %ReqLLM.Request{
      messages: system_messages ++ conversation_messages ++ [user_message],
      tools: tools,
      model: room_state.config.model,
      temperature: character.temperature || 0.7,
      max_tokens: room_state.config.max_tokens || 1000,
      metadata: %{
        tenant_id: room_state.tenant_id,
        instance_id: room_state.instance_id,
        room_id: room_state.id,
        character_id: character.id,
        trace_id: Jido.Signal.current_trace_id()
      }
    }
  end
  
  defp resolve_character(%{character_ref: char_ref}) when not is_nil(char_ref) do
    Jido.Character.get(char_ref)
  end
  defp resolve_character(%{instance_id: inst_id}) do
    Instance.get_default_character(inst_id)
  end
  
  defp build_system_messages(character) do
    [
      %{role: :system, content: character.system_prompt},
      %{role: :system, content: character.behavioral_guidelines}
    ]
  end
  
  defp build_conversation_history(history, opts) do
    history
    |> Enum.take(-(opts[:history_window] || 20))
    |> Enum.map(&message_to_llm_format/1)
  end
  
  defp message_to_llm_format(message) do
    %{
      role: message.role,  # :user | :assistant | :tool
      content: format_content(message.content),
      name: message.from.display_name
    }
  end
  
  defp build_tool_definitions(room_state, character) do
    # Get available actions for this character/instance
    character.available_actions
    |> Enum.map(&action_to_tool_definition/1)
  end
  
  defp action_to_tool_definition(action_module) do
    # Convert Jido.Action schema to MCP/OpenAI function format
    %{
      type: "function",
      function: %{
        name: action_module.__action__(:name),
        description: action_module.__action__(:description),
        parameters: action_module.__action__(:schema) |> schema_to_json_schema()
      }
    }
  end
end
```

#### Agent Gateway

```elixir
defmodule Jido.Chat.V2.AgentGateway do
  use GenServer
  
  @moduledoc """
  Orchestrates agent interactions via ReqLLM.
  
  Responsibilities:
  - Build rich context from room state
  - Submit to LLM provider
  - Handle streaming responses
  - Execute tool calls via Jido.Action
  - Return responses to room
  """
  
  def process_message(room_id, message, opts \\ []) do
    GenServer.call(__MODULE__, {:process, room_id, message, opts}, :timer.minutes(5))
  end
  
  def handle_call({:process, room_id, message, opts}, _from, state) do
    # 1. Get room state
    room_state = RoomServer.get_state(room_id)
    
    # 2. Build ReqLLM context
    req = ContextBuilder.build_context(room_state, message, opts)
    
    # 3. Emit signal
    emit_signal("chat.agent.requested", %{room_id: room_id, request: req})
    
    # 4. Submit to LLM
    case ReqLLM.chat(req) do
      {:ok, %{streaming: true} = response} ->
        handle_streaming_response(room_id, response, state)
      
      {:ok, response} ->
        handle_sync_response(room_id, response, state)
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  defp handle_streaming_response(room_id, response, state) do
    # Stream chunks back to room
    Stream.each(response.stream, fn chunk ->
      RoomServer.stream_chunk(room_id, chunk)
      emit_signal("chat.agent.chunk", %{room_id: room_id, chunk: chunk})
    end)
    |> Stream.run()
    
    # Final message
    final_message = response.final_message
    
    # Check for tool calls
    case final_message.tool_calls do
      nil -> {:reply, {:ok, final_message}, state}
      tools -> execute_tools_and_continue(room_id, tools, state)
    end
  end
  
  defp execute_tools_and_continue(room_id, tool_calls, state) do
    # Execute each tool call via Jido.Action
    results = Enum.map(tool_calls, fn tool_call ->
      action_module = resolve_action(tool_call.function.name)
      params = Jason.decode!(tool_call.function.arguments)
      
      # Build action context
      context = %{
        room_id: room_id,
        trace_id: Jido.Signal.current_trace_id()
      }
      
      # Execute action
      case Jido.Action.run(action_module, params, context) do
        {:ok, result, _context} ->
          emit_signal("chat.agent.tool_called", %{
            room_id: room_id,
            tool: tool_call.function.name,
            result: result
          })
          
          %{
            tool_call_id: tool_call.id,
            role: :tool,
            content: Jason.encode!(result)
          }
        
        {:error, reason} ->
          %{
            tool_call_id: tool_call.id,
            role: :tool,
            content: Jason.encode!(%{error: reason})
          }
      end
    end)
    
    # Continue conversation with tool results
    # (simplified - real implementation would loop until no more tools)
    {:reply, {:ok, results}, state}
  end
end
```

**Jido.Character Integration**:

```elixir
defmodule Jido.Character do
  @moduledoc """
  Character represents an AI agent's personality and capabilities.
  
  Used by JIDO_CHAT_V2 to:
  - Generate system prompts
  - Define behavioral guidelines
  - Specify available tools (Jido.Actions)
  - Configure model parameters
  """
  
  defstruct [
    :id,
    :name,
    :system_prompt,
    :behavioral_guidelines,
    :available_actions,        # List of Jido.Action modules
    :temperature,
    :model_preferences,
    :safety_rules,
    :metadata
  ]
  
  # Example character
  def customer_support do
    %__MODULE__{
      id: "customer_support_v1",
      name: "Customer Support Agent",
      system_prompt: """
      You are a helpful, professional customer support agent.
      Your goal is to resolve customer issues efficiently and empathetically.
      """,
      behavioral_guidelines: """
      - Always be polite and professional
      - Ask clarifying questions when needed
      - Escalate to human support when appropriate
      - Use available tools to look up order status, refunds, etc.
      """,
      available_actions: [
        MyApp.Actions.LookupOrder,
        MyApp.Actions.ProcessRefund,
        MyApp.Actions.EscalateToHuman
      ],
      temperature: 0.7,
      model_preferences: %{
        provider: :openai,
        model: "gpt-4"
      }
    }
  end
end
```

**Research Topics**: [See research/reqllm-integration.md](#)

**Implementation Effort**: L (2-4 days for context builder + gateway + character integration)

---

### Layer 5: Signals & Events (jido_signal)

**Purpose**: Make every meaningful step observable and hookable via signals

**Signal Map**:

```elixir
defmodule Jido.Chat.V2.Signals do
  @moduledoc """
  Signal definitions for JIDO_CHAT_V2.
  
  All signals follow pattern: "chat.{domain}.{action}"
  """
  
  # Inbound events
  def incoming_message, do: "chat.incoming.message"
  def incoming_command, do: "chat.incoming.command"
  def incoming_reaction, do: "chat.incoming.reaction"
  
  # Room lifecycle
  def room_created, do: "chat.room.created"
  def room_updated, do: "chat.room.updated"
  def room_closed, do: "chat.room.closed"
  
  # Participant events
  def participant_joined, do: "chat.participant.joined"
  def participant_left, do: "chat.participant.left"
  def participant_updated, do: "chat.participant.updated"
  
  # Agent lifecycle
  def agent_requested, do: "chat.agent.requested"
  def agent_streaming_started, do: "chat.agent.streaming_started"
  def agent_chunk, do: "chat.agent.chunk"
  def agent_tool_called, do: "chat.agent.tool_called"
  def agent_completed, do: "chat.agent.completed"
  def agent_error, do: "chat.agent.error"
  
  # Outbound events
  def outgoing_message, do: "chat.outgoing.message"
  def outgoing_delivery_succeeded, do: "chat.outgoing.delivery_succeeded"
  def outgoing_delivery_failed, do: "chat.outgoing.delivery_failed"
  
  # Instance lifecycle
  def instance_started, do: "chat.instance.started"
  def instance_stopped, do: "chat.instance.stopped"
  def instance_error, do: "chat.instance.error"
  
  # Tracing
  def trace_started, do: "chat.trace.started"
  def trace_stage, do: "chat.trace.stage"
  def trace_completed, do: "chat.trace.completed"
end
```

**Emission Pattern**:

```elixir
defmodule Jido.Chat.V2.SignalEmitter do
  def emit(signal_name, payload, context \\ %{}) do
    signal = %Jido.Signal{
      type: signal_name,
      source: "jido_chat_v2",
      payload: payload,
      metadata: context,
      timestamp: DateTime.utc_now()
    }
    
    Jido.Signal.Bus.publish(Jido.Chat.V2.Bus, [signal])
  end
end

# Usage in RoomServer:
def handle_call({:incoming_event, event}, _from, state) do
  # ... process event ...
  
  SignalEmitter.emit(
    Signals.incoming_message(),
    %{message: message, room_id: state.id},
    %{instance_id: state.instance_id, trace_id: trace_id}
  )
  
  # ... continue processing ...
end
```

**Subscription Pattern**:

```elixir
# External service subscribes to all incoming messages
defmodule MyApp.Analytics do
  use GenServer
  
  def init(_) do
    # Subscribe to chat signals
    Jido.Signal.Bus.subscribe(Jido.Chat.V2.Bus, "chat.incoming.*")
    Jido.Signal.Bus.subscribe(Jido.Chat.V2.Bus, "chat.agent.completed")
    
    {:ok, %{}}
  end
  
  def handle_info({:signal, %{type: "chat.incoming.message"} = signal}, state) do
    # Log message to analytics
    track_incoming_message(signal.payload)
    {:noreply, state}
  end
  
  def handle_info({:signal, %{type: "chat.agent.completed"} = signal}, state) do
    # Track agent response time
    track_agent_latency(signal.payload, signal.metadata)
    {:noreply, state}
  end
end
```

**Research Topics**: [See research/event-architecture.md](#)

**Implementation Effort**: S-M (0.5-1 day for signal definitions + instrumentation)

---

### Layer 6: Multi-Tenant APIs & Admin Surfaces

**Purpose**: Enable management of instances, rooms, and configuration

**Phoenix API Structure**:

```elixir
defmodule Jido.Chat.V2.Web.Router do
  use Phoenix.Router
  
  pipeline :api do
    plug :accepts, ["json"]
    plug Jido.Chat.V2.Web.Plugs.APIAuth
  end
  
  pipeline :webhook do
    plug :accepts, ["json"]
    plug Jido.Chat.V2.Web.Plugs.WebhookAuth
  end
  
  scope "/api/v1", Jido.Chat.V2.Web do
    pipe_through :api
    
    # Instance management
    resources "/instances", InstanceController, except: [:new, :edit] do
      get "/qr", InstanceController, :qr_code        # WhatsApp QR login
      post "/restart", InstanceController, :restart
      get "/status", InstanceController, :status
      
      # Message operations
      post "/send-text", MessageController, :send_text
      post "/send-media", MessageController, :send_media
      post "/send-buttons", MessageController, :send_buttons
    end
    
    # Room management
    resources "/rooms", RoomController, only: [:index, :show, :create, :delete] do
      get "/history", RoomController, :get_history
      post "/participants", RoomController, :add_participant
      delete "/participants/:participant_id", RoomController, :remove_participant
    end
    
    # Omni operations
    get "/omni/:instance_name/contacts", OmniController, :contacts
    get "/omni/:instance_name/chats", OmniController, :chats
    get "/omni/:instance_name/info", OmniController, :info
    
    # Tracing & analytics
    resources "/traces", TraceController, only: [:index, :show]
    get "/analytics/summary", AnalyticsController, :summary
  end
  
  scope "/webhooks", Jido.Chat.V2.Web do
    pipe_through :webhook
    
    # Webhook receivers (per instance)
    post "/:instance_name", WebhookController, :receive
  end
end
```

**Instance Management Example**:

```elixir
defmodule Jido.Chat.V2.Web.InstanceController do
  use Phoenix.Controller
  
  # POST /api/v1/instances
  def create(conn, %{"instance" => params}) do
    case Jido.Chat.V2.Instance.create(params) do
      {:ok, instance} ->
        conn
        |> put_status(:created)
        |> json(%{data: instance})
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, & &1)})
    end
  end
  
  # GET /api/v1/instances/:name/qr
  def qr_code(conn, %{"instance_id" => id}) do
    case Instance.get_qr_code(id) do
      {:ok, qr_data} ->
        json(conn, %{qr_code: qr_data, expires_at: DateTime.add(DateTime.utc_now(), 60)})
      
      {:error, :channel_not_whatsapp} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "QR code only available for WhatsApp instances"})
    end
  end
end
```

**Webhook Receiver Example**:

```elixir
defmodule Jido.Chat.V2.Web.WebhookController do
  use Phoenix.Controller
  
  # POST /webhooks/:instance_name
  def receive(conn, %{"instance_name" => instance_name} = params) do
    # Start trace
    {:ok, trace_id} = Trace.start(instance_name, extract_user_id(params))
    
    # Route to instance server
    case InstanceServer.handle_incoming(instance_name, params, trace_id) do
      :ok ->
        send_resp(conn, 200, "")
      
      {:error, reason} ->
        Logger.error("Webhook failed: #{inspect(reason)}")
        send_resp(conn, 500, "")
    end
  end
end
```

**Research Topics**: [See research/api-design.md](#)

**Implementation Effort**: M (1-3 days for controllers + routes + auth)

---

## Integration with Jido Ecosystem

### Jido.Action Integration

**Pattern**: Expose actions as LLM tools

```elixir
defmodule MyApp.Actions.LookupOrder do
  use Jido.Action,
    name: "lookup_order",
    description: "Look up order status by order ID",
    schema: [
      order_id: [type: :string, required: true]
    ]
  
  @impl true
  def run(params, context) do
    # Business logic
    order = Orders.get_order(params.order_id)
    
    # Return result for LLM
    {:ok, %{
      order_id: order.id,
      status: order.status,
      items: order.items,
      total: order.total
    }, context}
  end
end

# In ContextBuilder:
defp build_tool_definitions(room_state, character) do
  character.available_actions
  |> Enum.map(fn action_module ->
    %{
      type: "function",
      function: %{
        name: action_module.__action__(:name),
        description: action_module.__action__(:description),
        parameters: convert_schema_to_json_schema(action_module.__action__(:schema))
      }
    }
  end)
end
```

### Jido.Signal Integration

**Pattern**: Emit and subscribe to chat events

```elixir
# Emit from RoomServer
SignalEmitter.emit("chat.incoming.message", %{message: msg, room_id: room.id})

# Subscribe in external service
Jido.Signal.Bus.subscribe(Jido.Chat.V2.Bus, "chat.incoming.*")

def handle_info({:signal, signal}, state) do
  # Process chat event
  Logger.info("Received chat signal: #{signal.type}")
  {:noreply, state}
end
```

### Jido.Character Integration

**Pattern**: Define agent personalities

```elixir
defmodule MyApp.Characters do
  def sales_agent do
    %Jido.Character{
      id: "sales_v1",
      name: "Sales Agent",
      system_prompt: "You are a knowledgeable sales representative...",
      behavioral_guidelines: "Always be consultative, not pushy...",
      available_actions: [
        MyApp.Actions.LookupProduct,
        MyApp.Actions.CreateQuote,
        MyApp.Actions.ScheduleDemo
      ],
      temperature: 0.8
    }
  end
  
  def support_agent do
    %Jido.Character{
      id: "support_v1",
      name: "Support Agent",
      system_prompt: "You are a patient, helpful support agent...",
      behavioral_guidelines: "Focus on resolving issues quickly...",
      available_actions: [
        MyApp.Actions.LookupOrder,
        MyApp.Actions.ProcessRefund,
        MyApp.Actions.EscalateToHuman
      ],
      temperature: 0.7
    }
  end
end
```

### ReqLLM Integration

**Pattern**: Build rich contexts for LLM submission

```elixir
# ContextBuilder produces ReqLLM.Request
req = %ReqLLM.Request{
  messages: [
    %{role: :system, content: character.system_prompt},
    %{role: :user, content: "What's my order status?"}
  ],
  tools: [
    %{
      type: "function",
      function: %{
        name: "lookup_order",
        description: "Look up order status by order ID",
        parameters: %{...}
      }
    }
  ],
  model: "gpt-4",
  temperature: 0.7
}

# Submit to LLM
{:ok, response} = ReqLLM.chat(req)
```

---

## Multi-Tenancy & Isolation

### Tenant Model

```
Tenant (Organization)
  └─── Instances (1 per channel connection)
         ├─── WhatsApp Instance #1 (Evolution API)
         ├─── Slack Instance #1 (Workspace A)
         ├─── Discord Instance #1 (Server A)
         └─── SMS Instance #1 (Twilio)
               └─── Rooms (conversations)
                     ├─── Room #1 (external_room_ref: slack_channel_id_123)
                     ├─── Room #2 (external_room_ref: whatsapp_jid_456)
                     └─── Room #N
```

### Isolation Guarantees

**Process-level isolation**:
- Each instance runs in separate `InstanceServer` GenServer
- Instance crash doesn't affect other instances
- Supervised by `DynamicSupervisor`

**Configuration isolation**:
- Each instance has independent:
  - Channel credentials (tokens, secrets)
  - Agent configuration (model, provider)
  - Access rules (whitelist/blacklist)
  - Character defaults

**Data isolation**:
- Room state scoped to instance
- Message history per-room
- Participant lists per-room

**Resource limits**:
- Per-instance participant limits
- Per-room message limits
- Configurable rate limiting

---

## ReqLLM Context Building

### Context Structure

```elixir
%ReqLLM.Request{
  # System messages from Character
  messages: [
    %{role: :system, content: character.system_prompt},
    %{role: :system, content: character.behavioral_guidelines},
    
    # Conversation history (normalized)
    %{role: :user, content: "Hello!", name: "Alice"},
    %{role: :assistant, content: "Hi Alice! How can I help?"},
    %{role: :user, content: "What's my order status?"},
    
    # Tool results (if previous turn had tool calls)
    %{role: :tool, content: "{\"order_id\": \"123\", \"status\": \"shipped\"}"}
  ],
  
  # Tools from Character.available_actions
  tools: [
    %{
      type: "function",
      function: %{
        name: "lookup_order",
        description: "Look up order status by order ID",
        parameters: %{
          type: "object",
          properties: %{
            order_id: %{type: "string"}
          },
          required: ["order_id"]
        }
      }
    }
  ],
  
  # Model configuration
  model: "gpt-4",
  temperature: 0.7,
  max_tokens: 1000,
  
  # Metadata for tracing
  metadata: %{
    tenant_id: "tenant_123",
    instance_id: "inst_456",
    room_id: "room_789",
    character_id: "support_v1",
    trace_id: "trace_abc"
  }
}
```

### History Window Strategy

```elixir
defmodule ContextBuilder do
  # Get last N message turns
  def build_conversation_history(history, opts \\ []) do
    window = opts[:history_window] || 20
    
    history
    |> Enum.take(-window)
    |> Enum.map(&normalize_for_llm/1)
  end
  
  # Alternatively: Token-based windowing
  def build_conversation_history_by_tokens(history, opts \\ []) do
    max_tokens = opts[:max_context_tokens] || 4000
    
    history
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn msg, {acc, token_count} ->
      msg_tokens = estimate_tokens(msg)
      
      if token_count + msg_tokens <= max_tokens do
        {:cont, {[normalize_for_llm(msg) | acc], token_count + msg_tokens}}
      else
        {:halt, {acc, token_count}}
      end
    end)
    |> elem(0)
  end
end
```

---

## Signal-Driven Events

### Event Flow Example

```
User sends WhatsApp message "What's my order status?"
    ↓
1. Webhook → InstanceServer → RoomServer
   Signal: "chat.incoming.message"
    ↓
2. RoomServer → Router → AgentGateway
   Signal: "chat.agent.requested"
    ↓
3. AgentGateway → ContextBuilder → ReqLLM
   Signal: "chat.agent.streaming_started"
    ↓
4. LLM returns: "Let me check... I'll use the lookup_order tool"
   Signal: "chat.agent.tool_called"
    ↓
5. Execute LookupOrderAction
   Signal: "action.lookup_order.started"
   Signal: "action.lookup_order.completed"
    ↓
6. Return tool result to LLM
   Signal: "chat.agent.requested" (second turn)
    ↓
7. LLM returns: "Your order #123 is shipped!"
   Signal: "chat.agent.completed"
    ↓
8. RoomServer → InstanceServer → Channel → WhatsApp
   Signal: "chat.outgoing.message"
   Signal: "chat.outgoing.delivery_succeeded"
```

### Observability via Signals

```elixir
# Analytics service subscribes to all agent events
defmodule Analytics do
  def init(_) do
    Jido.Signal.Bus.subscribe(Bus, "chat.agent.*")
    {:ok, %{start_times: %{}}}
  end
  
  def handle_info({:signal, %{type: "chat.agent.requested", payload: p}}, state) do
    state = put_in(state.start_times[p.room_id], DateTime.utc_now())
    {:noreply, state}
  end
  
  def handle_info({:signal, %{type: "chat.agent.completed", payload: p}}, state) do
    start_time = state.start_times[p.room_id]
    latency = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)
    
    # Track metrics
    track_agent_latency(p.instance_id, latency)
    
    {:noreply, state}
  end
end
```

---

## Implementation Strategy

### Phase 1: Core Foundation (Weeks 1-2)

**Goal**: Modernize existing jido_chat with new domain model

- [ ] Migrate structs to Zoi (Instance, Room, Participant, Message)
- [ ] Add Splode error handling
- [ ] Implement InstanceSupervisor + InstanceServer
- [ ] Refactor RoomServer with new domain model
- [ ] Add Registry-based lookups
- [ ] Update to quality standards (mix quality passes)

**Deliverable**: Modernized jido_chat with multi-instance support

---

### Phase 2: Channel Abstraction (Weeks 3-4)

**Goal**: Implement channel normalization layer

- [ ] Define Channel behaviour
- [ ] Implement WhatsApp adapter (Evolution API)
- [ ] Implement Slack adapter (Events API/Bolt)
- [ ] Build webhook receiver infrastructure
- [ ] Add channel-specific message formatting

**Deliverable**: Working WhatsApp and Slack channels

---

### Phase 3: Agent Integration (Weeks 5-6)

**Goal**: Connect to LLMs via ReqLLM

- [ ] Build ContextBuilder module
- [ ] Implement AgentGateway
- [ ] Integrate Jido.Character
- [ ] Map Jido.Actions to tools
- [ ] Add streaming support
- [ ] Handle tool calls

**Deliverable**: Agents can respond via LLM with tool use

---

### Phase 4: Routing & Middleware (Weeks 7-8)

**Goal**: Add sophisticated routing and orchestration

- [ ] Build Router DSL
- [ ] Implement middleware pipeline
- [ ] Add turn strategies
- [ ] Build conversation state management
- [ ] Add pattern matching routing

**Deliverable**: Flexible routing with multi-party support

---

### Phase 5: Signals & Observability (Weeks 9-10)

**Goal**: Instrument with comprehensive signals

- [ ] Define signal map
- [ ] Add emission points in all components
- [ ] Build trace context
- [ ] Add telemetry integration
- [ ] Create analytics example

**Deliverable**: Full observability via signals

---

### Phase 6: APIs & Management (Weeks 11-12)

**Goal**: Production-ready management APIs

- [ ] Build Phoenix controllers
- [ ] Add instance CRUD
- [ ] Add room management
- [ ] Build Omni APIs
- [ ] Add authentication/authorization

**Deliverable**: Production-ready API surface

---

### Phase 7: Additional Channels (Weeks 13-14)

**Goal**: Expand platform support

- [ ] Implement Discord adapter
- [ ] Implement SMS adapter (Twilio)
- [ ] Add web chat adapter
- [ ] Test cross-platform scenarios

**Deliverable**: 4+ channels working

---

### Phase 8: Polish & Documentation (Weeks 15-16)

**Goal**: Production readiness

- [ ] Comprehensive testing (>90% coverage)
- [ ] Load testing (1000 participants, 100 instances)
- [ ] Documentation (guides, API docs, examples)
- [ ] Deployment guides
- [ ] Example applications

**Deliverable**: Production-ready v1.0

---

## Research Areas

The following areas require deeper research and are documented in separate files:

### 1. [Channel Adapter Design](research/channel-adapters.md)

**Questions**:
- How do we handle platform-specific features (Slack threads, WhatsApp media, Discord voice)?
- What's the right abstraction for interactive components (buttons, modals, forms)?
- How do we normalize attachments across platforms?
- Should adapters be plugins or built-in?

**Research Topics**:
- Survey existing Slack/Discord/WhatsApp libraries
- Design button/card abstraction
- Define attachment normalization strategy
- Plugin architecture vs built-in adapters

---

### 2. [Routing Strategies](research/routing-strategies.md)

**Questions**:
- When should we route to Action vs Agent?
- How do we support intent-based routing (NLP)?
- What's the right pattern matching DSL?
- How do we handle ambiguous inputs?

**Research Topics**:
- Intent classification integration (Jido.AI?)
- Pattern matching DSL design
- Fallback strategies
- Multi-agent routing

---

### 3. [ReqLLM Integration](research/reqllm-integration.md)

**Questions**:
- How do we optimize context window usage?
- What's the right tool calling pattern?
- How do we handle streaming across platforms?
- How do we manage prompt governance?

**Research Topics**:
- Token-aware history windowing
- Tool call error handling
- Streaming buffer strategies
- Prompt template system

---

### 4. [Character System Design](research/character-system.md)

**Questions**:
- How granular should character configuration be?
- Should characters be versioned?
- How do we handle character evolution?
- What's the right tool selection strategy?

**Research Topics**:
- Character versioning
- Tool capability mapping
- Personality configuration
- Safety guardrails

---

### 5. [Multi-Tenancy Architecture](research/multi-tenancy.md)

**Questions**:
- How do we isolate tenant data?
- What's the right tenant billing model?
- How do we handle tenant-specific compliance?
- Should we support tenant-level clustering?

**Research Topics**:
- Data isolation strategies
- Resource quota enforcement
- Tenant administration APIs
- Compliance frameworks

---

### 6. [Event Architecture](research/event-architecture.md)

**Questions**:
- What's the right signal granularity?
- How do we handle signal versioning?
- Should signals be persistent (event sourcing)?
- How do we prevent signal fanout issues?

**Research Topics**:
- Signal schema evolution
- Event sourcing patterns
- Signal replay/debugging
- Performance optimization

---

### 7. [Conversation State Management](research/conversation-state.md)

**Questions**:
- How do we persist conversation state?
- What's the right TTL strategy?
- How do we support complex workflows?
- Should we use behavior trees or state machines?

**Research Topics**:
- State persistence adapters
- TTL and cleanup strategies
- Workflow DSL design
- Jido.BehaviorTree integration

---

### 8. [API Design Patterns](research/api-design.md)

**Questions**:
- REST vs GraphQL for management APIs?
- How do we version APIs?
- What's the right authentication model?
- Should we support webhooks for events?

**Research Topics**:
- API versioning strategies
- Authentication/authorization
- Webhook delivery guarantees
- Rate limiting

---

### 9. [Testing Strategies](research/testing-strategies.md)

**Questions**:
- How do we test multi-channel flows?
- What's the right mocking strategy for LLMs?
- How do we test streaming?
- What property-based tests make sense?

**Research Topics**:
- Channel adapter mocking
- LLM response fixtures
- Property-based test scenarios
- Load testing frameworks

---

### 10. [Performance & Scaling](research/performance-scaling.md)

**Questions**:
- What's the bottleneck: rooms, instances, or channels?
- How do we handle 1000+ concurrent rooms?
- Should we cluster across nodes?
- What's the right persistence strategy for history?

**Research Topics**:
- Benchmarking scenarios
- Clustering strategies (Horde, Swarm)
- Message persistence (Ecto, ETS, external store)
- Rate limiting and backpressure

---

## Success Criteria

### Functional Requirements

- [ ] Support 3+ channels (WhatsApp, Slack, Discord) with normalized message model
- [ ] Route messages to LLM agents with full conversation context
- [ ] Support Jido.Character-based personalities
- [ ] Execute Jido.Actions as LLM tools
- [ ] Multi-tenant instances with per-instance configuration
- [ ] 1000 participants per room
- [ ] 500 message history per room
- [ ] Streaming agent responses
- [ ] Comprehensive signal emission

### Quality Requirements

- [ ] `mix quality` passes with no warnings
- [ ] >90% test coverage
- [ ] Load tested: 100 instances, 1000 rooms, 10,000 messages/min
- [ ] All public APIs documented
- [ ] Guides for each channel integration
- [ ] Example application demonstrating full flow

### Integration Requirements

- [ ] Works with Jido.Action
- [ ] Works with Jido.Signal
- [ ] Works with Jido.Character
- [ ] Works with ReqLLM
- [ ] Embeds in Phoenix applications
- [ ] Deployable as standalone service

---

## Conclusion

**JIDO_CHAT_V2** is the missing piece that makes Jido agents accessible to humans via any messaging platform. It provides:

1. **Clean abstraction**: Agents never see platform-specific details
2. **Rich context**: Automatic ReqLLM context building from conversation state
3. **Multi-tenancy**: Per-instance isolation and configuration
4. **Event-driven**: Signal-based architecture for extensibility
5. **Production-ready**: Built on OTP with supervision, limits, and observability

**This is where the puzzle fits together** - the conversation fabric that connects:
- Human users (via any messaging platform)
- AI agents (via ReqLLM + Jido runtime)
- Backend systems (via Jido.Actions)
- Observability (via Jido.Signal)

The architecture builds incrementally on existing jido_chat foundations while adding the multi-channel, multi-tenant capabilities needed for production deployment of conversational AI agents.

**Next Steps**: Begin with Phase 1 (Core Foundation) to modernize existing jido_chat, then incrementally add layers 2-6 over 16 weeks to achieve the full vision.
