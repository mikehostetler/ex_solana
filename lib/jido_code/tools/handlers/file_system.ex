defmodule JidoCode.Tools.Handlers.FileSystem do
  @moduledoc """
  Handler modules for file system tools.

  This module contains sub-modules that implement the execute/2 callback
  for file system operations, delegating to the Security module for
  sandboxed execution with path validation.

  ## Handler Modules

  - `EditFile` - Edit file with string replacement
  - `ReadFile` - Read file contents
  - `WriteFile` - Write/overwrite file
  - `ListDirectory` - List directory contents
  - `FileInfo` - Get file metadata
  - `CreateDirectory` - Create directory
  - `DeleteFile` - Delete file (with confirmation)

  ## Usage

  These handlers are invoked by the Executor when the LLM calls file tools:

      # Via Executor
      Executor.execute(%{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "src/main.ex"}
      })

  ## Context

  The context map should contain:
  - `:project_root` - Base directory for operations

  If project_root is not in context, it's fetched from the Manager.
  """

  alias JidoCode.Tools.{HandlerHelpers, Manager}

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  def format_error(:enoent, path), do: "File not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"
  def format_error(:eisdir, path), do: "Is a directory: #{path}"
  def format_error(:enotdir, path), do: "Not a directory: #{path}"
  def format_error(:enospc, _path), do: "No space left on device"

  def format_error(:path_escapes_boundary, path),
    do: "Security error: path escapes project boundary: #{path}"

  def format_error(:path_outside_boundary, path),
    do: "Security error: path is outside project: #{path}"

  def format_error(:symlink_escapes_boundary, path),
    do: "Security error: symlink points outside project: #{path}"

  def format_error(reason, path) when is_atom(reason), do: "File error (#{reason}): #{path}"
  def format_error(reason, _path) when is_binary(reason), do: reason
  def format_error(reason, path), do: "Error (#{inspect(reason)}): #{path}"

  # ============================================================================
  # EditFile Handler
  # ============================================================================

  defmodule EditFile do
    @moduledoc """
    Handler for the edit_file tool.

    Performs exact string replacement within files. Unlike write_file which
    overwrites the entire file, edit_file allows targeted modifications.

    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Edits a file by replacing old_string with new_string.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"old_string"` - Exact string to find and replace
    - `"new_string"` - Replacement string
    - `"replace_all"` - If true, replace all occurrences; if false (default),
      require exactly one match

    ## Returns

    - `{:ok, message}` - Success message with replacement count
    - `{:error, reason}` - Error message

    ## Errors

    - Returns error if old_string is not found
    - Returns error if old_string appears multiple times and replace_all is false
    """
    def execute(%{"path" => path, "old_string" => old_string, "new_string" => new_string} = args, _context)
        when is_binary(path) and is_binary(old_string) and is_binary(new_string) do
      replace_all = Map.get(args, "replace_all", false)

      with {:ok, content} <- Manager.read_file(path),
           {:ok, new_content, count} <- do_replace(content, old_string, new_string, replace_all),
           :ok <- Manager.write_file(path, new_content) do
        {:ok, "Successfully replaced #{count} occurrence(s) in #{path}"}
      else
        {:error, :not_found} ->
          {:error, "String not found in file: #{path}"}

        {:error, :ambiguous_match, count} ->
          {:error, "Found #{count} occurrences of the string in #{path}. Use replace_all: true to replace all, or provide a more specific string."}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "edit_file requires path, old_string, and new_string arguments"}
    end

    defp do_replace(content, old_string, new_string, replace_all) do
      # Count occurrences
      count = count_occurrences(content, old_string)

      cond do
        count == 0 ->
          {:error, :not_found}

        count > 1 and not replace_all ->
          {:error, :ambiguous_match, count}

        true ->
          new_content = String.replace(content, old_string, new_string, global: replace_all)
          replaced_count = if replace_all, do: count, else: 1
          {:ok, new_content, replaced_count}
      end
    end

    defp count_occurrences(content, pattern) do
      # Use binary split to count occurrences without regex
      parts = String.split(content, pattern)
      length(parts) - 1
    end
  end

  # ============================================================================
  # ReadFile Handler
  # ============================================================================

  defmodule ReadFile do
    @moduledoc """
    Handler for the read_file tool.

    Reads the contents of a file within the project boundary.
    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Reads the contents of a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)

    ## Returns

    - `{:ok, content}` - File contents as string
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, _context) when is_binary(path) do
      case Manager.read_file(path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "read_file requires a path argument"}
    end
  end

  # ============================================================================
  # WriteFile Handler
  # ============================================================================

  defmodule WriteFile do
    @moduledoc """
    Handler for the write_file tool.

    Writes content to a file, creating parent directories if needed.
    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Writes content to a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"content"` - Content to write

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path, "content" => content}, _context)
        when is_binary(path) and is_binary(content) do
      # Create parent directories first
      dir_path = Path.dirname(path)

      with :ok <- (if dir_path != ".", do: Manager.mkdir_p(dir_path), else: :ok),
           :ok <- Manager.write_file(path, content) do
        {:ok, "File written successfully: #{path}"}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "write_file requires path and content arguments"}
    end
  end

  # ============================================================================
  # ListDirectory Handler
  # ============================================================================

  defmodule ListDirectory do
    @moduledoc """
    Handler for the list_directory tool.

    Lists the contents of a directory with optional recursive listing.
    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Lists directory contents.

    ## Arguments

    - `"path"` - Path to the directory (relative to project root)
    - `"recursive"` - Whether to list recursively (optional, default false)

    ## Returns

    - `{:ok, entries}` - JSON-encoded list of entries
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path} = args, _context) when is_binary(path) do
      recursive = Map.get(args, "recursive", false)
      list_entries(path, recursive)
    end

    def execute(_args, _context) do
      {:error, "list_directory requires a path argument"}
    end

    defp list_entries(path, false) do
      case Manager.list_dir(path) do
        {:ok, entries} when is_list(entries) ->
          result = entries |> Enum.sort() |> Enum.map(&entry_info(path, &1))
          {:ok, Jason.encode!(result)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    defp list_entries(path, true) do
      case list_recursive(path) do
        {:ok, entries} ->
          {:ok, Jason.encode!(entries)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    defp entry_info(parent_path, entry) do
      full_path = Path.join(parent_path, entry)

      type =
        case Manager.is_dir?(full_path) do
          {:ok, true} -> "directory"
          _ -> "file"
        end

      %{name: entry, type: type}
    end

    defp list_recursive(path) do
      case Manager.list_dir(path) do
        {:ok, entries} when is_list(entries) ->
          results = entries |> Enum.sort() |> Enum.flat_map(&expand_entry(path, &1))
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp expand_entry(parent_path, entry) do
      full_path = Path.join(parent_path, entry)

      case Manager.is_dir?(full_path) do
        {:ok, true} ->
          expand_directory(full_path)

        _ ->
          [%{name: full_path, type: "file"}]
      end
    end

    defp expand_directory(full_path) do
      case list_recursive(full_path) do
        {:ok, children} ->
          [%{name: full_path, type: "directory"} | children]

        {:error, _} ->
          [%{name: full_path, type: "directory", error: "unreadable"}]
      end
    end
  end

  # ============================================================================
  # FileInfo Handler
  # ============================================================================

  defmodule FileInfo do
    @moduledoc """
    Handler for the file_info tool.

    Gets metadata about a file or directory.
    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Gets file metadata.

    ## Arguments

    - `"path"` - Path to the file/directory (relative to project root)

    ## Returns

    - `{:ok, info}` - JSON-encoded metadata map
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, _context) when is_binary(path) do
      case Manager.file_stat(path) do
        {:ok, stat} ->
          info = %{
            path: path,
            size: stat.size,
            type: Atom.to_string(stat.type),
            access: Atom.to_string(stat.access),
            mtime: format_mtime(stat.mtime)
          }

          {:ok, Jason.encode!(info)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "file_info requires a path argument"}
    end

    defp format_mtime({{year, month, day}, {hour, minute, second}}) do
      :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [year, month, day, hour, minute, second])
      |> IO.iodata_to_binary()
    end

    defp format_mtime(_), do: ""
  end

  # ============================================================================
  # CreateDirectory Handler
  # ============================================================================

  defmodule CreateDirectory do
    @moduledoc """
    Handler for the create_directory tool.

    Creates a directory, including parent directories.
    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Creates a directory.

    ## Arguments

    - `"path"` - Path to the directory to create (relative to project root)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, _context) when is_binary(path) do
      case Manager.mkdir_p(path) do
        :ok -> {:ok, "Directory created successfully: #{path}"}
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "create_directory requires a path argument"}
    end
  end

  # ============================================================================
  # DeleteFile Handler
  # ============================================================================

  defmodule DeleteFile do
    @moduledoc """
    Handler for the delete_file tool.

    Deletes a file with confirmation requirement for safety.
    All file operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Manager

    @doc """
    Deletes a file.

    ## Arguments

    - `"path"` - Path to the file to delete (relative to project root)
    - `"confirm"` - Must be true to actually delete

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path, "confirm" => true}, _context) when is_binary(path) do
      case Manager.delete_file(path) do
        :ok -> {:ok, "File deleted successfully: #{path}"}
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(%{"path" => _path, "confirm" => false}, _context) do
      {:error, "Delete operation requires confirm=true"}
    end

    def execute(%{"path" => _path}, _context) do
      {:error, "delete_file requires confirm parameter set to true"}
    end

    def execute(_args, _context) do
      {:error, "delete_file requires path and confirm arguments"}
    end
  end
end
