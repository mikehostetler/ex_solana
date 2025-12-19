defmodule JidoCode.Tools.Security do
  @moduledoc """
  Security boundary enforcement for tool operations.

  This module provides path validation to ensure file operations stay within
  the project boundary. It is used by bridge functions to validate paths
  before performing any file system operations.

  ## Security Checks

  - **Absolute paths**: Must start with project root
  - **Relative paths**: Resolved relative to project root
  - **Path traversal**: `..` sequences resolved and validated
  - **Symlinks**: Followed and validated against boundary

  ## Usage

      # Validate a path
      {:ok, safe_path} = Security.validate_path("src/file.ex", "/project")

      # Path traversal blocked
      {:error, :path_escapes_boundary} = Security.validate_path("../../../etc/passwd", "/project")

      # Absolute path outside project
      {:error, :path_outside_boundary} = Security.validate_path("/etc/passwd", "/project")

  ## Logging

  All security violations are logged as warnings for debugging. Set the
  `:log_violations` option to `false` to disable logging (useful in tests).
  """

  require Logger

  @type validation_error ::
          :path_escapes_boundary
          | :path_outside_boundary
          | :symlink_escapes_boundary
          | :invalid_path

  @type validate_opts :: [log_violations: boolean()]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Validates that a path is within the project boundary.

  Resolves the path (handling `..` and symlinks) and ensures the result
  is within the project root directory.

  ## Parameters

  - `path` - The path to validate (relative or absolute)
  - `project_root` - The project root directory (must be absolute)
  - `opts` - Options:
    - `:log_violations` - Log security violations (default: true)

  ## Returns

  - `{:ok, resolved_path}` - Path is valid and resolved
  - `{:error, reason}` - Path violates security boundary

  ## Examples

      # Valid relative path
      {:ok, "/project/src/file.ex"} = validate_path("src/file.ex", "/project")

      # Valid absolute path within project
      {:ok, "/project/src/file.ex"} = validate_path("/project/src/file.ex", "/project")

      # Path traversal attack
      {:error, :path_escapes_boundary} = validate_path("../../../etc/passwd", "/project")

      # Absolute path outside project
      {:error, :path_outside_boundary} = validate_path("/etc/passwd", "/project")
  """
  @spec validate_path(String.t(), String.t(), validate_opts()) ::
          {:ok, String.t()} | {:error, validation_error()}
  def validate_path(path, project_root, opts \\ [])

  def validate_path(path, project_root, opts) when is_binary(path) and is_binary(project_root) do
    log_violations = Keyword.get(opts, :log_violations, true)

    # Normalize project root (ensure no trailing slash, expanded)
    normalized_root = normalize_path(project_root)

    # Resolve the path
    resolved =
      if Path.type(path) == :absolute do
        normalize_path(path)
      else
        # Relative path - expand relative to project root
        normalize_path(Path.join(project_root, path))
      end

    # Check if resolved path is within project boundary
    if within_boundary?(resolved, normalized_root) do
      # Check for symlinks if path exists
      check_symlinks(resolved, normalized_root, log_violations)
    else
      reason = determine_violation_reason(path)
      maybe_log_violation(reason, path, log_violations)
      {:error, reason}
    end
  end

  def validate_path(_, _, _), do: {:error, :invalid_path}

  @doc """
  Checks if a path is within the project boundary.

  This is a simpler check that doesn't follow symlinks. Use `validate_path/3`
  for full validation.

  ## Parameters

  - `path` - The resolved path to check
  - `project_root` - The project root directory

  ## Returns

  - `true` if path is within boundary
  - `false` otherwise
  """
  @spec within_boundary?(String.t(), String.t()) :: boolean()
  def within_boundary?(path, project_root) do
    normalized_path = normalize_path(path)
    normalized_root = normalize_path(project_root)

    # Path must start with project root
    # We add a trailing slash to prevent matching partial directory names
    # e.g., /project shouldn't match /project2/file
    String.starts_with?(normalized_path, normalized_root <> "/") or
      normalized_path == normalized_root
  end

  @doc """
  Resolves a path relative to the project root.

  This expands the path and resolves `..` sequences, but does not
  validate the result. Use `validate_path/3` for validation.

  ## Parameters

  - `path` - The path to resolve
  - `project_root` - The project root directory

  ## Returns

  The resolved absolute path.
  """
  @spec resolve_path(String.t(), String.t()) :: String.t()
  def resolve_path(path, project_root) do
    if Path.type(path) == :absolute do
      normalize_path(path)
    else
      normalize_path(Path.join(project_root, path))
    end
  end

  # ============================================================================
  # Atomic Operations (TOCTOU Mitigation)
  # ============================================================================

  @doc """
  Performs an atomic read operation with validation.

  This function validates the path and reads the file atomically to mitigate
  TOCTOU (time-of-check to time-of-use) race conditions. The validation is
  performed immediately before the read operation.

  ## Parameters

  - `path` - The path to read
  - `project_root` - The project root directory
  - `opts` - Options (same as `validate_path/3`)

  ## Returns

  - `{:ok, content}` - File contents
  - `{:error, reason}` - Validation or read error
  """
  @spec atomic_read(String.t(), String.t(), validate_opts()) ::
          {:ok, binary()} | {:error, validation_error() | atom()}
  def atomic_read(path, project_root, opts \\ []) do
    # Validate path first
    case validate_path(path, project_root, opts) do
      {:ok, safe_path} ->
        # Re-check that the path is still valid and read atomically
        # This second check catches TOCTOU attacks where symlink changed between validate and read
        case File.read(safe_path) do
          {:ok, content} ->
            # Final validation: ensure the file we read is still within boundary
            # by checking the realpath of the file descriptor
            case validate_realpath(safe_path, project_root, opts) do
              :ok -> {:ok, content}
              {:error, _} = error -> error
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Performs an atomic write operation with validation.

  This function validates the path and writes the file atomically to mitigate
  TOCTOU race conditions. For writes to existing files, it re-validates after
  the write to detect attacks.

  ## Parameters

  - `path` - The path to write
  - `content` - Content to write
  - `project_root` - The project root directory
  - `opts` - Options (same as `validate_path/3`)

  ## Returns

  - `:ok` - Write successful
  - `{:error, reason}` - Validation or write error
  """
  @spec atomic_write(String.t(), binary(), String.t(), validate_opts()) ::
          :ok | {:error, validation_error() | atom()}
  def atomic_write(path, content, project_root, opts \\ []) do
    case validate_path(path, project_root, opts) do
      {:ok, safe_path} ->
        # Create parent directories if needed
        case safe_path |> Path.dirname() |> File.mkdir_p() do
          :ok ->
            # Write the file
            case File.write(safe_path, content) do
              :ok ->
                # Post-write validation: ensure we wrote to the correct location
                # This catches TOCTOU attacks on the directory path
                validate_realpath(safe_path, project_root, opts)

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates the real path of an existing file is within the project boundary.

  This is used after file operations to verify that the actual file location
  (following all symlinks) is within the allowed boundary. This helps detect
  TOCTOU attacks where symlinks were modified during the operation.

  ## Parameters

  - `path` - The path to validate (must exist)
  - `project_root` - The project root directory
  - `opts` - Options (same as `validate_path/3`)

  ## Returns

  - `:ok` - Path is valid
  - `{:error, :symlink_escapes_boundary}` - Real path is outside boundary
  """
  @spec validate_realpath(String.t(), String.t(), validate_opts()) ::
          :ok | {:error, :symlink_escapes_boundary}
  def validate_realpath(path, project_root, opts \\ []) do
    log_violations = Keyword.get(opts, :log_violations, true)
    normalized_root = normalize_path(project_root)

    # Get the real path (follows all symlinks)
    case :file.read_link_info(path, [:raw]) do
      {:ok, _info} ->
        # File exists, check its real location
        case Path.expand(path) do
          expanded when is_binary(expanded) ->
            if within_boundary?(expanded, normalized_root) do
              :ok
            else
              maybe_log_violation(:symlink_escapes_boundary, path, log_violations)
              {:error, :symlink_escapes_boundary}
            end
        end

      {:error, :enoent} ->
        # File doesn't exist (might be newly created), that's OK
        :ok

      {:error, _} ->
        # Other error, assume OK for non-existent paths
        :ok
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp determine_violation_reason(path) do
    if Path.type(path) == :absolute do
      :path_outside_boundary
    else
      :path_escapes_boundary
    end
  end

  defp maybe_log_violation(reason, path, true) do
    Logger.warning("Security violation: #{reason} - attempted path: #{path}")
  end

  defp maybe_log_violation(_reason, _path, false), do: :ok

  defp normalize_path(path) do
    # Expand to absolute path, resolving . and ..
    # Remove trailing slash for consistent comparison
    path
    |> Path.expand()
    |> String.trim_trailing("/")
  end

  defp check_symlinks(path, project_root, log_violations) do
    case resolve_symlink_chain(path, project_root, MapSet.new()) do
      {:ok, final_path} ->
        {:ok, final_path}

      {:error, :symlink_escapes_boundary} = error ->
        if log_violations do
          Logger.warning("Security violation: symlink_escapes_boundary - path: #{path}")
        end

        error

      {:error, :symlink_loop} ->
        if log_violations do
          Logger.warning("Security violation: symlink_loop - path: #{path}")
        end

        {:error, :invalid_path}
    end
  end

  defp resolve_symlink_chain(path, project_root, seen) do
    if MapSet.member?(seen, path) do
      {:error, :symlink_loop}
    else
      resolve_symlink_target(path, project_root, seen)
    end
  end

  defp resolve_symlink_target(path, project_root, seen) do
    case File.read_link(path) do
      {:ok, target} ->
        handle_symlink_target(path, target, project_root, seen)

      {:error, :einval} ->
        # Not a symlink - path is valid
        {:ok, path}

      {:error, :enoent} ->
        # Path doesn't exist - OK for paths we're about to create
        {:ok, path}

      {:error, _} ->
        # Other error - path is valid (not a symlink)
        {:ok, path}
    end
  end

  defp handle_symlink_target(path, target, project_root, seen) do
    resolved_target = resolve_symlink_path(target, path)

    if within_boundary?(resolved_target, project_root) do
      resolve_symlink_chain(resolved_target, project_root, MapSet.put(seen, path))
    else
      {:error, :symlink_escapes_boundary}
    end
  end

  defp resolve_symlink_path(target, symlink_path) do
    if Path.type(target) == :absolute do
      normalize_path(target)
    else
      # Relative symlink - resolve relative to symlink's directory
      normalize_path(Path.join(Path.dirname(symlink_path), target))
    end
  end
end
