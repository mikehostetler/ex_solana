<!--
SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Common Development Commands

### Testing
```bash
# Create and migrate test database
mix test.create && mix test.migrate

# Run all tests
mix test

# Run a specific test file
mix test test/path/to/test_file.exs

# Run a specific test by line number
mix test test/path/to/test_file.exs:42
```

### Code Quality
```bash
# Run all checks (formatting, credo, dialyzer, sobelow)
mix check

# Format code
mix format

# Check formatting
mix format --check

# Run Credo for code analysis
mix credo --strict

# Run Dialyzer for type checking
mix dialyzer

# Security analysis
mix sobelow --skip
```

### Documentation
```bash
# Generate documentation
mix docs

# Generate Spark cheat sheets
mix spark.cheat_sheets --extensions AshAi
```

### Database Operations (Test Environment)
```bash
# Generate migrations
mix test.generate_migrations

# Check if migrations are up to date
mix test.check_migrations

# Reset test database completely
mix test.reset

# Full reset (regenerate migrations + reset)
mix test.full_reset
```

## Code Architecture

### Core Concepts

1. **Spark DSL Extension**: AshAi extends Ash resources and domains through Spark DSL, adding AI capabilities without modifying core Ash behavior.

2. **Tool Exposure Pattern**: Actions from Ash resources are exposed as tools that LLMs can call. The exposure happens at the domain level:
   ```elixir
   tools do
     tool :tool_name, Resource, :action_name
     
     # With custom description
     tool :read_posts, Post, :read do
       description "Read all blog posts with optional filtering"
     end
     
     # With loading relationships/calculations
     tool :read_posts_with_author, Post, :read do
       load [:author, :comment_count]
     end
   end
   ```
   
   **Important Tool Considerations:**
   - Only public attributes (`public?: true`) are accessible for filtering, sorting, and aggregation
   - Private attributes cannot be filtered, sorted, or used in aggregates
   - Use the `load` option to include relationships, calculations, or additional attributes in responses
   - When using `load`, even private attributes become visible in tool responses
   - Tool descriptions help LLMs understand when and how to use each tool

3. **Prompt-Backed Actions**: Actions where the implementation is delegated to an LLM using structured outputs to ensure type safety.

4. **Vectorization System**: 
   - Supports multiple strategies (after_action, ash_oban, manual)
   - Uses transformers to inject changes and actions at compile time
   - Embeddings are stored alongside resources for semantic search

5. **MCP Server Architecture**:
   - Development server (`AshAi.Mcp.Dev`) as a Plug for rapid iteration
   - Production server with authentication support via AshAuthentication
   - Session management for stateful interactions

### Key Integration Points

- **LangChain**: Deep integration for building AI agents and chains. All tool exposure is designed to work seamlessly with LangChain's tool calling interface.
- **Ash Transformers**: Uses Spark transformers to modify resources at compile time (e.g., adding vector fields, creating update actions).
- **Oban Integration**: For asynchronous vectorization, leverages ash_oban triggers.
- **Phoenix Integration**: MCP servers integrate as plugs and routers.

### Error Handling

- All errors are transformed to JSON:API format for consistency
- Tool calls include detailed error messages for LLM consumption
- Validation errors include field-level details

### Testing Approach

- Use `AshAi.TestRepo` with Ecto sandbox for isolation
- Mock LLM responses with `ChatFaker` for predictable tests
- Test resources are defined inline within test modules to avoid pollution
- Always test both synchronous and asynchronous vectorization strategies when applicable

## Development Best Practices

- Always run mix format after changing elixir code
