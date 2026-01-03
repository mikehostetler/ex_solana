defmodule JidoCode.Tools.Definitions.FileWrite do
  @moduledoc """
  Tool definition for writing file contents with security validation.

  This module defines the `write_file` tool for the Lua sandbox architecture.
  The tool writes content to files, creating parent directories if needed,
  with security validation to ensure writes stay within project boundaries.

  ## Execution Flow

  Tool Executor → Tools.Manager → Lua VM → `jido.write_file` → Bridge.lua_write_file/3 → Security.atomic_write/3

  ## Features

  - Atomic write operations (write to temp file, then rename)
  - Automatic parent directory creation
  - Project boundary enforcement
  - TOCTOU attack mitigation via Security.atomic_write
  - Protected settings file blocking (.jido_code/settings.json)

  ## Read-Before-Write Requirement

  For **existing files**, the file must be read in the current session before
  it can be overwritten. This prevents accidental overwrites and ensures the
  agent has seen the current file contents. New files can be created without
  prior reading.

  This requirement is enforced by tracking file read timestamps in the session
  state. If an attempt is made to overwrite a file that hasn't been read, the
  operation is rejected with a clear error message.

  ## Usage

      # Register the tool
      :ok = Registry.register(FileWrite.write_file())

      # Get LLM-compatible format
      Tool.to_llm_function(FileWrite.write_file())

  ## See Also

  - `JidoCode.Tools.Bridge.lua_write_file/3` - Bridge function implementation
  - `JidoCode.Tools.Security.atomic_write/3` - Secure file writing
  - `JidoCode.Tools.Definitions.FileRead` - Companion read tool
  - [ADR-0001](../../../notes/decisions/0001-tool-security-architecture.md) - Security architecture
  """

  alias JidoCode.Tools.Tool

  @doc """
  Returns the write_file tool definition.

  Writes content to a file, creating the file if it doesn't exist or
  overwriting if it does. Parent directories are created automatically.

  ## Parameters

  - `path` (required, string) - Path to the file to write (relative to project root)
  - `content` (required, string) - Content to write to the file

  ## Returns

  On success:
  - `{:ok, "File written successfully: <path>"}` for new files
  - `{:ok, "File updated successfully: <path>"}` for existing files

  On error:
  - `{:error, "File must be read before overwriting: <path>"}` - Read-before-write violation
  - `{:error, "Path outside project boundary: <path>"}` - Security violation
  - `{:error, "Cannot write to protected settings file"}` - Protected file
  - `{:error, "Permission denied: <path>"}` - Filesystem permission error

  ## Security

  All paths are validated to ensure they stay within the project boundary.
  Symlinks are followed and validated. Attempts to escape the project root
  via path traversal (../) are blocked.

  The file `.jido_code/settings.json` is protected and cannot be modified
  via this tool to prevent agents from altering their own configuration.

  ## Read-Before-Write

  For safety, existing files must be read in the current session before
  they can be overwritten. This ensures the agent has seen the current
  content and is making an informed decision to replace it.

  ```
  # This will fail if file.txt exists but hasn't been read:
  write_file("src/file.txt", "new content")
  # Error: "File must be read before overwriting: src/file.txt"

  # Correct flow:
  read_file("src/file.txt")  # First, read the file
  write_file("src/file.txt", "new content")  # Now write is allowed
  ```

  New files (that don't exist) can be written without prior reading.

  ## Examples

      # Create a new file
      %{"path" => "src/new_module.ex", "content" => "defmodule NewModule do\\nend"}

      # Overwrite existing file (after reading it)
      %{"path" => "README.md", "content" => "# Updated README\\n\\nNew content."}

      # Write to nested directory (creates parents)
      %{"path" => "lib/deep/nested/module.ex", "content" => "defmodule Deep.Nested.Module do\\nend"}
  """
  @spec write_file() :: Tool.t()
  def write_file do
    Tool.new!(%{
      name: "write_file",
      description:
        "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. " <>
          "Creates parent directories automatically. " <>
          "IMPORTANT: Existing files must be read first before overwriting to ensure you've seen the current content.",
      handler: JidoCode.Tools.Handlers.FileSystem.WriteFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to write (relative to project root)",
          required: true
        },
        %{
          name: "content",
          type: :string,
          description: "Content to write to the file",
          required: true
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
    [write_file()]
  end
end
