# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- changelog -->

## [1.0.0] - 2025-12-23

### Added

- **Core API** - `new/1`, `new!/1`, `update/2`, `update!/2`, `validate/1` for character lifecycle
- **LLM Integration** - `to_context/2`, `to_system_prompt/2` for direct ReqLLM integration
- **Evolution** - `evolve/2`, `evolve!/2` for simulating character aging and memory decay
- **Pipe-friendly helpers** for building characters incrementally:
  - `add_knowledge/2,3` - Add knowledge items with optional category/importance
  - `add_instruction/2` - Add behavioral instructions
  - `add_memory/2,3` - Add memory entries with capacity enforcement
  - `add_trait/2,3` - Add personality traits with optional intensity
  - `add_value/2` - Add personality values
  - `add_quirk/2` - Add personality quirks
  - `add_expression/2` - Add voice expressions
  - `add_fact/2` - Add identity facts
- **`use Jido.Character` macro** for module-based character definitions with:
  - Default attributes
  - Extension configuration
  - Adapter/renderer configuration
  - All generated functions are `defoverridable`
- **Zoi-based validation schemas** with typed sub-modules:
  - `Jido.Character.Schema.Identity` - Role, age, background, facts
  - `Jido.Character.Schema.Personality` - Traits, values, quirks
  - `Jido.Character.Schema.Voice` - Tone, style, vocabulary, expressions
  - `Jido.Character.Schema.Memory` - Entries with decay, capacity limits
  - `Jido.Character.Schema.MemoryEntry` - Individual memory items
  - `Jido.Character.Schema.KnowledgeItem` - Permanent facts
  - `Jido.Character.Schema.Trait` - Traits with intensity
- **Pluggable Renderer behaviour** with dispatcher for custom prompt formats
- **Persistence behaviour** with Memory adapter using ETS
- **Memory decay model** - Importance decreases over time based on decay rate
- **Memory capacity enforcement** - Oldest entries dropped when over limit
- **Comprehensive type specifications** for Dialyzer compatibility
