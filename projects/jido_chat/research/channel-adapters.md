# Channel Adapter Design Research

## Overview

Channel adapters are the **edge layer** of JIDO_CHAT_V2 - they translate platform-specific events into normalized messages and vice versa.

## Core Questions

### 1. How do we handle platform-specific features?

**Examples**:
- Slack: Threads, ephemeral messages, Block Kit, slash commands
- WhatsApp: Media (images, voice notes), reactions, status updates
- Discord: Embeds, voice channels, server-specific features
- SMS: Character limits, MMS, delivery receipts

**Proposed Approach**:

```elixir
# Normalized message supports "rich" content
%Message{
  content: %{
    type: :rich,
    text: "Primary text",
    
    # Platform-agnostic representations
    attachments: [
      %{type: :image, url: "...", caption: "..."},
      %{type: :file, url: "...", filename: "...", mime_type: "..."}
    ],
    
    # Interactive components
    buttons: [
      %{id: "btn1", label: "Approve", style: :primary, value: "approve"},
      %{id: "btn2", label: "Reject", style: :danger, value: "reject"}
    ],
    
    # Platform-specific (preserved for rendering)
    platform_extensions: %{
      slack: %{
        blocks: [...],  # Full Block Kit
        thread_ts: "..."
      },
      whatsapp: %{
        quoted_message_id: "...",
        reaction: "👍"
      }
    }
  }
}
```

**Trade-offs**:
- ✅ Supports rich interactions
- ✅ Platform extensions preserved
- ❌ Complexity in normalization
- ❌ Lowest-common-denominator for cross-platform

**Research Tasks**:
- [ ] Survey top 20 message types per platform
- [ ] Design button/card abstraction (what can work everywhere?)
- [ ] Define attachment normalization (images, videos, files, voice)
- [ ] Handle threading semantics (Slack threads vs WhatsApp quotes)

---

### 2. Interactive Components Abstraction

**Challenge**: Different platforms have different interaction models:
- Slack: Block Kit (buttons, select menus, modals)
- WhatsApp: List messages, button messages, quick replies
- Discord: Components (buttons, select menus, embeds)
- SMS: Text-only (use numbered options)

**Proposed Abstraction**:

```elixir
defmodule Jido.Chat.V2.InteractiveComponent do
  @type button :: %{
    id: String.t(),
    label: String.t(),
    value: any(),
    style: :primary | :secondary | :danger | :link
  }
  
  @type select_option :: %{
    value: String.t(),
    label: String.t(),
    description: String.t() | nil
  }
  
  @type card :: %{
    title: String.t(),
    description: String.t(),
    image_url: String.t() | nil,
    buttons: [button()]
  }
  
  # Adapters translate these to platform-specific format
  @callback render_buttons(state, text :: String.t(), buttons :: [button()]) :: {:ok, payload}
  @callback render_select(state, text :: String.t(), options :: [select_option()]) :: {:ok, payload}
  @callback render_card(state, card) :: {:ok, payload}
end
```

**Adapter Implementations**:

```elixir
# Slack: Translate to Block Kit
defmodule Channel.Slack do
  def render_buttons(_state, text, buttons) do
    blocks = [
      %{type: "section", text: %{type: "mrkdwn", text: text}},
      %{
        type: "actions",
        elements: Enum.map(buttons, fn btn ->
          %{
            type: "button",
            action_id: btn.id,
            text: %{type: "plain_text", text: btn.label},
            value: btn.value,
            style: map_style(btn.style)
          }
        end)
      }
    ]
    {:ok, %{blocks: blocks}}
  end
end

# WhatsApp: Translate to button message
defmodule Channel.WhatsApp do
  def render_buttons(_state, text, buttons) do
    # WhatsApp limits: 3 buttons max
    buttons = Enum.take(buttons, 3)
    
    payload = %{
      text: text,
      buttons: Enum.map(buttons, fn btn ->
        %{id: btn.id, title: btn.label}
      end)
    }
    {:ok, payload}
  end
end

# SMS: Fallback to numbered list
defmodule Channel.SMS do
  def render_buttons(_state, text, buttons) do
    numbered_options = buttons
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {btn, idx} -> "#{idx}. #{btn.label}" end)
    
    full_text = "#{text}\n\n#{numbered_options}\n\nReply with the number of your choice."
    {:ok, %{text: full_text}}
  end
end
```

**Research Tasks**:
- [ ] Define common component types (buttons, selects, cards, forms)
- [ ] Map component limits per platform (WhatsApp: 3 buttons, Slack: 25)
- [ ] Design fallback strategies (SMS gets numbered lists)
- [ ] Handle modal/dialog flows

---

### 3. Attachment Normalization

**Challenge**: Different platforms support different media types:
- Images: All platforms (different size limits)
- Videos: Most platforms (different codecs/durations)
- Files: Slack, Discord, Email (not WhatsApp Business)
- Voice notes: WhatsApp, Telegram (not Slack)

**Proposed Strategy**:

```elixir
defmodule Jido.Chat.V2.Attachment do
  defstruct [
    :type,        # :image | :video | :audio | :file | :location
    :url,         # Public URL or base64
    :mime_type,
    :size_bytes,
    :filename,
    :caption,
    :metadata     # Platform-specific (duration, dimensions, etc.)
  ]
  
  # Validation per platform
  def validate_for_platform(attachment, platform) do
    case {attachment.type, platform} do
      {:image, :whatsapp} when attachment.size_bytes > 5_000_000 ->
        {:error, :image_too_large}
      
      {:video, :whatsapp} when attachment.size_bytes > 16_000_000 ->
        {:error, :video_too_large}
      
      {:file, :whatsapp} ->
        {:error, :files_not_supported}
      
      _ ->
        :ok
    end
  end
end
```

**Adapter Responsibility**:

```elixir
defmodule Channel.WhatsApp do
  def send_media(state, to, attachment) do
    # Convert to WhatsApp format
    case Attachment.validate_for_platform(attachment, :whatsapp) do
      :ok ->
        payload = %{
          to: to,
          type: map_media_type(attachment.type),
          [attachment.type] => %{
            url: attachment.url,
            caption: attachment.caption
          }
        }
        EvolutionAPI.send_media(state.client, state.instance, payload)
      
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**Research Tasks**:
- [ ] Survey media type support matrix
- [ ] Define size/duration limits per platform
- [ ] Design media transcoding strategy (if needed)
- [ ] Handle media storage (CDN, temporary URLs)

---

### 4. Built-in vs Plugin Adapters

**Options**:

**Option A: Built-in Adapters** (current recommendation)
- Pros: Batteries included, guaranteed compatibility
- Cons: Harder to extend, maintenance burden

**Option B: Plugin Architecture**
- Pros: Community extensibility, focused core
- Cons: Version fragmentation, quality variance

**Proposed Hybrid**:

```elixir
# Core adapters (built-in)
- Jido.Chat.V2.Channel.WhatsApp
- Jido.Chat.V2.Channel.Slack
- Jido.Chat.V2.Channel.Discord

# Plugin adapters (community)
- JidoChat.Channel.Telegram (separate hex package)
- JidoChat.Channel.Teams (separate hex package)

# Plugin registration
config :jido_chat_v2,
  custom_channels: [
    telegram: JidoChat.Channel.Telegram,
    teams: JidoChat.Channel.Teams
  ]
```

**Research Tasks**:
- [ ] Define adapter plugin protocol
- [ ] Design adapter discovery mechanism
- [ ] Build adapter testing framework
- [ ] Create adapter starter template

---

## Implementation Examples

### WhatsApp Adapter (Evolution API)

```elixir
defmodule Jido.Chat.V2.Channel.WhatsApp do
  @behaviour Jido.Chat.V2.Channel
  
  alias Jido.Chat.V2.{Message, Attachment}
  
  defstruct [:client, :instance_name, :config]
  
  @impl true
  def init(instance_config) do
    client = EvolutionAPI.Client.new(
      instance_config.evolution_url,
      instance_config.evolution_key
    )
    
    {:ok, %__MODULE__{
      client: client,
      instance_name: instance_config.instance_name,
      config: instance_config
    }}
  end
  
  @impl true
  def normalize_incoming(state, %{"data" => data} = _raw) do
    {:ok, %{
      type: detect_event_type(data),
      external_room_ref: data["key"]["remoteJid"],
      external_user_ref: extract_sender(data),
      text: extract_text_content(data),
      attachments: extract_attachments(data),
      metadata: %{
        message_id: data["key"]["id"],
        timestamp: data["messageTimestamp"],
        quoted_message: data["message"]["extendedTextMessage"]["contextInfo"]
      }
    }}
  end
  
  @impl true
  def send_text(state, to, text) do
    EvolutionAPI.send_text(state.client, state.instance_name, to, text)
  end
  
  @impl true
  def send_buttons(state, to, text, buttons) do
    # WhatsApp button format
    payload = %{
      text: text,
      buttons: buttons |> Enum.take(3) |> Enum.map(&format_button/1)
    }
    EvolutionAPI.send_buttons(state.client, state.instance_name, to, payload)
  end
  
  @impl true
  def get_contacts(state, opts) do
    EvolutionAPI.get_contacts(state.client, state.instance_name, opts)
  end
  
  defp detect_event_type(data) do
    cond do
      data["message"]["conversation"] -> :message
      data["message"]["imageMessage"] -> :message
      data["message"]["reactionMessage"] -> :reaction
      true -> :other
    end
  end
end
```

### Slack Adapter (Events API)

```elixir
defmodule Jido.Chat.V2.Channel.Slack do
  @behaviour Jido.Chat.V2.Channel
  
  defstruct [:token, :team_id, :config]
  
  @impl true
  def init(instance_config) do
    {:ok, %__MODULE__{
      token: instance_config.bot_token,
      team_id: instance_config.team_id,
      config: instance_config
    }}
  end
  
  @impl true
  def normalize_incoming(state, %{"event" => event}) do
    {:ok, %{
      type: event_type(event["type"]),
      external_room_ref: event["channel"],
      external_user_ref: event["user"],
      text: event["text"],
      attachments: normalize_slack_files(event["files"]),
      metadata: %{
        ts: event["ts"],
        thread_ts: event["thread_ts"],
        event_id: event["event_id"]
      }
    }}
  end
  
  @impl true
  def send_text(state, channel, text) do
    Slack.Web.Chat.post_message(channel, text, state.token)
  end
  
  @impl true
  def send_buttons(state, channel, text, buttons) do
    blocks = build_block_kit_buttons(text, buttons)
    Slack.Web.Chat.post_message(channel, blocks: blocks, token: state.token)
  end
  
  defp build_block_kit_buttons(text, buttons) do
    [
      %{type: "section", text: %{type: "mrkdwn", text: text}},
      %{
        type: "actions",
        elements: Enum.map(buttons, fn btn ->
          %{
            type: "button",
            action_id: btn.id,
            text: %{type: "plain_text", text: btn.label},
            value: Jason.encode!(btn.value),
            style: map_button_style(btn.style)
          }
        end)
      }
    ]
  end
end
```

---

## Testing Strategy

### Adapter Contract Tests

```elixir
defmodule Jido.Chat.V2.ChannelContractTest do
  @moduledoc """
  Shared contract tests that all adapters must pass.
  """
  
  defmacro __using__(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    
    quote do
      test "normalize_incoming handles text messages" do
        state = setup_adapter_state(unquote(adapter))
        raw_event = build_text_message_fixture(unquote(adapter))
        
        assert {:ok, normalized} = unquote(adapter).normalize_incoming(state, raw_event)
        assert normalized.type == :message
        assert is_binary(normalized.text)
        assert is_binary(normalized.external_room_ref)
      end
      
      test "send_text delivers message" do
        state = setup_adapter_state(unquote(adapter))
        
        assert {:ok, _result} = unquote(adapter).send_text(state, "test_room", "Hello")
      end
      
      # ... more contract tests ...
    end
  end
end

# Usage
defmodule WhatsAppAdapterTest do
  use ExUnit.Case
  use Jido.Chat.V2.ChannelContractTest, adapter: Channel.WhatsApp
  
  # Adapter-specific tests
  test "handles WhatsApp media messages" do
    # ...
  end
end
```

---

## Next Steps

1. **Prototype** 3 adapters (WhatsApp, Slack, Discord)
2. **Document** normalization mapping for each platform
3. **Build** interactive component abstraction
4. **Test** cross-platform message flows
5. **Define** adapter plugin protocol
