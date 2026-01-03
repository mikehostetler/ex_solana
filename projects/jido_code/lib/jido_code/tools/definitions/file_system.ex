defmodule JidoCode.Tools.Definitions.FileSystem do
  @moduledoc """
  Tool definitions for file system operations.

  This module defines the tools for file system operations that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `read_file` - Read file contents with line numbers, offset, and limit support
  - `write_file` - Write/overwrite file
  - `edit_file` - Edit file with string replacement
  - `multi_edit_file` - Apply multiple edits atomically (all succeed or all fail)
  - `list_dir` - List directory contents with filtering support
  - `list_directory` - List directory contents with recursive option
  - `glob_search` - Find files matching glob patterns
  - `file_info` - Get file metadata
  - `create_directory` - Create directory
  - `delete_file` - Delete file (with confirmation)

  ## Usage

      # Register all file system tools
      for tool <- FileSystem.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      read_file_tool = FileSystem.read_file()
      :ok = Registry.register(read_file_tool)
  """

  alias JidoCode.Tools.Definitions.FileMultiEdit
  alias JidoCode.Tools.Definitions.FileRead
  alias JidoCode.Tools.Definitions.FileWrite
  alias JidoCode.Tools.Definitions.GlobSearch
  alias JidoCode.Tools.Definitions.ListDir
  alias JidoCode.Tools.Handlers.FileSystem, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all file system tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      read_file(),
      write_file(),
      edit_file(),
      multi_edit_file(),
      list_dir(),
      list_directory(),
      glob_search(),
      file_info(),
      create_directory(),
      delete_file()
    ]
  end

  @doc """
  Returns the read_file tool definition.

  Reads file contents with line numbers, supporting offset and limit parameters
  for handling large files. Delegates to `JidoCode.Tools.Definitions.FileRead`.

  ## Parameters

  - `path` (required, string) - Path to the file relative to project root
  - `offset` (optional, integer) - Line number to start from (1-indexed, default: 1)
  - `limit` (optional, integer) - Maximum lines to read (default: 2000)

  ## See Also

  - `JidoCode.Tools.Definitions.FileRead` - Full documentation
  """
  @spec read_file() :: Tool.t()
  defdelegate read_file(), to: FileRead

  @doc """
  Returns the write_file tool definition.

  Writes content to a file, creating parent directories if needed.
  Delegates to `JidoCode.Tools.Definitions.FileWrite`.

  ## Parameters

  - `path` (required, string) - Path to the file relative to project root
  - `content` (required, string) - Content to write to the file

  ## Read-Before-Write Requirement

  Existing files must be read before they can be overwritten to ensure
  the agent has seen the current content. New files can be created without
  prior reading.

  ## See Also

  - `JidoCode.Tools.Definitions.FileWrite` - Full documentation
  """
  @spec write_file() :: Tool.t()
  defdelegate write_file(), to: FileWrite

  @doc """
  Returns the edit_file tool definition.

  Performs exact string replacement within files. Unlike write_file which
  overwrites the entire file, edit_file allows targeted modifications.

  ## Parameters

  - `path` (required, string) - Path to the file relative to project root
  - `old_string` (required, string) - Exact string to find and replace
  - `new_string` (required, string) - Replacement string
  - `replace_all` (optional, boolean) - Replace all occurrences (default: false)
  """
  @spec edit_file() :: Tool.t()
  def edit_file do
    Tool.new!(%{
      name: "edit_file",
      description:
        "Edit a file by replacing an exact string with a new string. " <>
          "By default requires the old_string to appear exactly once (for safety). " <>
          "Use replace_all=true to replace all occurrences.",
      handler: Handlers.EditFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to edit (relative to project root)",
          required: true
        },
        %{
          name: "old_string",
          type: :string,
          description: "Exact string to find and replace",
          required: true
        },
        %{
          name: "new_string",
          type: :string,
          description: "Replacement string",
          required: true
        },
        %{
          name: "replace_all",
          type: :boolean,
          description:
            "Replace all occurrences instead of requiring exactly one match (default: false)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the multi_edit_file tool definition.

  Performs multiple search/replace operations within a single file atomically.
  All edits succeed or all fail - the file remains unchanged if any edit fails.
  Delegates to `JidoCode.Tools.Definitions.FileMultiEdit`.

  ## Parameters

  - `path` (required, string) - Path to the file relative to project root
  - `edits` (required, array) - Array of edit objects with old_string and new_string

  ## Atomic Behavior

  All edits are validated before any modifications occur. If any edit fails
  validation (string not found, ambiguous match), no changes are made.

  ## See Also

  - `JidoCode.Tools.Definitions.FileMultiEdit` - Full documentation
  """
  @spec multi_edit_file() :: Tool.t()
  defdelegate multi_edit_file(), to: FileMultiEdit

  @doc """
  Returns the list_dir tool definition.

  Lists the contents of a directory with optional filtering via glob patterns.
  Delegates to `JidoCode.Tools.Definitions.ListDir`.

  ## Parameters

  - `path` (required, string) - Path to the directory relative to project root
  - `ignore_patterns` (optional, array) - Glob patterns to exclude from listing

  ## Features

  - Sorted output (directories first, then alphabetically)
  - Glob pattern filtering for excluding unwanted entries
  - Type indicators for each entry (file or directory)

  ## See Also

  - `JidoCode.Tools.Definitions.ListDir` - Full documentation
  """
  @spec list_dir() :: Tool.t()
  defdelegate list_dir(), to: ListDir

  @doc """
  Returns the list_directory tool definition.

  Lists the contents of a directory with optional recursive listing.

  ## Parameters

  - `path` (required, string) - Path to the directory relative to project root
  - `recursive` (optional, boolean) - Whether to list recursively (default: false)
  """
  @spec list_directory() :: Tool.t()
  def list_directory do
    Tool.new!(%{
      name: "list_directory",
      description:
        "List the contents of a directory. Returns a JSON array of entries with name and type (file or directory).",
      handler: Handlers.ListDirectory,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the directory to list (relative to project root)",
          required: true
        },
        %{
          name: "recursive",
          type: :boolean,
          description: "Whether to list contents recursively (default: false)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the glob_search tool definition.

  Finds files matching a glob pattern within the project boundary.
  Delegates to `JidoCode.Tools.Definitions.GlobSearch`.

  ## Parameters

  - `pattern` (required, string) - Glob pattern to match files against
  - `path` (optional, string) - Base directory to search from

  ## Features

  - Full glob pattern support (**, *, ?, {a,b}, [abc])
  - Results sorted by modification time (newest first)
  - Security boundary enforcement

  ## See Also

  - `JidoCode.Tools.Definitions.GlobSearch` - Full documentation
  """
  @spec glob_search() :: Tool.t()
  defdelegate glob_search(), to: GlobSearch

  @doc """
  Returns the file_info tool definition.

  Gets metadata about a file or directory.

  ## Parameters

  - `path` (required, string) - Path to the file/directory relative to project root
  """
  @spec file_info() :: Tool.t()
  def file_info do
    Tool.new!(%{
      name: "file_info",
      description:
        "Get metadata about a file or directory. Returns JSON with size, type, access mode, and timestamps.",
      handler: Handlers.FileInfo,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file or directory (relative to project root)",
          required: true
        }
      ]
    })
  end

  @doc """
  Returns the create_directory tool definition.

  Creates a directory, including parent directories.

  ## Parameters

  - `path` (required, string) - Path to the directory to create relative to project root
  """
  @spec create_directory() :: Tool.t()
  def create_directory do
    Tool.new!(%{
      name: "create_directory",
      description:
        "Create a directory. Creates parent directories automatically if they don't exist.",
      handler: Handlers.CreateDirectory,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the directory to create (relative to project root)",
          required: true
        }
      ]
    })
  end

  @doc """
  Returns the delete_file tool definition.

  Deletes a file with confirmation requirement for safety.

  ## Parameters

  - `path` (required, string) - Path to the file to delete relative to project root
  - `confirm` (required, boolean) - Must be true to confirm deletion
  """
  @spec delete_file() :: Tool.t()
  def delete_file do
    Tool.new!(%{
      name: "delete_file",
      description:
        "Delete a file. Requires explicit confirmation (confirm=true) to prevent accidental deletions.",
      handler: Handlers.DeleteFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to delete (relative to project root)",
          required: true
        },
        %{
          name: "confirm",
          type: :boolean,
          description: "Must be set to true to confirm the deletion",
          required: true
        }
      ]
    })
  end
end
