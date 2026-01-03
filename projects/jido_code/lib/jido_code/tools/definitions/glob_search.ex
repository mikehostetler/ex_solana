defmodule JidoCode.Tools.Definitions.GlobSearch do
  @moduledoc """
  Tool definition for pattern-based file finding.

  This module defines the `glob_search` tool for the Lua sandbox architecture.
  The tool finds files matching glob patterns with support for recursive
  matching, extensions, and brace expansion.

  ## Execution Flow

  Tool Executor → Tools.Manager → Lua VM → `jido.glob` → Bridge.lua_glob/3 → Security.validate_path/3

  ## Supported Patterns

  - `*` - Match any sequence of characters (not including path separator)
  - `**` - Match any sequence of characters including path separators (recursive)
  - `?` - Match any single character
  - `{a,b}` - Match either pattern a or pattern b (brace expansion)
  - `[abc]` - Match any character in the set

  ## Features

  - Recursive file finding with `**` pattern
  - Extension filtering (e.g., `*.ex`, `**/*.test.js`)
  - Brace expansion for multiple extensions
  - Results sorted by modification time (newest first)
  - Security boundary enforcement

  ## Usage

      # Register the tool
      :ok = Registry.register(GlobSearch.glob_search())

      # Get LLM-compatible format
      Tool.to_llm_function(GlobSearch.glob_search())

  ## See Also

  - `JidoCode.Tools.Bridge.lua_glob/3` - Bridge function implementation
  - `JidoCode.Tools.Security.validate_path/3` - Path validation
  - `Path.wildcard/2` - Underlying pattern matching
  """

  alias JidoCode.Tools.Handlers.FileSystem.GlobSearch, as: GlobSearchHandler
  alias JidoCode.Tools.Tool

  @doc """
  Returns the glob_search tool definition.

  Finds files matching a glob pattern within the project boundary.
  Results are sorted by modification time with newest files first.

  ## Parameters

  - `pattern` (required, string) - Glob pattern to match files against
  - `path` (optional, string) - Base directory to search from (defaults to project root)

  ## Returns

  JSON-encoded array of relative file paths:

      ```json
      [
        "lib/jido_code/tools/bridge.ex",
        "lib/jido_code/tools/security.ex",
        "lib/jido_code/tools/tool.ex"
      ]
      ```

  ## Pattern Examples

  | Pattern | Matches |
  |---------|---------|
  | `*.ex` | All .ex files in current directory |
  | `**/*.ex` | All .ex files recursively |
  | `lib/**/*.ex` | All .ex files under lib/ |
  | `{lib,test}/**/*.ex` | All .ex files in lib/ or test/ |
  | `**/*_test.exs` | All test files recursively |
  | `*.{ex,exs}` | All .ex and .exs files |

  ## Errors

  - Base path not found
  - Base path outside project boundary
  - Invalid pattern syntax

  ## Examples

      # Find all Elixir files
      %{"pattern" => "**/*.ex"}

      # Find all files in lib directory
      %{"pattern" => "**/*", "path" => "lib"}

      # Find test files
      %{"pattern" => "**/*_test.exs", "path" => "test"}

      # Find multiple file types
      %{"pattern" => "**/*.{ex,exs}"}
  """
  @spec glob_search() :: Tool.t()
  def glob_search do
    Tool.new!(%{
      name: "glob_search",
      description:
        "Find files matching glob pattern. " <>
          "Supports **, *, ?, {a,b}, and [abc] patterns. " <>
          "Returns JSON array of file paths sorted by modification time (newest first).",
      handler: GlobSearchHandler,
      parameters: [
        %{
          name: "pattern",
          type: :string,
          description:
            "Glob pattern to match (e.g., \"**/*.ex\" for all Elixir files, " <>
              "\"lib/**/*.ex\" for files in lib, \"{lib,test}/**/*.ex\" for multiple directories)",
          required: true
        },
        %{
          name: "path",
          type: :string,
          description: "Base directory to search from (relative to project root, defaults to \".\")",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns all tools defined in this module.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [glob_search()]
  end
end
