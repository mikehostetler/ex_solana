defmodule JidoCode.Tools.Handlers.Search do
  @moduledoc """
  Handler modules for search tools.

  This module contains handlers for searching the codebase:
  - `Grep` - Search file contents for patterns
  - `FindFiles` - Find files by name/glob pattern

  ## Session Context

  Handlers use `HandlerHelpers.validate_path/2` for session-aware path validation:

  1. `session_id` present → Uses `Session.Manager.validate_path/2`
  2. `project_root` present → Uses `Security.validate_path/3`
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Usage

  These handlers are invoked by the Executor when the LLM calls search tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "grep",
        arguments: %{"pattern" => "def hello", "path" => "lib"}
      }, context: context)

  ## Context

  The context map should contain:
  - `:session_id` - Session ID for path validation (preferred)
  - `:project_root` - Base directory for operations (legacy)
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
  def format_error(:enoent, path), do: "Path not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"
  def format_error(:enotdir, path), do: "Not a directory: #{path}"

  def format_error(:path_escapes_boundary, path),
    do: "Security error: path escapes project boundary: #{path}"

  def format_error(:path_outside_boundary, path),
    do: "Security error: path is outside project: #{path}"

  def format_error(:symlink_escapes_boundary, path),
    do: "Security error: symlink points outside project: #{path}"

  def format_error({:invalid_regex, reason}, _path), do: "Invalid regex pattern: #{reason}"
  def format_error(reason, path) when is_atom(reason), do: "Error (#{reason}): #{path}"
  def format_error(reason, _path) when is_binary(reason), do: reason
  def format_error(reason, path), do: "Error (#{inspect(reason)}): #{path}"

  # ============================================================================
  # Grep Handler
  # ============================================================================

  defmodule Grep do
    @moduledoc """
    Handler for the grep tool.

    Searches file contents for patterns and returns matched lines
    with file paths and line numbers.

    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    """

    alias JidoCode.Tools.Handlers.Search

    @default_max_results 100

    @doc """
    Searches for pattern in files.

    ## Arguments

    - `"pattern"` - Regex or literal pattern to search for
    - `"path"` - Directory or file to search in
    - `"recursive"` - Whether to search subdirectories (default: true)
    - `"max_results"` - Maximum matches to return (default: 100)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, json}` - JSON array of matches with file, line, content
    - `{:error, reason}` - Error message
    """
    def execute(%{"pattern" => pattern, "path" => path} = args, context)
        when is_binary(pattern) and is_binary(path) do
      recursive = Map.get(args, "recursive", true)
      max_results = Map.get(args, "max_results", @default_max_results)

      with {:ok, regex} <- compile_pattern(pattern),
           {:ok, safe_path} <- Search.validate_path(path, context),
           {:ok, project_root} <- Search.get_project_root(context) do
        results = search_files(safe_path, project_root, regex, recursive, max_results)
        {:ok, Jason.encode!(results)}
      else
        {:error, reason} -> {:error, Search.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "grep requires pattern and path arguments"}
    end

    defp compile_pattern(pattern) do
      case Regex.compile(pattern) do
        {:ok, regex} -> {:ok, regex}
        {:error, {reason, _pos}} -> {:error, {:invalid_regex, reason}}
      end
    end

    defp search_files(safe_path, project_root, regex, recursive, max_results) do
      files = collect_files(safe_path, recursive)

      files
      |> Stream.flat_map(&search_file(&1, project_root, regex))
      |> Enum.take(max_results)
    end

    defp collect_files(path, recursive) do
      cond do
        File.regular?(path) ->
          [path]

        File.dir?(path) && recursive ->
          list_files_recursive(path)

        File.dir?(path) ->
          list_files_shallow(path)

        true ->
          []
      end
    end

    defp list_files_recursive(dir) do
      case File.ls(dir) do
        {:ok, entries} when is_list(entries) ->
          Enum.flat_map(entries, &expand_entry(dir, &1))

        _ ->
          []
      end
    end

    defp expand_entry(dir, entry) do
      full_path = Path.join(dir, entry)

      cond do
        File.regular?(full_path) -> [full_path]
        File.dir?(full_path) -> list_files_recursive(full_path)
        true -> []
      end
    end

    defp list_files_shallow(dir) do
      case File.ls(dir) do
        {:ok, entries} when is_list(entries) ->
          entries
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&File.regular?/1)

        _ ->
          []
      end
    end

    defp search_file(file_path, project_root, regex) do
      case File.read(file_path) do
        {:ok, content} ->
          # Return relative path from project root
          relative_path = Path.relative_to(file_path, project_root)

          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _num} -> Regex.match?(regex, line) end)
          |> Enum.map(fn {line, num} ->
            %{
              file: relative_path,
              line: num,
              content: String.trim_trailing(line, "\n")
            }
          end)

        {:error, _} ->
          []
      end
    end
  end

  # ============================================================================
  # FindFiles Handler
  # ============================================================================

  defmodule FindFiles do
    @moduledoc """
    Handler for the find_files tool.

    Finds files by name or glob pattern.

    Uses session-aware path validation via `HandlerHelpers.validate_path/2`.
    Uses `Path.wildcard/2` on validated paths within the project boundary.
    """

    alias JidoCode.Tools.Handlers.Search

    @default_max_results 100

    @doc """
    Finds files matching a pattern.

    ## Arguments

    - `"pattern"` - Glob pattern or filename to find
    - `"path"` - Directory to search in (default: project root)
    - `"max_results"` - Maximum files to return (default: 100)

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, json}` - JSON array of matching file paths
    - `{:error, reason}` - Error message
    """
    def execute(%{"pattern" => pattern} = args, context) when is_binary(pattern) do
      path = Map.get(args, "path", "")
      max_results = Map.get(args, "max_results", @default_max_results)

      with {:ok, safe_path} <- Search.validate_path(path, context),
           {:ok, project_root} <- Search.get_project_root(context) do
        results = find_matching_files(safe_path, project_root, pattern, max_results)
        {:ok, Jason.encode!(results)}
      else
        {:error, reason} ->
          {:error, Search.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "find_files requires a pattern argument"}
    end

    defp find_matching_files(base_path, project_root, pattern, max_results) do
      glob_pattern = build_glob_pattern(base_path, pattern)

      glob_pattern
      |> Path.wildcard(match_dot: false)
      |> Stream.filter(&File.regular?/1)
      |> Stream.map(&Path.relative_to(&1, project_root))
      |> Enum.take(max_results)
    end

    defp build_glob_pattern(base_path, pattern) do
      cond do
        # Pattern already has directory component
        String.contains?(pattern, "/") ->
          Path.join(base_path, pattern)

        # Pattern has glob characters - search recursively
        has_glob_chars?(pattern) ->
          Path.join([base_path, "**", pattern])

        # Plain filename - search recursively
        true ->
          Path.join([base_path, "**", pattern])
      end
    end

    defp has_glob_chars?(pattern) do
      String.contains?(pattern, ["*", "?", "[", "{"])
    end
  end
end
