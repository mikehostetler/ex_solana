defmodule JidoCode.Tools.Definitions.ListDir do
  @moduledoc """
  Tool definition for listing directory contents with filtering support.

  This module defines the `list_dir` tool for the Lua sandbox architecture.
  The tool lists directory contents with optional glob pattern filtering to
  exclude unwanted files or directories.

  ## Execution Flow

  Tool Executor → Tools.Manager → Lua VM → `jido.list_dir` → Bridge.lua_list_dir/3 → Security.validate_path/3

  ## Features

  - Directory listing with file type indicators
  - Glob pattern filtering via ignore_patterns
  - Sorted output (directories first, then alphabetically)
  - Security boundary enforcement

  ## Usage

      # Register the tool
      :ok = Registry.register(ListDir.list_dir())

      # Get LLM-compatible format
      Tool.to_llm_function(ListDir.list_dir())

  ## See Also

  - `JidoCode.Tools.Bridge.lua_list_dir/3` - Bridge function implementation
  - `JidoCode.Tools.Security.validate_path/3` - Path validation
  - [ADR-0001](../../../notes/decisions/0001-tool-security-architecture.md) - Security architecture
  """

  alias JidoCode.Tools.Handlers.FileSystem.ListDir, as: ListDirHandler
  alias JidoCode.Tools.Tool

  @doc """
  Returns the list_dir tool definition.

  Lists directory contents with optional filtering via glob patterns.
  Returns entries with type indicators (file or directory).

  ## Parameters

  - `path` (required, string) - Path to the directory to list (relative to project root)
  - `ignore_patterns` (optional, array) - Glob patterns to filter out from results

  ## Returns

  JSON-encoded array of entries with name and type:

      ```json
      [
        {"name": "lib", "type": "directory"},
        {"name": "mix.exs", "type": "file"}
      ]
      ```

  ## Errors

  - Directory not found
  - Path outside project boundary
  - Path is a file, not a directory
  - Permission denied

  ## Examples

      # List directory contents
      %{"path" => "lib"}

      # List with filtering (exclude test files and node_modules)
      %{"path" => ".", "ignore_patterns" => ["*.test.js", "node_modules"]}

      # List subdirectory
      %{"path" => "lib/jido_code/tools"}
  """
  @spec list_dir() :: Tool.t()
  def list_dir do
    Tool.new!(%{
      name: "list_dir",
      description:
        "List directory contents with type indicators. " <>
          "Returns JSON array of entries with name and type (file or directory). " <>
          "Use ignore_patterns to filter out files matching glob patterns.",
      handler: ListDirHandler,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the directory to list (relative to project root)",
          required: true
        },
        %{
          name: "ignore_patterns",
          type: :array,
          description: "Glob patterns to exclude from the listing (e.g., [\"*.log\", \"node_modules\"])",
          required: false,
          items: :string
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
    [list_dir()]
  end
end
