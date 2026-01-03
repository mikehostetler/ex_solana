defmodule JidoCode.Tools.Helpers.GlobMatcher do
  @moduledoc """
  Shared glob pattern matching utilities for file listing and search tools.

  This module provides glob pattern matching functionality used by both
  handlers and bridge functions, eliminating code duplication and ensuring
  consistent behavior.

  ## Pattern Matching Functions

  For ignore pattern filtering (used by ListDir):
  - `matches_any?/2` - Check if entry matches any pattern in a list
  - `matches_glob?/2` - Check if entry matches a single glob pattern
  - `sort_directories_first/2` - Sort with directories first
  - `entry_info/2` - Get entry metadata

  ## Glob Search Functions

  For glob search result processing (used by GlobSearch):
  - `filter_within_boundary/2` - Filter paths to project boundary (with symlink validation)
  - `sort_by_mtime_desc/1` - Sort by modification time (newest first)
  - `make_relative/2` - Convert absolute paths to relative

  ## Supported Glob Patterns (for matches_glob?)

  - `*` - Match any sequence of characters (except path separator)
  - `?` - Match any single character
  - Literal characters are matched exactly

  Note: `**`, `[abc]`, and `{a,b}` patterns are handled by `Path.wildcard/2`
  in the GlobSearch tool, not by this module's pattern matching functions.

  ## Security

  - All regex metacharacters are properly escaped to prevent regex injection
  - Symlinks are followed and validated in `filter_within_boundary/2`
  - Invalid patterns are logged and treated as non-matching

  ## See Also

  - `JidoCode.Tools.Handlers.FileSystem.ListDir` - ListDir handler
  - `JidoCode.Tools.Handlers.FileSystem.GlobSearch` - GlobSearch handler
  - `JidoCode.Tools.Bridge` - Bridge functions for Lua sandbox
  """

  require Logger

  @doc """
  Checks if an entry matches any of the provided ignore patterns.

  Returns `true` if the entry matches at least one pattern, `false` otherwise.
  An empty pattern list always returns `false`.

  ## Examples

      iex> GlobMatcher.matches_any?("test.log", ["*.log", "*.tmp"])
      true

      iex> GlobMatcher.matches_any?("readme.md", ["*.log"])
      false

      iex> GlobMatcher.matches_any?("file.txt", [])
      false

  """
  @spec matches_any?(String.t(), list(String.t())) :: boolean()
  def matches_any?(_entry, []), do: false

  def matches_any?(entry, patterns) when is_binary(entry) and is_list(patterns) do
    Enum.any?(patterns, &matches_glob?(entry, &1))
  end

  def matches_any?(_entry, _patterns), do: false

  @doc """
  Checks if an entry matches a single glob pattern.

  Converts the glob pattern to a regex and tests for a match.
  Invalid patterns log a warning and return `false`.

  ## Examples

      iex> GlobMatcher.matches_glob?("test.log", "*.log")
      true

      iex> GlobMatcher.matches_glob?("config.json", "config.???")
      false

      iex> GlobMatcher.matches_glob?("config.json", "config.????")
      true

  """
  @spec matches_glob?(String.t(), String.t()) :: boolean()
  def matches_glob?(entry, pattern) when is_binary(entry) and is_binary(pattern) do
    regex_pattern = glob_to_regex(pattern)

    case Regex.compile("^#{regex_pattern}$") do
      {:ok, regex} ->
        Regex.match?(regex, entry)

      {:error, reason} ->
        Logger.warning("Invalid glob pattern #{inspect(pattern)}: #{inspect(reason)}")
        false
    end
  end

  def matches_glob?(_entry, _pattern), do: false

  @doc """
  Sorts entries with directories first, then alphabetically within each group.

  ## Examples

      iex> GlobMatcher.sort_directories_first(["file.txt", "dir", "another.md"], "/path")
      ["dir", "another.md", "file.txt"]  # assuming "dir" is a directory

  """
  @spec sort_directories_first(list(String.t()), String.t()) :: list(String.t())
  def sort_directories_first(entries, parent_path) when is_list(entries) and is_binary(parent_path) do
    Enum.sort_by(entries, fn entry ->
      full_path = Path.join(parent_path, entry)
      is_dir = File.dir?(full_path)
      # Directories first (false < true when negated), then alphabetically
      {not is_dir, entry}
    end)
  end

  @doc """
  Returns information about a directory entry.

  ## Examples

      iex> GlobMatcher.entry_info("/path/to/dir", "subdir")
      %{name: "subdir", type: "directory"}

      iex> GlobMatcher.entry_info("/path/to/dir", "file.txt")
      %{name: "file.txt", type: "file"}

  """
  @spec entry_info(String.t(), String.t()) :: %{name: String.t(), type: String.t()}
  def entry_info(parent_path, entry) when is_binary(parent_path) and is_binary(entry) do
    full_path = Path.join(parent_path, entry)
    type = if File.dir?(full_path), do: "directory", else: "file"
    %{name: entry, type: type}
  end

  # Private: Convert glob pattern to regex pattern with proper escaping
  @spec glob_to_regex(String.t()) :: String.t()
  defp glob_to_regex(pattern) do
    pattern
    # Escape all regex metacharacters except * and ?
    |> escape_regex_metacharacters()
    # Convert glob wildcards to regex equivalents
    |> String.replace("\\*", ".*")
    |> String.replace("\\?", ".")
  end

  # Escape all regex metacharacters using Regex.escape, then restore * and ?
  @spec escape_regex_metacharacters(String.t()) :: String.t()
  defp escape_regex_metacharacters(pattern) do
    # Use Regex.escape to escape all metacharacters properly
    escaped = Regex.escape(pattern)
    # Regex.escape converts * to \* and ? to \?, which we want for now
    # We'll convert them back to regex wildcards in glob_to_regex
    escaped
  end

  # ===========================================================================
  # Glob Search Helpers
  # ===========================================================================

  @doc """
  Filters paths to only those within the project boundary.

  This function validates that each path is within the allowed project root,
  including following symlinks to ensure they don't escape the boundary.

  ## Parameters

  - `paths` - List of absolute file paths to filter
  - `project_root` - The project root directory (will be expanded)

  ## Returns

  A filtered list containing only paths within the boundary.

  ## Examples

      iex> GlobMatcher.filter_within_boundary(["/project/file.ex", "/etc/passwd"], "/project")
      ["/project/file.ex"]

  """
  @spec filter_within_boundary(list(String.t()), String.t()) :: list(String.t())
  def filter_within_boundary(paths, project_root) when is_list(paths) and is_binary(project_root) do
    expanded_root = Path.expand(project_root)

    Enum.filter(paths, fn path ->
      path_within_boundary?(path, expanded_root)
    end)
  end

  @doc """
  Sorts paths by modification time, newest first.

  Files that cannot be stat'd (e.g., permission denied) are sorted to the end.

  ## Parameters

  - `paths` - List of file paths to sort

  ## Returns

  Paths sorted by modification time (newest first).

  ## Examples

      iex> GlobMatcher.sort_by_mtime_desc(["/old/file.ex", "/new/file.ex"])
      ["/new/file.ex", "/old/file.ex"]  # assuming new was modified more recently

  """
  @spec sort_by_mtime_desc(list(String.t())) :: list(String.t())
  def sort_by_mtime_desc(paths) when is_list(paths) do
    Enum.sort_by(
      paths,
      fn path ->
        case File.stat(path, time: :posix) do
          {:ok, %{mtime: mtime}} -> -mtime
          _ -> 0
        end
      end
    )
  end

  @doc """
  Converts absolute paths to relative paths from project root.

  ## Parameters

  - `paths` - List of absolute file paths
  - `project_root` - The project root directory (will be expanded)

  ## Returns

  List of paths relative to the project root.

  ## Examples

      iex> GlobMatcher.make_relative(["/project/lib/file.ex"], "/project")
      ["lib/file.ex"]

  """
  @spec make_relative(list(String.t()), String.t()) :: list(String.t())
  def make_relative(paths, project_root) when is_list(paths) and is_binary(project_root) do
    expanded_root = Path.expand(project_root)

    Enum.map(paths, fn path ->
      expanded_path = Path.expand(path)
      Path.relative_to(expanded_path, expanded_root)
    end)
  end

  # Private: Check if a single path is within the boundary, including symlink resolution
  @spec path_within_boundary?(String.t(), String.t()) :: boolean()
  defp path_within_boundary?(path, expanded_root) do
    expanded_path = Path.expand(path)

    # First check: is the path itself within the boundary?
    if String.starts_with?(expanded_path, expanded_root <> "/") or expanded_path == expanded_root do
      # Second check: if it's a symlink, does its target stay within boundary?
      case File.read_link(path) do
        {:ok, _target} ->
          # It's a symlink - get the real path and check
          real_path = resolve_real_path(path)
          String.starts_with?(real_path, expanded_root <> "/") or real_path == expanded_root

        {:error, :einval} ->
          # Not a symlink, path check passed
          true

        {:error, _} ->
          # Other error (file doesn't exist, etc.), exclude
          false
      end
    else
      false
    end
  end

  # Resolve the real path by following all symlinks
  @spec resolve_real_path(String.t()) :: String.t()
  defp resolve_real_path(path) do
    case File.read_link(path) do
      {:ok, target} ->
        # Target might be relative to the symlink's directory
        resolved =
          if Path.type(target) == :relative do
            path |> Path.dirname() |> Path.join(target) |> Path.expand()
          else
            Path.expand(target)
          end

        # Recursively follow if target is also a symlink
        resolve_real_path(resolved)

      {:error, :einval} ->
        # Not a symlink, return expanded path
        Path.expand(path)

      {:error, _} ->
        # Other error, return expanded path
        Path.expand(path)
    end
  end
end
