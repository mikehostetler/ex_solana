defmodule JidoCode.Tools.Definitions.FileRead do
  @moduledoc """
  Tool definition for reading file contents with line numbers.

  This module defines the `read_file` tool for the Lua sandbox architecture.
  The tool reads file contents and returns them with line numbers (cat -n style),
  supporting offset and limit parameters for handling large files.

  ## Execution Flow

  Tool Executor → Tools.Manager → Lua VM → `jido.read_file` → Bridge.lua_read_file/3 → Security.atomic_read/2

  ## Features

  - Line-numbered output (1-indexed, cat -n style)
  - Offset support for reading from a specific line
  - Limit support for capping output (default: 2000 lines)
  - Long line truncation at 2000 characters
  - Binary file detection and rejection

  ## Usage

      # Register the tool
      :ok = Registry.register(FileRead.read_file())

      # Get LLM-compatible format
      Tool.to_llm_function(FileRead.read_file())

  ## See Also

  - `JidoCode.Tools.Bridge.lua_read_file/3` - Bridge function implementation
  - `JidoCode.Tools.Security.atomic_read/2` - Secure file reading
  - [ADR-0001](../../../notes/decisions/0001-tool-security-architecture.md) - Security architecture
  """

  alias JidoCode.Tools.Tool

  @default_limit 2000

  @doc """
  Returns the default line limit for file reading.

  Files are read with a maximum of #{@default_limit} lines by default to prevent
  excessive output that could overwhelm the LLM context.

  ## Examples

      iex> FileRead.default_limit()
      2000
  """
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  Returns the read_file tool definition.

  Reads file contents with line numbers, supporting pagination through
  offset and limit parameters.

  ## Parameters

  - `path` (required, string) - Path to the file to read (relative to project root)
  - `offset` (optional, integer) - Line number to start reading from (1-indexed, default: 1)
  - `limit` (optional, integer) - Maximum number of lines to read (default: #{@default_limit})

  ## Returns

  Line-numbered content in cat -n format:

      ```
           1→first line of file
           2→second line of file
           3→third line of file
      ```

  ## Errors

  - File not found
  - Path outside project boundary
  - Binary file detected
  - Permission denied

  ## Examples

      # Read entire file (up to 2000 lines)
      %{"path" => "lib/my_module.ex"}

      # Read lines 50-150
      %{"path" => "lib/my_module.ex", "offset" => 50, "limit" => 100}

      # Read first 10 lines
      %{"path" => "README.md", "limit" => 10}
  """
  @spec read_file() :: Tool.t()
  def read_file do
    Tool.new!(%{
      name: "read_file",
      description:
        "Read file contents with line numbers. Returns line-numbered output (cat -n style). " <>
          "Use offset to skip initial lines and limit to cap output. " <>
          "Default limit is #{@default_limit} lines. Long lines are truncated at 2000 characters.",
      handler: JidoCode.Tools.Handlers.FileSystem.ReadFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to read (relative to project root)",
          required: true
        },
        %{
          name: "offset",
          type: :integer,
          description: "Line number to start reading from (1-indexed, default: 1)",
          required: false,
          default: 1
        },
        %{
          name: "limit",
          type: :integer,
          description: "Maximum number of lines to read (default: #{@default_limit})",
          required: false,
          default: @default_limit
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
    [read_file()]
  end
end
