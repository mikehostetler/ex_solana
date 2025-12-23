# AGENTS.md - Jido Character

## Common Commands

```bash
# Development
mix compile          # Compile the project
mix format           # Format code
mix test             # Run tests
mix coveralls        # Run tests with coverage

# Quality
mix quality          # Run full quality suite (format, compile, credo, dialyzer)
mix q                # Alias for quality

# Documentation
mix docs             # Generate documentation
```

## Project Structure

```
jido_character/
├── lib/
│   ├── jido_character.ex              # Main API and `use` macro
│   └── jido_character/
│       ├── definition.ex              # Character definition struct
│       ├── schema.ex                  # Zoi validation schemas
│       ├── context/
│       │   └── renderer.ex            # System prompt generation
│       └── persistence/
│           ├── adapter.ex             # Persistence behaviour
│           └── memory.ex              # ETS-based memory adapter
├── test/
│   ├── jido_character_test.exs        # Main API tests
│   ├── jido_character/
│   │   ├── definition_test.exs        # Definition tests
│   │   ├── schema_test.exs            # Schema validation tests
│   │   ├── context/
│   │   │   └── renderer_test.exs      # Renderer tests
│   │   └── persistence/
│   │       └── memory_test.exs        # Memory adapter tests
│   └── support/
│       └── characters.ex              # Test character modules
└── mix.exs
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Jido.Character` | Main API - `new/1`, `update/2`, `validate/1`, `to_context/2`, `to_system_prompt/2` |
| `Jido.Character.Definition` | TypedStruct for compile-time character config |
| `Jido.Character.Schema` | Zoi schemas for character validation |
| `Jido.Character.Context.Renderer` | Renders characters to Markdown system prompts |
| `Jido.Character.Persistence.Adapter` | Behaviour for persistence adapters |
| `Jido.Character.Persistence.Memory` | In-memory ETS adapter |

## Testing Patterns

### Direct API Tests

```elixir
test "creates character with defaults" do
  {:ok, char} = Jido.Character.new(%{name: "Test"})
  assert char.name == "Test"
  assert char.id != nil
end
```

### Module-Based Character Tests

```elixir
defmodule TestCharacter do
  use Jido.Character,
    defaults: %{name: "Test"}
end

test "module creates character with defaults" do
  {:ok, char} = TestCharacter.new()
  assert char.name == "Test"
end
```

### Persistence Tests

```elixir
test "saves and retrieves character" do
  {:ok, char} = TestCharacter.new()
  {:ok, saved} = TestCharacter.save(char)
  
  adapter = TestCharacter.adapter()
  defn = TestCharacter.definition()
  {:ok, retrieved} = adapter.get(defn, saved.id)
  
  assert retrieved.id == saved.id
end
```

## Dependencies

- `zoi` - Schema validation
- `typedstruct` - Struct definitions
- `req_llm` - LLM context integration
- `uniq` - UUID generation

## Code Style

- Use `@moduledoc` and `@doc` for all public modules/functions
- Prefer pattern matching over conditionals
- Use `{:ok, value}` / `{:error, reason}` tuples consistently
- Deep merge for nested map updates
