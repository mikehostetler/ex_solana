defmodule JidoCode.Tools.Handlers.FileSystem do
  @moduledoc """
  Handler modules for file system tools.

  This module contains sub-modules that implement the execute/2 callback
  for file system operations with session-aware path validation.

  ## Handler Modules

  - `EditFile` - Edit file with string replacement
  - `ReadFile` - Read file contents
  - `WriteFile` - Write/overwrite file
  - `ListDirectory` - List directory contents
  - `FileInfo` - Get file metadata
  - `CreateDirectory` - Create directory
  - `DeleteFile` - Delete file (with confirmation)

  ## Session Context

  Handlers use `HandlerHelpers.validate_path/2` for session-aware path validation:

  1. `session_id` present → Uses `Session.Manager.validate_path/2`
  2. `project_root` present → Uses `Security.validate_path/3`
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Usage

  These handlers are invoked by the Executor when the LLM calls file tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "src/main.ex"}
      }, context: context)
  """

  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  defdelegate validate_path(path, context), to: HandlerHelpers

  @doc false
  def format_error(:enoent, path), do: "File not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"
  def format_error(:eisdir, path), do: "Is a directory: #{path}"
  def format_error(:enotdir, path), do: "Not a directory: #{path}"
  def format_error(:enospc, _path), do: "No space left on device"

  def format_error(:content_too_large, _path),
    do: "Content exceeds maximum file size (10MB)"

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

    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Edits a file by replacing old_string with new_string.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"old_string"` - Exact string to find and replace
    - `"new_string"` - Replacement string
    - `"replace_all"` - If true, replace all occurrences; if false (default),
      require exactly one match

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, message}` - Success message with replacement count
    - `{:error, reason}` - Error message

    ## Errors

    - Returns error if old_string is not found
    - Returns error if old_string appears multiple times and replace_all is false
    """
    def execute(
          %{"path" => path, "old_string" => old_string, "new_string" => new_string} = args,
          context
        )
        when is_binary(path) and is_binary(old_string) and is_binary(new_string) do
      replace_all = Map.get(args, "replace_all", false)

      with {:ok, safe_path} <- FileSystem.validate_path(path, context),
           {:ok, content} <- File.read(safe_path),
           {:ok, new_content, count} <- do_replace(content, old_string, new_string, replace_all),
           :ok <- File.write(safe_path, new_content) do
        {:ok, "Successfully replaced #{count} occurrence(s) in #{path}"}
      else
        {:error, :not_found} ->
          {:error, "String not found in file: #{path}"}

        {:error, :ambiguous_match, count} ->
          {:error,
           "Found #{count} occurrences of the string in #{path}. Use replace_all: true to replace all, or provide a more specific string."}

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
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Reads the contents of a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, content}` - File contents as string
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.read(safe_path) do
            {:ok, content} -> {:ok, content}
            {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
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
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.HandlerHelpers
    alias JidoCode.Tools.Handlers.FileSystem

    # Maximum file size: 10MB
    @max_file_size 10 * 1024 * 1024

    @doc """
    Writes content to a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"content"` - Content to write (max 10MB)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message

    ## Security

    - Content size limited to 10MB
    - Parent directories validated to prevent symlink escape
    """
    def execute(%{"path" => path, "content" => content}, context)
        when is_binary(path) and is_binary(content) do
      with :ok <- validate_content_size(content),
           {:ok, safe_path} <- FileSystem.validate_path(path, context),
           dir_path <- Path.dirname(safe_path),
           :ok <- validate_parent_directory(dir_path, context),
           :ok <- maybe_create_directory(dir_path),
           :ok <- File.write(safe_path, content) do
        {:ok, "File written successfully: #{path}"}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "write_file requires path and content arguments"}
    end

    # Private functions for WriteFile

    defp validate_content_size(content) when byte_size(content) > @max_file_size do
      {:error, :content_too_large}
    end

    defp validate_content_size(_content), do: :ok

    defp maybe_create_directory("."), do: :ok
    defp maybe_create_directory(dir_path), do: File.mkdir_p(dir_path)

    # Validate parent directory to prevent TOCTOU attacks with symlinks
    defp validate_parent_directory(".", _context), do: :ok

    defp validate_parent_directory(dir_path, context) do
      case File.lstat(dir_path) do
        {:ok, %{type: :symlink}} ->
          # Symlink exists - validate where it points
          validate_symlink_target(dir_path, context)

        {:ok, _stat} ->
          # Regular directory exists, OK
          :ok

        {:error, :enoent} ->
          # Directory doesn't exist yet - check parent recursively
          parent = Path.dirname(dir_path)

          if parent == dir_path do
            # Reached root
            :ok
          else
            validate_parent_directory(parent, context)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp validate_symlink_target(symlink_path, context) do
      case File.read_link(symlink_path) do
        {:ok, target} ->
          # Resolve symlink relative to its location
          resolved = Path.expand(target, Path.dirname(symlink_path))

          case HandlerHelpers.get_project_root(context) do
            {:ok, root} ->
              normalized_root = Path.expand(root)

              if String.starts_with?(resolved, normalized_root <> "/") or
                   resolved == normalized_root do
                :ok
              else
                {:error, :symlink_escapes_boundary}
              end

            {:error, _} = error ->
              error
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ============================================================================
  # ListDirectory Handler
  # ============================================================================

  defmodule ListDirectory do
    @moduledoc """
    Handler for the list_directory tool.

    Lists the contents of a directory with optional recursive listing.
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Lists directory contents.

    ## Arguments

    - `"path"` - Path to the directory (relative to project root)
    - `"recursive"` - Whether to list recursively (optional, default false)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, entries}` - JSON-encoded list of entries
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path} = args, context) when is_binary(path) do
      recursive = Map.get(args, "recursive", false)

      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          list_entries(path, safe_path, recursive)

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "list_directory requires a path argument"}
    end

    defp list_entries(original_path, safe_path, false) do
      case File.ls(safe_path) do
        {:ok, entries} when is_list(entries) ->
          result = entries |> Enum.sort() |> Enum.map(&entry_info(safe_path, &1))
          {:ok, Jason.encode!(result)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, original_path)}
      end
    end

    defp list_entries(original_path, safe_path, true) do
      case list_recursive(safe_path, safe_path) do
        {:ok, entries} ->
          {:ok, Jason.encode!(entries)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, original_path)}
      end
    end

    defp entry_info(parent_path, entry) do
      full_path = Path.join(parent_path, entry)
      type = if File.dir?(full_path), do: "directory", else: "file"
      %{name: entry, type: type}
    end

    # Recursive listing - base_path is the root for relative name calculation
    defp list_recursive(path, base_path) do
      case File.ls(path) do
        {:ok, entries} when is_list(entries) ->
          results = entries |> Enum.sort() |> Enum.flat_map(&expand_entry(path, &1, base_path))
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp expand_entry(parent_path, entry, base_path) do
      full_path = Path.join(parent_path, entry)
      # Calculate relative path from base
      relative_name = Path.relative_to(full_path, base_path)

      if File.dir?(full_path) do
        expand_directory(full_path, relative_name, base_path)
      else
        [%{name: relative_name, type: "file"}]
      end
    end

    defp expand_directory(full_path, relative_name, base_path) do
      case list_recursive(full_path, base_path) do
        {:ok, children} ->
          [%{name: relative_name, type: "directory"} | children]

        {:error, _} ->
          [%{name: relative_name, type: "directory", error: "unreadable"}]
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
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Gets file metadata.

    ## Arguments

    - `"path"` - Path to the file/directory (relative to project root)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, info}` - JSON-encoded metadata map
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.stat(safe_path) do
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

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "file_info requires a path argument"}
    end

    defp format_mtime({{year, month, day}, {hour, minute, second}}) do
      :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [
        year,
        month,
        day,
        hour,
        minute,
        second
      ])
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
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Creates a directory.

    ## Arguments

    - `"path"` - Path to the directory to create (relative to project root)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.mkdir_p(safe_path) do
            :ok -> {:ok, "Directory created successfully: #{path}"}
            {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
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
    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.FileSystem

    @doc """
    Deletes a file.

    ## Arguments

    - `"path"` - Path to the file to delete (relative to project root)
    - `"confirm"` - Must be true to actually delete

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path, "confirm" => true}, context) when is_binary(path) do
      case FileSystem.validate_path(path, context) do
        {:ok, safe_path} ->
          case File.rm(safe_path) do
            :ok -> {:ok, "File deleted successfully: #{path}"}
            {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
          end

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
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
