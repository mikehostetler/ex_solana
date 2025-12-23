# Evolving Jido.Chat into an Omni-Style Multi-Channel AI Messaging Hub

## Executive Summary

This document outlines the architectural evolution needed to transform **Jido.Chat** from a single-paradigm chat room system into an **Omni-style multi-tenant, multi-channel AI messaging hub** similar to [Automagik Omni](https://github.com/namastexlabs/automagik-omni).

**Current State**: Jido.Chat is a solid OTP-based chat room system with signal bus architecture, turn-taking strategies, and persistence adapters.

**Target State**: A production-grade platform that routes messages across WhatsApp, Discord, Slack, and other channels to multiple AI agents with per-instance isolation, streaming responses, comprehensive tracing, and unified APIs.

---

## Table of Contents

1. [Current Architecture Analysis](#current-architecture-analysis)
2. [Omni Feature Mapping to Elixir](#omni-feature-mapping-to-elixir)
3. [Multi-Instance Architecture](#multi-instance-architecture)
4. [Pluggable Channel System](#pluggable-channel-system)
5. [Streaming & Agent Integration](#streaming--agent-integration)
6. [Tracing & Observability](#tracing--observability)
7. [Phoenix Integration Strategy](#phoenix-integration-strategy)
8. [Implementation Roadmap](#implementation-roadmap)
9. [Code Examples](#code-examples)

---

## Current Architecture Analysis

### What Jido.Chat Does Well

✅ **OTP Foundation**: GenServer-based rooms with supervision  
✅ **Signal Bus**: Event-driven architecture via `Jido.Signal.Bus`  
✅ **Turn Strategies**: Pluggable message flow control (FreeForm, RoundRobin, PubSub)  
✅ **Persistence Adapters**: ETS, In-Memory, Ecto-ready  
✅ **Participant Management**: Human/Agent distinction  
✅ **Message History**: In-memory with configurable limits  

### Current Limitations for Omni Evolution

❌ **Single Protocol**: No channel abstraction (WhatsApp, Discord, etc.)  
❌ **No Multi-Tenancy**: Rooms share the same runtime configuration  
❌ **No Instance Isolation**: Can't have multiple configs pointing to different AI backends  
❌ **No Streaming Support**: Agent responses are synchronous  
❌ **Limited Tracing**: Basic logging, no message lifecycle tracking  
❌ **No Access Control**: No per-instance whitelist/blacklist  
❌ **No Channel-Specific Operations**: No contacts/chats/media APIs  

---

## Omni Feature Mapping to Elixir

| Omni Feature | Elixir/Phoenix Equivalent | Pattern |
|--------------|---------------------------|---------|
| **Multi-Tenant Instances** | `DynamicSupervisor` + per-instance GenServer | Registry-based instance lookup |
| **Channel Handlers** | `Behaviour` module + implementations | Factory pattern with behaviour callbacks |
| **Evolution API (WhatsApp)** | External HTTP client + webhook receiver | Phoenix Controller + Tesla/Finch |
| **Discord Bot** | `Nostrum` library + IPC GenServer | Supervised bot manager process |
| **SSE Streaming** | `Phoenix.Channel` or HTTP SSE endpoint | GenServer buffering + chunked responses |
| **Message Router** | GenServer with pattern matching | Route to agent → format → send via channel |
| **Trace Service** | Telemetry + Ecto schema | `:telemetry.span/3` with database persistence |
| **Access Control** | Plug middleware + ETS rules cache | Pre-routing ACL check |
| **MCP Server** | JSON-RPC over stdio/HTTP | Elixir MCP library (if exists) or custom implementation |
| **REST API** | Phoenix Router + Controllers | Standard CRUD operations |

---

## Multi-Instance Architecture

### Core Concept: Instance = Independent Configuration

Each **instance** is a fully isolated configuration that can:
- Point to a different AI agent backend
- Use a different messaging channel (WhatsApp, Discord, Slack)
- Have its own access control rules
- Maintain separate message history
- Use different credentials and webhooks

### Proposed Structure

```elixir
defmodule Jido.Chat.Instance do
  @moduledoc """
  Represents a multi-tenant chat instance with isolated configuration.
  
  Each instance:
  - Has a unique name
  - Connects to ONE channel (WhatsApp, Discord, etc.)
  - Routes to ONE AI agent backend
  - Maintains its own state and access rules
  """
  
  use GenServer
  
  @type t :: %__MODULE__{
    name: String.t(),
    channel_type: :whatsapp | :discord | :slack | :telegram,
    channel_config: map(),
    agent_config: %{
      api_url: String.t(),
      api_key: String.t(),
      instance_type: :hive | :openai | :anthropic | :custom
    },
    access_rules: %{
      whitelist: [String.t()],
      blacklist: [String.t()],
      default_policy: :allow | :deny
    },
    is_active: boolean(),
    enable_auto_split: boolean(),
    metadata: map()
  }
  
  defstruct [
    :name,
    :channel_type,
    :channel_config,
    :agent_config,
    :access_rules,
    :is_active,
    :enable_auto_split,
    :metadata
  ]
end
```

### Instance Supervisor

```elixir
defmodule Jido.Chat.Instance.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing multiple chat instances.
  
  Each instance runs as a separate GenServer with its own:
  - Channel handler process
  - Message router
  - Trace collector
  """
  
  use DynamicSupervisor
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  def start_instance(instance_config) do
    child_spec = {Jido.Chat.Instance, instance_config}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  def stop_instance(instance_name) do
    # Find the PID via Registry and terminate
    case Registry.lookup(Jido.Chat.InstanceRegistry, instance_name) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
  
  def list_instances do
    Registry.select(Jido.Chat.InstanceRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
```

### Persistence Schema (Ecto)

```elixir
defmodule Jido.Chat.Schema.InstanceConfig do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "instance_configs" do
    field :name, :string
    field :channel_type, Ecto.Enum, values: [:whatsapp, :discord, :slack, :telegram]
    field :channel_config, :map
    field :agent_config, :map
    field :access_rules, :map
    field :is_active, :boolean, default: true
    field :enable_auto_split, :boolean, default: false
    field :metadata, :map, default: %{}
    
    timestamps()
  end
  
  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [:name, :channel_type, :channel_config, :agent_config, 
                    :access_rules, :is_active, :enable_auto_split, :metadata])
    |> validate_required([:name, :channel_type])
    |> unique_constraint(:name)
    |> validate_channel_config()
    |> validate_agent_config()
  end
  
  defp validate_channel_config(changeset) do
    # Validate channel-specific required fields
    # WhatsApp needs evolution_url, evolution_key
    # Discord needs bot_token, client_id
    changeset
  end
  
  defp validate_agent_config(changeset) do
    # Validate agent config has api_url, api_key, instance_type
    changeset
  end
end
```

---

## Pluggable Channel System

### Channel Behaviour

```elixir
defmodule Jido.Chat.Channel do
  @moduledoc """
  Behaviour for implementing messaging channel adapters.
  
  Each channel must implement:
  - Sending messages in various formats
  - Handling incoming webhooks
  - Fetching contacts/chats (Omni operations)
  - Managing connection lifecycle
  """
  
  @type instance_config :: map()
  @type message :: map()
  @type contact :: map()
  @type chat :: map()
  @type result :: {:ok, any()} | {:error, any()}
  
  @callback init(instance_config) :: {:ok, state :: any()} | {:error, any()}
  @callback send_text(state :: any(), to :: String.t(), text :: String.t()) :: result()
  @callback send_media(state :: any(), to :: String.t(), media_url :: String.t(), opts :: keyword()) :: result()
  @callback send_audio(state :: any(), to :: String.t(), audio_url :: String.t()) :: result()
  @callback send_reaction(state :: any(), message_id :: String.t(), emoji :: String.t()) :: result()
  
  # Omni unified operations
  @callback get_contacts(state :: any(), opts :: keyword()) :: {:ok, [contact()]} | {:error, any()}
  @callback get_chats(state :: any(), opts :: keyword()) :: {:ok, [chat()]} | {:error, any()}
  @callback get_channel_info(state :: any()) :: {:ok, map()} | {:error, any()}
  
  # Connection management
  @callback connect(state :: any()) :: {:ok, state :: any()} | {:error, any()}
  @callback disconnect(state :: any()) :: {:ok, state :: any()} | {:error, any()}
  @callback status(state :: any()) :: :connected | :disconnected | :error
  
  # Webhook handling
  @callback handle_webhook(state :: any(), payload :: map()) :: {:ok, message()} | {:error, any()}
end
```

### Channel Factory

```elixir
defmodule Jido.Chat.Channel.Factory do
  @moduledoc """
  Registry and factory for channel handlers.
  """
  
  @handlers %{
    whatsapp: Jido.Chat.Channel.WhatsApp,
    discord: Jido.Chat.Channel.Discord,
    slack: Jido.Chat.Channel.Slack,
    telegram: Jido.Chat.Channel.Telegram
  }
  
  def get_handler(channel_type) do
    case Map.get(@handlers, channel_type) do
      nil -> {:error, :unknown_channel}
      module -> {:ok, module}
    end
  end
  
  def register_handler(channel_type, module) do
    # Allow runtime registration for extensibility
    # Store in ETS or persistent config
  end
end
```

### WhatsApp Channel Implementation (via Evolution API)

```elixir
defmodule Jido.Chat.Channel.WhatsApp do
  @moduledoc """
  WhatsApp channel implementation using Evolution API.
  
  Evolution API is a REST API for WhatsApp that handles:
  - QR code login
  - Message sending (text, media, audio, stickers)
  - Webhook delivery for incoming messages
  - Contact and chat management
  """
  
  @behaviour Jido.Chat.Channel
  
  alias Jido.Chat.Channel.WhatsApp.Client
  
  defstruct [:evolution_url, :evolution_key, :instance_name, :client]
  
  @impl true
  def init(config) do
    state = %__MODULE__{
      evolution_url: config.evolution_url,
      evolution_key: config.evolution_key,
      instance_name: config.instance_name,
      client: Client.new(config.evolution_url, config.evolution_key)
    }
    {:ok, state}
  end
  
  @impl true
  def send_text(state, to, text) do
    Client.send_text(state.client, state.instance_name, to, text)
  end
  
  @impl true
  def send_media(state, to, media_url, opts) do
    media_type = Keyword.get(opts, :type, :image)
    caption = Keyword.get(opts, :caption, "")
    Client.send_media(state.client, state.instance_name, to, media_url, media_type, caption)
  end
  
  @impl true
  def get_contacts(state, opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 50)
    Client.get_contacts(state.client, state.instance_name, page, page_size)
  end
  
  @impl true
  def get_chats(state, opts) do
    Client.get_chats(state.client, state.instance_name, opts)
  end
  
  @impl true
  def handle_webhook(state, payload) do
    # Parse Evolution API webhook format
    # Extract message, sender, content
    # Return normalized message struct
    {:ok, normalize_webhook(payload)}
  end
  
  defp normalize_webhook(payload) do
    %{
      id: payload["key"]["id"],
      from: payload["key"]["remoteJid"],
      content: extract_content(payload),
      timestamp: payload["messageTimestamp"],
      type: detect_message_type(payload)
    }
  end
end
```

### Discord Channel Implementation (via Nostrum)

```elixir
defmodule Jido.Chat.Channel.Discord do
  @moduledoc """
  Discord channel implementation using Nostrum library.
  
  Nostrum is a Discord API client for Elixir that handles:
  - Bot authentication
  - Gateway connection
  - Slash commands
  - Message events
  """
  
  @behaviour Jido.Chat.Channel
  
  alias Nostrum.Api
  
  defstruct [:bot_token, :client_id, :guild_id]
  
  @impl true
  def init(config) do
    # Nostrum starts as an application, so we just store config
    state = %__MODULE__{
      bot_token: config.bot_token,
      client_id: config.client_id,
      guild_id: config.guild_id
    }
    {:ok, state}
  end
  
  @impl true
  def send_text(state, channel_id, text) do
    case Api.create_message(channel_id, text) do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @impl true
  def get_chats(state, _opts) do
    # Get all channels in the guild
    case Api.get_guild_channels(state.guild_id) do
      {:ok, channels} -> {:ok, Enum.map(channels, &normalize_channel/1)}
      error -> error
    end
  end
  
  @impl true
  def handle_webhook(_state, payload) do
    # Discord events come through Nostrum's consumer
    # This would typically be handled in a separate consumer module
    {:ok, payload}
  end
end
```

---

## Streaming & Agent Integration

### Agent Client with Streaming Support

```elixir
defmodule Jido.Chat.Agent.Client do
  @moduledoc """
  HTTP client for AI agent backends with streaming support.
  
  Supports:
  - Synchronous REST responses (Automagik mode)
  - Server-Sent Events streaming (Hive mode)
  - Automatic buffering and formatting
  """
  
  use GenServer
  require Logger
  
  @type agent_config :: %{
    api_url: String.t(),
    api_key: String.t(),
    instance_type: :hive | :openai | :anthropic | :custom
  }
  
  def start_link(agent_config) do
    GenServer.start_link(__MODULE__, agent_config)
  end
  
  def send_message(pid, message, opts \\ []) do
    GenServer.call(pid, {:send_message, message, opts}, :timer.minutes(5))
  end
  
  @impl true
  def init(agent_config) do
    {:ok, %{config: agent_config}}
  end
  
  @impl true
  def handle_call({:send_message, message, opts}, from, state) do
    case state.config.instance_type do
      :hive -> handle_streaming_request(message, opts, from, state)
      _ -> handle_sync_request(message, opts, from, state)
    end
  end
  
  defp handle_sync_request(message, _opts, _from, state) do
    # Standard HTTP POST with JSON response
    url = "#{state.config.api_url}/chat"
    headers = [{"Authorization", "Bearer #{state.config.api_key}"}, {"Content-Type", "application/json"}]
    body = Jason.encode!(%{
      message: message.content,
      user_id: "#{message.platform}:#{message.from}",
      platform: message.platform,
      context: message.metadata || %{}
    })
    
    case Finch.build(:post, url, headers, body) |> Finch.request(MyApp.Finch) do
      {:ok, %{status: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        {:reply, {:ok, response["response"]}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  defp handle_streaming_request(message, _opts, from, state) do
    # SSE streaming - spawn async handler
    parent = self()
    task = Task.async(fn -> stream_agent_response(message, state.config, parent) end)
    
    # Store the task and from for later reply
    new_state = Map.put(state, :streaming_task, %{task: task, from: from})
    {:noreply, new_state}
  end
  
  defp stream_agent_response(message, config, parent) do
    # Use Mint for SSE streaming
    url = URI.parse("#{config.api_url}/chat")
    {:ok, conn} = Mint.HTTP.connect(:https, url.host, url.port || 443)
    
    headers = [{"authorization", "Bearer #{config.api_key}"}, {"content-type", "application/json"}]
    body = Jason.encode!(%{
      message: message.content,
      user_id: "#{message.platform}:#{message.from}",
      platform: message.platform
    })
    
    {:ok, conn, request_ref} = Mint.HTTP.request(conn, "POST", url.path, headers, body)
    
    # Collect streaming chunks
    chunks = collect_sse_stream(conn, request_ref, [])
    Mint.HTTP.close(conn)
    
    # Send complete response back to GenServer
    send(parent, {:stream_complete, chunks})
    Enum.join(chunks, "")
  end
  
  defp collect_sse_stream(conn, request_ref, acc) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            {acc, done?} = process_responses(responses, request_ref, acc)
            if done? do
              acc
            else
              collect_sse_stream(conn, request_ref, acc)
            end
          
          {:error, _conn, _reason, _responses} ->
            acc
          
          :unknown ->
            collect_sse_stream(conn, request_ref, acc)
        end
    after
      30_000 -> acc  # 30 second timeout
    end
  end
  
  defp process_responses(responses, request_ref, acc) do
    Enum.reduce(responses, {acc, false}, fn
      {:data, ^request_ref, chunk}, {acc, _done?} ->
        # Parse SSE format: "data: {json}\n\n"
        case parse_sse_chunk(chunk) do
          {:ok, text} -> {[text | acc], false}
          :done -> {acc, true}
          :skip -> {acc, false}
        end
      
      {:done, ^request_ref}, {acc, _done?} ->
        {acc, true}
      
      _other, state ->
        state
    end)
  end
  
  defp parse_sse_chunk(chunk) do
    # SSE format: "data: {json}\n\n" or "data: [DONE]\n\n"
    case String.trim(chunk) do
      "data: [DONE]" -> :done
      "data: " <> json -> 
        case Jason.decode(json) do
          {:ok, %{"content" => text}} -> {:ok, text}
          _ -> :skip
        end
      _ -> :skip
    end
  end
  
  @impl true
  def handle_info({:stream_complete, chunks}, state) do
    # Reply to the original caller
    response = Enum.reverse(chunks) |> Enum.join("")
    GenServer.reply(state.streaming_task.from, {:ok, response})
    {:noreply, Map.delete(state, :streaming_task)}
  end
end
```

---

## Tracing & Observability

### Trace Context

```elixir
defmodule Jido.Chat.Trace.Context do
  @moduledoc """
  Tracks the complete lifecycle of a message through the system.
  
  Stages:
  1. webhook_received
  2. access_control
  3. agent_request
  4. agent_response
  5. formatting
  6. send
  7. delivered (or error)
  """
  
  use GenServer
  
  defstruct [
    :trace_id,
    :instance_name,
    :user_id,
    :start_time,
    stages: [],
    metadata: %{}
  ]
  
  def start_trace(instance_name, user_id) do
    trace_id = generate_trace_id()
    context = %__MODULE__{
      trace_id: trace_id,
      instance_name: instance_name,
      user_id: user_id,
      start_time: System.monotonic_time(:millisecond)
    }
    
    # Store in ETS for fast lookup
    :ets.insert(:trace_contexts, {trace_id, context})
    {:ok, trace_id}
  end
  
  def log_stage(trace_id, stage, payload, status_code \\ 200) do
    case :ets.lookup(:trace_contexts, trace_id) do
      [{^trace_id, context}] ->
        timestamp = System.monotonic_time(:millisecond)
        latency = timestamp - context.start_time
        
        stage_data = %{
          stage: stage,
          timestamp: timestamp,
          latency_ms: latency,
          status_code: status_code,
          payload: compress_payload(payload)
        }
        
        updated_context = %{context | stages: [stage_data | context.stages]}
        :ets.insert(:trace_contexts, {trace_id, updated_context})
        
        # Emit telemetry event
        :telemetry.execute(
          [:jido_chat, :trace, :stage],
          %{latency: latency},
          %{trace_id: trace_id, stage: stage, status: status_code}
        )
        
        :ok
      
      [] ->
        {:error, :trace_not_found}
    end
  end
  
  def finalize_trace(trace_id) do
    case :ets.lookup(:trace_contexts, trace_id) do
      [{^trace_id, context}] ->
        # Persist to database
        Task.start(fn ->
          Jido.Chat.Schema.MessageTrace.create(context)
        end)
        
        # Clean up ETS
        :ets.delete(:trace_contexts, trace_id)
        :ok
      
      [] ->
        {:error, :trace_not_found}
    end
  end
  
  defp compress_payload(payload) when is_map(payload) do
    # Compress large payloads with zlib
    json = Jason.encode!(payload)
    if byte_size(json) > 1024 do
      :zlib.compress(json) |> Base.encode64()
    else
      json
    end
  end
  
  defp generate_trace_id do
    "trace_#{System.unique_integer([:positive, :monotonic])}"
  end
end
```

### Trace Schema

```elixir
defmodule Jido.Chat.Schema.MessageTrace do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "message_traces" do
    field :trace_id, :string
    field :instance_name, :string
    field :user_id, :string
    field :total_latency_ms, :integer
    field :status, :string
    field :error_message, :string
    
    has_many :payloads, Jido.Chat.Schema.TracePayload
    
    timestamps()
  end
  
  def create(trace_context) do
    total_latency = List.first(trace_context.stages).timestamp - trace_context.start_time
    status = if Enum.any?(trace_context.stages, &(&1.status_code >= 400)), do: "error", else: "success"
    
    %__MODULE__{}
    |> cast(%{
      trace_id: trace_context.trace_id,
      instance_name: trace_context.instance_name,
      user_id: trace_context.user_id,
      total_latency_ms: total_latency,
      status: status
    }, [:trace_id, :instance_name, :user_id, :total_latency_ms, :status])
    |> MyApp.Repo.insert()
  end
end

defmodule Jido.Chat.Schema.TracePayload do
  use Ecto.Schema
  
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trace_payloads" do
    field :stage, :string
    field :payload, :binary  # Compressed JSON
    field :latency_ms, :integer
    field :status_code, :integer
    
    belongs_to :message_trace, Jido.Chat.Schema.MessageTrace, type: :binary_id
    
    timestamps()
  end
end
```

### Telemetry Integration

```elixir
defmodule Jido.Chat.Telemetry do
  @moduledoc """
  Telemetry event handlers for metrics and monitoring.
  """
  
  def setup do
    events = [
      [:jido_chat, :trace, :stage],
      [:jido_chat, :message, :received],
      [:jido_chat, :message, :sent],
      [:jido_chat, :agent, :request],
      [:jido_chat, :agent, :response]
    ]
    
    :telemetry.attach_many(
      "jido-chat-handler",
      events,
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:jido_chat, :trace, :stage], measurements, metadata, _config) do
    # Send to monitoring system (Prometheus, Datadog, etc.)
    Logger.info("Trace stage: #{metadata.stage} - #{measurements.latency}ms")
  end
  
  def handle_event([:jido_chat, :agent, :response], measurements, metadata, _config) do
    if measurements.latency > 5000 do
      Logger.warning("Slow agent response: #{measurements.latency}ms for instance #{metadata.instance}")
    end
  end
end
```

---

## Phoenix Integration Strategy

### Embedding Jido.Chat in a Phoenix App

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Phoenix essentials
      MyApp.Repo,
      MyAppWeb.Telemetry,
      {Phoenix.PubSub, name: MyApp.PubSub},
      MyAppWeb.Endpoint,
      
      # Jido.Chat components
      {Registry, keys: :unique, name: Jido.Chat.InstanceRegistry},
      Jido.Chat.Instance.Supervisor,
      Jido.Chat.MessageRouter,
      {Finch, name: MyApp.Finch},  # For HTTP requests to agents
      
      # Load instances from database on startup
      {Task, fn -> Jido.Chat.Instance.Loader.load_from_db() end}
    ]
    
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Phoenix Controllers for Instance Management

```elixir
defmodule MyAppWeb.InstanceController do
  use MyAppWeb, :controller
  
  alias Jido.Chat.Instance
  
  # POST /api/v1/instances
  def create(conn, %{"instance" => instance_params}) do
    case Instance.create(instance_params) do
      {:ok, instance} ->
        conn
        |> put_status(:created)
        |> json(%{data: instance})
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end
  
  # GET /api/v1/instances
  def index(conn, _params) do
    instances = Instance.list_all()
    json(conn, %{data: instances})
  end
  
  # GET /api/v1/instances/:name
  def show(conn, %{"name" => name}) do
    case Instance.get_by_name(name) do
      {:ok, instance} -> json(conn, %{data: instance})
      {:error, :not_found} -> 
        conn
        |> put_status(:not_found)
        |> json(%{error: "Instance not found"})
    end
  end
  
  # PATCH /api/v1/instances/:name
  def update(conn, %{"name" => name, "instance" => instance_params}) do
    case Instance.update(name, instance_params) do
      {:ok, instance} -> json(conn, %{data: instance})
      {:error, :not_found} -> 
        conn
        |> put_status(:not_found)
        |> json(%{error: "Instance not found"})
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end
  
  # DELETE /api/v1/instances/:name
  def delete(conn, %{"name" => name}) do
    case Instance.delete(name) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Instance not found"})
    end
  end
  
  # GET /api/v1/instances/:name/qr
  def qr_code(conn, %{"name" => name}) do
    case Instance.get_qr_code(name) do
      {:ok, qr_data} -> json(conn, %{qr_code: qr_data})
      {:error, :channel_not_whatsapp} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "QR code only available for WhatsApp instances"})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
  
  # POST /api/v1/instances/:name/restart
  def restart(conn, %{"name" => name}) do
    case Instance.restart(name) do
      :ok -> json(conn, %{status: "restarted"})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
end
```

### Webhook Receiver

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller
  
  require Logger
  
  # POST /webhooks/:instance_name
  def receive(conn, %{"instance_name" => instance_name} = params) do
    # Start trace
    {:ok, trace_id} = Jido.Chat.Trace.Context.start_trace(instance_name, extract_user_id(params))
    Jido.Chat.Trace.Context.log_stage(trace_id, "webhook_received", params)
    
    # Route to message router
    case Jido.Chat.MessageRouter.route(instance_name, params, trace_id) do
      :ok ->
        send_resp(conn, :ok, "")
      
      {:error, reason} ->
        Logger.error("Webhook processing failed: #{inspect(reason)}")
        send_resp(conn, :internal_server_error, "")
    end
  end
  
  defp extract_user_id(%{"data" => %{"key" => %{"remoteJid" => jid}}}), do: jid
  defp extract_user_id(%{"author" => %{"id" => id}}), do: id
  defp extract_user_id(_), do: "unknown"
end
```

### Message Sending API

```elixir
defmodule MyAppWeb.MessageController do
  use MyAppWeb, :controller
  
  # POST /api/v1/instances/:instance_name/send-text
  def send_text(conn, %{"instance_name" => instance_name, "to" => to, "text" => text}) do
    case Jido.Chat.Instance.send_text(instance_name, to, text) do
      {:ok, result} -> json(conn, %{status: "sent", data: result})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
  
  # POST /api/v1/instances/:instance_name/send-media
  def send_media(conn, %{"instance_name" => instance_name, "to" => to, "media_url" => url} = params) do
    opts = [
      type: Map.get(params, "type", "image"),
      caption: Map.get(params, "caption", "")
    ]
    
    case Jido.Chat.Instance.send_media(instance_name, to, url, opts) do
      {:ok, result} -> json(conn, %{status: "sent", data: result})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
end
```

### Omni Unified API

```elixir
defmodule MyAppWeb.OmniController do
  use MyAppWeb, :controller
  
  # GET /omni/:instance_name/contacts
  def contacts(conn, %{"instance_name" => instance_name} = params) do
    opts = [
      page: Map.get(params, "page", "1") |> String.to_integer(),
      page_size: Map.get(params, "page_size", "50") |> String.to_integer(),
      search: Map.get(params, "search")
    ]
    
    case Jido.Chat.Instance.get_contacts(instance_name, opts) do
      {:ok, contacts} -> json(conn, %{data: contacts})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
  
  # GET /omni/:instance_name/chats
  def chats(conn, %{"instance_name" => instance_name} = params) do
    opts = [
      chat_type: Map.get(params, "type"),
      archived: Map.get(params, "archived")
    ]
    
    case Jido.Chat.Instance.get_chats(instance_name, opts) do
      {:ok, chats} -> json(conn, %{data: chats})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
  
  # GET /omni/:instance_name/info
  def info(conn, %{"instance_name" => instance_name}) do
    case Jido.Chat.Instance.get_channel_info(instance_name) do
      {:ok, info} -> json(conn, %{data: info})
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end
end
```

### Router Configuration

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  
  pipeline :api do
    plug :accepts, ["json"]
    plug MyAppWeb.Plugs.APIAuth  # API key authentication
  end
  
  pipeline :webhook do
    plug :accepts, ["json"]
  end
  
  scope "/api/v1", MyAppWeb do
    pipe_through :api
    
    resources "/instances", InstanceController, except: [:new, :edit] do
      get "/qr", InstanceController, :qr_code
      post "/restart", InstanceController, :restart
      post "/send-text", MessageController, :send_text
      post "/send-media", MessageController, :send_media
      post "/send-audio", MessageController, :send_audio
    end
    
    resources "/traces", TraceController, only: [:index, :show]
  end
  
  scope "/omni", MyAppWeb do
    pipe_through :api
    
    get "/:instance_name/contacts", OmniController, :contacts
    get "/:instance_name/chats", OmniController, :chats
    get "/:instance_name/info", OmniController, :info
  end
  
  scope "/webhooks", MyAppWeb do
    pipe_through :webhook
    
    post "/:instance_name", WebhookController, :receive
  end
end
```

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

**Goal**: Multi-instance architecture with basic channel abstraction

- [ ] Create `Jido.Chat.Instance` GenServer with configuration management
- [ ] Implement `Jido.Chat.Instance.Supervisor` with DynamicSupervisor
- [ ] Add `Jido.Chat.Channel` behaviour definition
- [ ] Create Ecto schemas for instance config storage
- [ ] Build instance CRUD operations via Phoenix controllers
- [ ] Add Registry for instance lookup

**Deliverable**: Multiple instances can be created/managed via API

---

### Phase 2: WhatsApp Integration (Weeks 3-4)

**Goal**: First production channel integration

- [ ] Implement `Jido.Chat.Channel.WhatsApp` using Evolution API client
- [ ] Build Evolution API HTTP client (Tesla/Finch)
- [ ] Add webhook receiver for incoming WhatsApp messages
- [ ] Implement QR code login endpoint
- [ ] Add message sending (text, media, audio)
- [ ] Test end-to-end WhatsApp flow

**Deliverable**: WhatsApp instances can send/receive messages

---

### Phase 3: Agent Integration & Streaming (Weeks 5-6)

**Goal**: Connect to AI agents with streaming support

- [ ] Build `Jido.Chat.Agent.Client` GenServer
- [ ] Implement synchronous HTTP requests (Automagik mode)
- [ ] Add SSE streaming support (Hive mode)
- [ ] Create message formatting logic
- [ ] Implement auto-split for long messages
- [ ] Build `Jido.Chat.MessageRouter` to orchestrate webhook → agent → channel

**Deliverable**: Instances route messages to AI agents and return responses

---

### Phase 4: Tracing & Observability (Weeks 7-8)

**Goal**: Comprehensive message lifecycle tracking

- [ ] Build `Jido.Chat.Trace.Context` for tracking
- [ ] Add ETS storage for active traces
- [ ] Create Ecto schemas for trace persistence
- [ ] Implement telemetry events
- [ ] Add trace visualization endpoints
- [ ] Build analytics dashboard (optional)

**Deliverable**: Every message can be traced through the system

---

### Phase 5: Access Control & Security (Weeks 9-10)

**Goal**: Per-instance user access management

- [ ] Create access rule schema (whitelist/blacklist)
- [ ] Implement ACL checking middleware
- [ ] Add API endpoints for managing access rules
- [ ] Build phone number normalization
- [ ] Add rate limiting per instance

**Deliverable**: Instances can restrict who can message them

---

### Phase 6: Discord Integration (Weeks 11-12)

**Goal**: Second major channel

- [ ] Integrate Nostrum library
- [ ] Implement `Jido.Chat.Channel.Discord`
- [ ] Add Discord bot management
- [ ] Build slash command handlers
- [ ] Implement Discord-specific message formatting

**Deliverable**: Discord instances work alongside WhatsApp

---

### Phase 7: Omni Unified API (Weeks 13-14)

**Goal**: Cross-channel operations

- [ ] Implement `get_contacts/2` for all channels
- [ ] Implement `get_chats/2` for all channels
- [ ] Add unified response schemas
- [ ] Build pagination helpers
- [ ] Create filtering logic

**Deliverable**: Unified API works across all channels

---

### Phase 8: MCP Integration (Weeks 15-16)

**Goal**: AI coding agent control

- [ ] Build JSON-RPC server (stdio mode)
- [ ] Implement MCP protocol handlers
- [ ] Add tool definitions (manage_instances, send_message, etc.)
- [ ] Create Claude Code configuration examples
- [ ] Test with Cursor/Cline

**Deliverable**: Claude can control Jido.Chat via MCP

---

### Phase 9: Production Hardening (Weeks 17-18)

**Goal**: Production readiness

- [ ] Add comprehensive error handling
- [ ] Implement retry logic with backoff
- [ ] Add circuit breakers for external services
- [ ] Build health check endpoints
- [ ] Add load testing
- [ ] Create deployment documentation

**Deliverable**: Production-grade reliability

---

### Phase 10: Additional Channels (Ongoing)

**Goal**: Expand channel support

- [ ] Slack integration
- [ ] Telegram integration
- [ ] SMS (Twilio)
- [ ] Microsoft Teams
- [ ] Custom webhook channels

---

## Code Examples

### Complete Message Flow Example

```elixir
# 1. Webhook arrives from WhatsApp
# POST /webhooks/customer-support

# 2. WebhookController receives it
defmodule MyAppWeb.WebhookController do
  def receive(conn, %{"instance_name" => "customer-support"} = params) do
    # Start trace
    {:ok, trace_id} = Trace.Context.start_trace("customer-support", params["from"])
    Trace.Context.log_stage(trace_id, "webhook_received", params)
    
    # Route to MessageRouter
    MessageRouter.route("customer-support", params, trace_id)
    send_resp(conn, :ok, "")
  end
end

# 3. MessageRouter orchestrates the flow
defmodule Jido.Chat.MessageRouter do
  def route(instance_name, webhook_payload, trace_id) do
    # Get instance config
    {:ok, instance} = Instance.get_by_name(instance_name)
    
    # Check access control
    user_id = extract_user_id(webhook_payload)
    Trace.Context.log_stage(trace_id, "access_control", %{user_id: user_id})
    
    case AccessControl.check(instance.access_rules, user_id) do
      :allow ->
        # Normalize webhook to internal message format
        {:ok, message} = normalize_message(webhook_payload, instance.channel_type)
        
        # Send to AI agent
        Trace.Context.log_stage(trace_id, "agent_request", message)
        {:ok, agent_response} = Agent.Client.send_message(instance.agent_config, message)
        Trace.Context.log_stage(trace_id, "agent_response", %{response: agent_response})
        
        # Format response for channel
        formatted = format_for_channel(agent_response, instance)
        Trace.Context.log_stage(trace_id, "formatting", formatted)
        
        # Send via channel
        {:ok, channel_handler} = Channel.Factory.get_handler(instance.channel_type)
        {:ok, channel_state} = channel_handler.init(instance.channel_config)
        {:ok, result} = channel_handler.send_text(channel_state, message.from, formatted)
        
        Trace.Context.log_stage(trace_id, "send", result)
        Trace.Context.finalize_trace(trace_id)
        
        :ok
      
      :deny ->
        Trace.Context.log_stage(trace_id, "access_control", %{result: :denied}, 403)
        Trace.Context.finalize_trace(trace_id)
        {:error, :access_denied}
    end
  end
end
```

### Creating an Instance via API

```bash
# Create WhatsApp instance
curl -X POST http://localhost:4000/api/v1/instances \
  -H "Authorization: Bearer API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "instance": {
      "name": "customer-support",
      "channel_type": "whatsapp",
      "channel_config": {
        "evolution_url": "http://localhost:8080",
        "evolution_key": "EVOLUTION_API_KEY",
        "instance_name": "customer-support"
      },
      "agent_config": {
        "api_url": "https://api.hive.ai/v1",
        "api_key": "HIVE_API_KEY",
        "instance_type": "hive"
      },
      "access_rules": {
        "whitelist": ["+1234567890"],
        "default_policy": "allow"
      },
      "enable_auto_split": true
    }
  }'

# Response
{
  "data": {
    "id": "01234567-89ab-cdef-0123-456789abcdef",
    "name": "customer-support",
    "channel_type": "whatsapp",
    "is_active": true,
    "created_at": "2025-12-23T10:00:00Z"
  }
}
```

### Querying Omni Contacts

```elixir
# GET /omni/customer-support/contacts?page=1&page_size=20&search=john

# Controller handles this
defmodule MyAppWeb.OmniController do
  def contacts(conn, params) do
    instance_name = params["instance_name"]
    opts = [
      page: String.to_integer(params["page"] || "1"),
      page_size: String.to_integer(params["page_size"] || "50"),
      search: params["search"]
    ]
    
    {:ok, contacts} = Instance.get_contacts(instance_name, opts)
    json(conn, %{data: contacts})
  end
end

# Instance delegates to channel handler
defmodule Jido.Chat.Instance do
  def get_contacts(instance_name, opts) do
    {:ok, instance} = get_by_name(instance_name)
    {:ok, handler} = Channel.Factory.get_handler(instance.channel_type)
    {:ok, state} = handler.init(instance.channel_config)
    handler.get_contacts(state, opts)
  end
end

# WhatsApp handler makes Evolution API call
defmodule Jido.Chat.Channel.WhatsApp do
  def get_contacts(state, opts) do
    url = "#{state.evolution_url}/contacts/#{state.instance_name}"
    params = %{
      page: opts[:page],
      pageSize: opts[:page_size],
      search: opts[:search]
    }
    
    case HTTP.get(url, headers: auth_headers(state), params: params) do
      {:ok, %{body: body}} ->
        {:ok, normalize_contacts(body)}
      error -> error
    end
  end
  
  defp normalize_contacts(raw_contacts) do
    Enum.map(raw_contacts, fn contact ->
      %{
        id: contact["id"],
        name: contact["name"] || contact["pushName"],
        phone: contact["id"],
        profile_picture: contact["profilePicUrl"]
      }
    end)
  end
end
```

---

## Migration Strategy

### Backward Compatibility

To ensure existing Jido.Chat users aren't disrupted:

1. **Keep current API intact**: `Jido.Chat.create_room/2`, `send_message/3`, etc.
2. **Add new API alongside**: `Jido.Chat.Instance.create/1`, `Instance.send_text/3`
3. **Adapter layer**: Wrap old room API to work with new instance system
4. **Deprecation path**: Mark old APIs as deprecated after 2-3 releases

### Example Compatibility Layer

```elixir
defmodule Jido.Chat do
  @deprecated "Use Jido.Chat.Instance.create/1 instead"
  def create_room(name, opts) do
    # Convert to instance format
    instance_config = %{
      name: name,
      channel_type: :internal,
      agent_config: opts[:agent_config] || %{},
      # ... map other opts
    }
    Instance.create(instance_config)
  end
end
```

---

## Conclusion

Transforming Jido.Chat into an Omni-style platform requires:

1. **Multi-instance architecture** with `DynamicSupervisor` and per-instance GenServers
2. **Channel abstraction layer** using Elixir behaviours and factory pattern
3. **Streaming agent support** via Mint/Finch with SSE parsing
4. **Comprehensive tracing** using Telemetry and Ecto persistence
5. **Phoenix integration** with controllers, webhooks, and RESTful APIs

The Elixir/OTP platform provides **excellent primitives** for this:
- GenServers for stateful instances
- Supervision trees for fault tolerance
- Phoenix for HTTP/webhook handling
- Ecto for database persistence
- Telemetry for observability

This architecture maintains Jido.Chat's **elegant functional core** while adding the **production-grade infrastructure** needed for multi-channel AI agent orchestration at scale.
