defmodule JidoCode.Tools.Definitions.Search do
  @moduledoc """
  Tool definitions for search operations.

  This module defines the tools for searching the codebase that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `grep` - Search file contents for patterns
  - `find_files` - Find files by name/glob pattern

  ## Usage

      # Register all search tools
      for tool <- Search.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      grep_tool = Search.grep()
      :ok = Registry.register(grep_tool)
  """

  alias JidoCode.Tools.Handlers.Search, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all search tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      grep(),
      find_files()
    ]
  end

  @doc """
  Returns the grep tool definition.

  Searches file contents for patterns and returns matched lines
  with file paths and line numbers.

  ## Parameters

  - `pattern` (required, string) - Regex pattern to search for
  - `path` (required, string) - Directory or file to search in
  - `recursive` (optional, boolean) - Search subdirectories (default: true)
  - `max_results` (optional, integer) - Maximum matches to return (default: 100)
  """
  @spec grep() :: Tool.t()
  def grep do
    Tool.new!(%{
      name: "grep",
      description:
        "Search file contents for a pattern. Returns matched lines with file paths and line numbers. " <>
          "Supports regex patterns. Use for finding code, function definitions, variable usage, etc.",
      handler: Handlers.Grep,
      parameters: [
        %{
          name: "pattern",
          type: :string,
          description:
            "Regex pattern to search for (e.g., 'def hello', 'TODO:', 'import.*React')",
          required: true
        },
        %{
          name: "path",
          type: :string,
          description: "Directory or file to search in (relative to project root)",
          required: true
        },
        %{
          name: "recursive",
          type: :boolean,
          description: "Whether to search subdirectories (default: true)",
          required: false
        },
        %{
          name: "max_results",
          type: :integer,
          description: "Maximum number of matches to return (default: 100)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the find_files tool definition.

  Finds files by name or glob pattern.

  ## Parameters

  - `pattern` (required, string) - Glob pattern or filename to find
  - `path` (optional, string) - Directory to search in (default: project root)
  - `max_results` (optional, integer) - Maximum files to return (default: 100)
  """
  @spec find_files() :: Tool.t()
  def find_files do
    Tool.new!(%{
      name: "find_files",
      description:
        "Find files by name or glob pattern. Returns list of matching file paths. " <>
          "Supports glob patterns like *.ex, **/*.test.js, src/**/*.ts",
      handler: Handlers.FindFiles,
      parameters: [
        %{
          name: "pattern",
          type: :string,
          description:
            "Glob pattern or filename to find (e.g., '*.ex', 'mix.exs', '**/*_test.exs')",
          required: true
        },
        %{
          name: "path",
          type: :string,
          description: "Directory to search in (default: project root)",
          required: false
        },
        %{
          name: "max_results",
          type: :integer,
          description: "Maximum number of files to return (default: 100)",
          required: false
        }
      ]
    })
  end
end
