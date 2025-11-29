# Agent Guidelines for Kaizen Project

## Build & Test Commands
- `mix compile` - Compile the project
- `mix test` - Run all tests 
- `mix test test/specific_test.exs` - Run a single test file
- `mix test test/specific_test.exs:12` - Run test at specific line
- `mix format` - Format code using configured formatter
- `mix deps.get` - Get dependencies

## Project Structure
- **Main app**: Kaizen - Generic evolutionary algorithm framework in Elixir
- **Core modules**: `lib/kaizen/` contains main implementation
- **Application**: OTP application with supervisor tree (see `lib/kaizen/application.ex`)
- **Architecture**: Protocol-based system for evolutinary algorithms (see IDEA.md for detailed design)
- **Key concepts**: Evolvable protocols, fitness behaviors, mutation/selection strategies, Pareto optimization

## Code Style & Conventions  
- **Modules**: Use `@moduledoc` for module documentation, `@doc` for function docs
- **Naming**: snake_case for functions/variables, PascalCase for modules
- **Documentation**: Include examples with doctests using `iex>` format
- **Testing**: Use ExUnit with `use ExUnit.Case` and `doctest ModuleName`
- **Formatting**: Follow `.formatter.exs` configuration (inputs cover lib, test, config, mix files)
- **OTP patterns**: Use standard OTP behaviors (Application, GenServer, Supervisor)
- **Error handling**: Use `{:ok, result}` / `{:error, reason}` tuples for fallible operations

## Dependencies
- Standard Elixir ~> 1.18 with OTP application structure
