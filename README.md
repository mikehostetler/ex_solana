# Jido Character

[![Hex.pm](https://img.shields.io/hexpm/v/jido_character.svg)](https://hex.pm/packages/jido_character)
[![Documentation](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/jido_character)
[![License](https://img.shields.io/hexpm/l/jido_character.svg)](https://github.com/agentjido/jido_character/blob/main/LICENSE)

Extensible character definition and context rendering for AI agents. Define composable personalities with identity, voice, memory, and knowledge—then render directly to LLM prompts via [ReqLLM](https://github.com/agentjido/req_llm).

- **Zoi-validated schemas** — Character data validated at runtime with rich error messages
- **Immutable updates** — All mutations return new character maps with version tracking
- **Module-based templates** — `use Jido.Character` for reusable character types with defaults
- **LLM-ready rendering** — Direct integration with `ReqLLM.Context` for prompt insertion
- **Pluggable persistence** — Adapter pattern for custom storage (ETS-backed Memory adapter included)

## Installation

```elixir
def deps do
  [
    {:jido_character, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Create a character with auto-generated ID
{:ok, bob} = Jido.Character.new(%{
  name: "Bob",
  identity: %{role: "Technical advisor", background: "15 years in software"},
  personality: %{traits: ["analytical", "patient"], values: ["clarity", "accuracy"]},
  voice: %{tone: :professional, style: "Concise and precise"}
})

# Use pipe-friendly helpers (version auto-increments)
{:ok, bob} = Jido.Character.add_knowledge(bob, "Expert in Elixir", category: "skills")
{:ok, bob} = Jido.Character.add_instruction(bob, "Always explain your reasoning")

# Render to system prompt for any LLM
prompt = Jido.Character.to_system_prompt(bob)

# Or get a ReqLLM.Context for full conversation management
context = Jido.Character.to_context(bob)
```

## Module-Based Characters

Define reusable character templates with the `use Jido.Character` macro:

```elixir
defmodule MyApp.Characters.Alice do
  use Jido.Character,
    defaults: %{
      name: "Alice",
      description: "A curious research assistant",
      identity: %{
        role: "Research Assistant",
        background: "Former academic with expertise in emerging technologies"
      },
      personality: %{
        traits: [%{name: "curious", intensity: 0.9}, "methodical"],
        values: ["accuracy", "clarity"]
      },
      voice: %{
        tone: :warm,
        style: "Conversational but precise"
      }
    },
    adapter: Jido.Character.Persistence.Memory
end

# Create instance with defaults
{:ok, alice} = MyApp.Characters.Alice.new()

# Override specific fields
{:ok, alice} = MyApp.Characters.Alice.new(%{name: "Alicia"})

# Persist using configured adapter
{:ok, alice} = MyApp.Characters.Alice.save(alice)

# Access module configuration
MyApp.Characters.Alice.definition()   #=> %Jido.Character.Definition{...}
MyApp.Characters.Alice.defaults()     #=> %{name: "Alice", ...}
MyApp.Characters.Alice.extensions()   #=> []
```

### Generated Functions

The `use Jido.Character` macro generates these functions:

| Function | Description |
|----------|-------------|
| `new/0`, `new/1` | Create instance with defaults merged |
| `update/2` | Update character immutably |
| `validate/1` | Validate character attributes |
| `to_context/1,2` | Render to `ReqLLM.Context` |
| `to_system_prompt/1,2` | Render to system prompt string |
| `save/1` | Persist via configured adapter |
| `add_knowledge/2,3` | Add knowledge item(s) |
| `add_instruction/2` | Add instruction(s) |
| `add_memory/2,3` | Add memory entry |
| `add_trait/2,3` | Add personality trait(s) |
| `add_value/2` | Add personality value(s) |
| `add_quirk/2` | Add personality quirk(s) |
| `add_expression/2` | Add voice expression(s) |
| `add_fact/2` | Add identity fact(s) |
| `definition/0` | Return module configuration |
| `defaults/0` | Return default attributes |
| `extensions/0` | Return enabled extensions |
| `adapter/0` | Return configured adapter |
| `adapter_opts/0` | Return adapter options |
| `renderer/0` | Return configured renderer |
| `renderer_opts/0` | Return renderer options |

All generated functions are `defoverridable` for customization.

## Pipe-Friendly Helpers

Build characters incrementally with chainable helper methods:

```elixir
{:ok, bob} = Jido.Character.new(%{name: "Bob"})

# Add knowledge (string shorthand or with options)
{:ok, bob} = Jido.Character.add_knowledge(bob, "Expert in Elixir")
{:ok, bob} = Jido.Character.add_knowledge(bob, "Knows Python", category: "skills", importance: 0.8)

# Add instructions
{:ok, bob} = Jido.Character.add_instruction(bob, "Always be helpful")
{:ok, bob} = Jido.Character.add_instruction(bob, ["Be concise", "Cite sources"])

# Add personality traits (string or with intensity)
{:ok, bob} = Jido.Character.add_trait(bob, "curious")
{:ok, bob} = Jido.Character.add_trait(bob, "analytical", intensity: 0.9)

# Add values and quirks
{:ok, bob} = Jido.Character.add_value(bob, "accuracy")
{:ok, bob} = Jido.Character.add_quirk(bob, "Uses analogies frequently")

# Add memory entries (with optional importance/decay)
{:ok, bob} = Jido.Character.add_memory(bob, "User prefers brief answers", importance: 0.8)

# Add voice expressions
{:ok, bob} = Jido.Character.add_expression(bob, "Let me think about that...")

# Add identity facts
{:ok, bob} = Jido.Character.add_fact(bob, "Has a PhD in Computer Science")
```

Each helper returns `{:ok, updated_character}` with version auto-incremented. All helpers are available on both the direct API and module-based characters.

## Custom Renderers

By default, characters render to Markdown-formatted system prompts. You can customize rendering by implementing the `Jido.Character.Renderer` behaviour.

### Implementing a Custom Renderer

```elixir
defmodule MyApp.JSONRenderer do
  @behaviour Jido.Character.Renderer

  @impl true
  def to_system_prompt(character, _opts) do
    Jason.encode!(%{
      name: character.name,
      role: get_in(character, [:identity, :role]),
      instructions: Map.get(character, :instructions, [])
    })
  end

  @impl true
  def to_context(character, opts) do
    prompt = to_system_prompt(character, opts)
    ReqLLM.Context.new([ReqLLM.Context.system(prompt)])
  end
end
```

The `to_context/2` callback is optional. If not implemented, the dispatcher wraps the result of `to_system_prompt/2` in a `ReqLLM.Context`.

### Using Custom Renderers

**Per-call:**

```elixir
prompt = Jido.Character.to_system_prompt(bob, renderer: MyApp.JSONRenderer)
```

**Per-module (module-based characters):**

```elixir
defmodule MyApp.Characters.APIBot do
  use Jido.Character,
    defaults: %{name: "APIBot"},
    renderer: MyApp.JSONRenderer,
    renderer_opts: [format: :compact]
end
```

**Global configuration:**

```elixir
# config/config.exs
config :jido_character, Jido.Character.Renderer,
  renderer: MyApp.JSONRenderer,
  renderer_opts: []
```

### Configuration Priority

Renderers are resolved in this order:
1. Per-call options (`:renderer` key)
2. Module defaults (for module-based characters)
3. Global application config
4. Built-in Markdown renderer (default)

## Using with ReqLLM

Characters integrate seamlessly with ReqLLM for LLM interactions:

```elixir
{:ok, character} = Jido.Character.new(%{
  name: "Helper",
  personality: %{traits: ["helpful", "concise"]}
})

# Get context with character as system message
context = Jido.Character.to_context(character)

# Add user message and generate response
{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-haiku-4-5",
  ReqLLM.Context.add_user(context, "Explain recursion in Elixir")
)
```

## Character Schema

Characters are plain Elixir maps validated by Zoi schemas. All fields except `id` are optional.

### Core Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Auto-generated UUID7 (required) |
| `name` | string | Display name (max 100 chars) |
| `description` | string | Brief description (max 2000 chars) |
| `version` | integer | Auto-incremented on updates |
| `created_at` | DateTime | Set on creation |
| `updated_at` | DateTime | Updated on every change |

### Identity

Who the character is—their background and role.

```elixir
%{
  identity: %{
    role: "Research Assistant",
    age: 30,                    # or "30s", "ancient", "ageless"
    background: "Former academic with expertise in AI",
    facts: ["Has a PhD in Computer Science", "Worked at three startups"]
  }
}
```

### Personality

How the character behaves and what they value.

```elixir
%{
  personality: %{
    # Traits can be strings or maps with intensity
    traits: [
      "curious",
      %{name: "analytical", intensity: 0.9},
      %{name: "patient", intensity: 0.7}
    ],
    values: ["accuracy", "efficiency", "clarity"],
    quirks: ["Uses analogies frequently", "Asks clarifying questions"]
  }
}
```

### Voice

How the character communicates.

```elixir
%{
  voice: %{
    tone: :warm,          # :formal, :casual, :playful, :serious, :warm, :cold, :professional, :friendly
    style: "Conversational but precise. Avoids jargon unless necessary.",
    vocabulary: :technical,  # :simple, :technical, :academic, :conversational, :poetic
    expressions: ["Let me think about that...", "Here's an interesting angle..."]
  }
}
```

### Memory

Experiences that fade over time based on importance and decay rate.

```elixir
%{
  memory: %{
    capacity: 100,
    entries: [
      %{
        content: "User mentioned they're learning Elixir",
        importance: 0.8,      # 0.0-1.0, higher = more memorable
        decay_rate: 0.05,     # 0.0-1.0, lower = slower fade
        category: "user_info"
      }
    ]
  }
}
```

**Memory Decay Model:**

Effective importance decreases over time: `effective = importance × (1 - decay_rate)^days`

| Scenario | Importance | Decay | After 7 Days | After 30 Days |
|----------|------------|-------|--------------|---------------|
| Important conversation | 0.9 | 0.02 | 0.78 | 0.45 |
| Casual chat | 0.3 | 0.2 | 0.06 | ~0 |
| Traumatic event | 1.0 | 0.0 | 1.0 | 1.0 |

### Knowledge

Permanent facts the character knows (no decay).

```elixir
%{
  knowledge: [
    %{content: "Expert in Elixir and functional programming", category: "skills", importance: 0.9},
    %{content: "Familiar with machine learning concepts", category: "skills", importance: 0.7}
  ]
}
```

### Instructions

Behavioral guidelines rendered in the system prompt.

```elixir
%{
  instructions: [
    "Always cite sources when providing factual information",
    "Ask for clarification if a question is ambiguous",
    "Prefer concise answers but offer to elaborate"
  ]
}
```

### Extensions

Custom data for domain-specific needs.

```elixir
%{
  extensions: %{
    my_app: %{custom_field: "value"}
  }
}
```

## Persistence

Characters can be persisted using adapters. The included Memory adapter uses ETS:

```elixir
defmodule MyApp.Characters.Bot do
  use Jido.Character,
    adapter: Jido.Character.Persistence.Memory,
    adapter_opts: [],
    defaults: %{name: "Bot"}
end

{:ok, bot} = MyApp.Characters.Bot.new()
{:ok, saved} = MyApp.Characters.Bot.save(bot)

# Retrieve via adapter directly
adapter = MyApp.Characters.Bot.adapter()
defn = MyApp.Characters.Bot.definition()
{:ok, retrieved} = adapter.get(defn, saved.id)
```

### Custom Adapters

Implement `Jido.Character.Persistence.Adapter` for custom storage:

```elixir
defmodule MyApp.PostgresAdapter do
  @behaviour Jido.Character.Persistence.Adapter

  @impl true
  def save(definition, character) do
    # Save to PostgreSQL
    {:ok, character}
  end

  @impl true
  def get(definition, id) do
    # Retrieve from PostgreSQL
    {:ok, character}
  end

  @impl true
  def delete(definition, id) do
    # Delete from PostgreSQL
    :ok
  end

  @impl true
  def list(definition, opts \\ []) do
    # List characters
    {:ok, []}
  end
end
```

## API Reference

### Direct API

```elixir
# Create
{:ok, char} = Jido.Character.new(%{name: "Name"})

# Update (immutable, increments version)
{:ok, char} = Jido.Character.update(char, %{description: "Updated"})

# Validate without creating
{:ok, validated} = Jido.Character.validate(%{id: "test", name: "Valid"})
{:error, errors} = Jido.Character.validate(%{})  # missing id

# Render to LLM context
context = Jido.Character.to_context(char)
prompt = Jido.Character.to_system_prompt(char)
```

### Definition Struct

Module configuration for `use Jido.Character`:

```elixir
%Jido.Character.Definition{
  module: MyApp.Characters.Alice,  # The defining module
  extensions: [],                   # Enabled extensions
  defaults: %{name: "Alice"},      # Default attributes
  adapter: Jido.Character.Persistence.Memory,
  adapter_opts: []
}
```

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run quality checks (format, compile, credo, dialyzer)
mix quality

# Generate documentation
mix docs
```

## Roadmap

- **Phase 1** ✅ Foundation (current) — Zoi schemas, `use` macro, direct API, Memory adapter
- **Phase 2** 🔜 Extensions — Extension behaviour, Memory/Relationships/Goals extensions
- **Phase 3** 🔜 Persistence — ETS adapter, per-module adapter config, version history
- **Phase 4** 🔜 Polish — Guides, property-based tests, examples
- **Phase 5** 🔜 Release — Hex.pm publication

## License

Copyright 2025 Mike Hostetler

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
