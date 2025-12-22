defmodule JidoCode.Tools.HandlerHelpers do
  @moduledoc """
  Shared helper functions for tool handlers.

  This module consolidates common functionality used across FileSystem,
  Search, and Shell handlers to reduce code duplication.

  ## Session-Aware Context

  Tool handlers receive a context map that may contain:

  - `:session_id` - Session identifier (must be valid UUID format)
  - `:project_root` - Direct project root path (legacy)

  The helpers prefer session context when available:

  1. `session_id` present (valid UUID) → Uses `Session.Manager` for that session
  2. `project_root` present → Uses the provided path directly
  3. Neither → Falls back to global `Tools.Manager` (deprecated, logs warning)

  ## Session ID Format

  Session IDs must be valid UUIDs (e.g., "550e8400-e29b-41d4-a716-446655440000").
  Invalid formats return `{:error, :invalid_session_id}`.

  ## Functions

  - `get_project_root/1` - Extract project root from context (session-aware)
  - `validate_path/2` - Validate path within security boundary (session-aware)
  - `format_common_error/2` - Format errors common across all handlers

  ## Usage

      alias JidoCode.Tools.HandlerHelpers

      # Session-aware (preferred)
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}
      with {:ok, project_root} <- HandlerHelpers.get_project_root(context),
           {:ok, safe_path} <- HandlerHelpers.validate_path("src/file.ex", context) do
        # use safe_path
      end

      # Legacy (deprecated)
      context = %{project_root: "/path/to/project"}
      with {:ok, project_root} <- HandlerHelpers.get_project_root(context) do
        # use project_root
      end

  ## Configuration

  To suppress deprecation warnings (useful for tests):

      Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

  To require session context (disables fallback to global Manager):

      config :jido_code, require_session_context: true

  When `require_session_context` is true, calls without `session_id` or
  `project_root` will return `{:error, :session_context_required}` instead
  of falling back to the global `Tools.Manager`.
  """

  require Logger

  alias JidoCode.Session
  alias JidoCode.Tools.{Manager, Security}
  alias JidoCode.Utils.UUID, as: UUIDUtils

  @doc """
  Extracts the project root from the context map.

  Checks in priority order:

  1. `session_id` (valid UUID) - Delegates to `Session.Manager.project_root/1`
  2. `project_root` - Returns the provided path directly
  3. Neither - Falls back to `Tools.Manager.project_root/0` (deprecated, logs warning)

  ## Examples

      # Session-aware (preferred)
      iex> HandlerHelpers.get_project_root(%{session_id: "550e8400-e29b-41d4-a716-446655440000"})
      {:ok, "/path/from/session/manager"}

      # Invalid session_id format
      iex> HandlerHelpers.get_project_root(%{session_id: "invalid"})
      {:error, :invalid_session_id}

      # Direct project_root (legacy)
      iex> HandlerHelpers.get_project_root(%{project_root: "/home/user/project"})
      {:ok, "/home/user/project"}

      # Fallback to global (deprecated)
      iex> HandlerHelpers.get_project_root(%{})
      # Returns Manager.project_root() result with deprecation warning
  """
  @spec get_project_root(map()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_session_id | String.t()}
  def get_project_root(%{session_id: session_id}) when is_binary(session_id) do
    if valid_session_id?(session_id) do
      emit_context_telemetry(:session_id, session_id)
      Session.Manager.project_root(session_id)
    else
      {:error, :invalid_session_id}
    end
  end

  def get_project_root(%{project_root: root}) when is_binary(root) do
    emit_context_telemetry(:project_root, nil)
    {:ok, root}
  end

  def get_project_root(_context) do
    if Application.get_env(:jido_code, :require_session_context, false) do
      {:error, :session_context_required}
    else
      emit_context_telemetry(:global_fallback, nil)
      log_deprecation_warning("get_project_root")
      Manager.project_root()
    end
  end

  @doc """
  Validates a path within the security boundary.

  Checks in priority order:

  1. `session_id` (valid UUID) - Delegates to `Session.Manager.validate_path/2`
  2. `project_root` - Uses `Security.validate_path/3` directly
  3. Neither - Falls back to `Tools.Manager.validate_path/1` (deprecated, logs warning)

  ## Parameters

  - `path` - The path to validate (relative or absolute)
  - `context` - Context map with `session_id` or `project_root`

  ## Returns

  - `{:ok, resolved_path}` - Path is valid and resolved
  - `{:error, reason}` - Path validation failed

  ## Examples

      # Session-aware (preferred)
      iex> HandlerHelpers.validate_path("src/file.ex", %{session_id: "550e8400-e29b-41d4-a716-446655440000"})
      {:ok, "/project/src/file.ex"}

      # Invalid session_id format
      iex> HandlerHelpers.validate_path("src/file.ex", %{session_id: "invalid"})
      {:error, :invalid_session_id}

      # Direct project_root
      iex> HandlerHelpers.validate_path("src/file.ex", %{project_root: "/project"})
      {:ok, "/project/src/file.ex"}

      # Security violation
      iex> HandlerHelpers.validate_path("../../../etc/passwd", context)
      {:error, :path_escapes_boundary}
  """
  @spec validate_path(String.t(), map()) ::
          {:ok, String.t()} | {:error, atom() | :not_found | :invalid_session_id}
  def validate_path(path, %{session_id: session_id}) when is_binary(session_id) do
    if valid_session_id?(session_id) do
      Session.Manager.validate_path(session_id, path)
    else
      {:error, :invalid_session_id}
    end
  end

  def validate_path(path, %{project_root: root}) when is_binary(root) do
    Security.validate_path(path, root, log_violations: true)
  end

  def validate_path(path, _context) do
    if Application.get_env(:jido_code, :require_session_context, false) do
      {:error, :session_context_required}
    else
      log_deprecation_warning("validate_path")
      Manager.validate_path(path)
    end
  end

  @doc """
  Formats common error types used across all handlers.

  Returns the formatted error message. Handlers may extend this with
  domain-specific error patterns.

  ## Common Errors

  - `:enoent` - File/path not found
  - `:eacces` - Permission denied
  - `:path_escapes_boundary` - Path traversal attempt
  - `:path_outside_boundary` - Path outside project
  - `:symlink_escapes_boundary` - Symlink points outside project

  ## Examples

      iex> HandlerHelpers.format_common_error(:enoent, "/path/to/file")
      {:ok, "Path not found: /path/to/file"}

      iex> HandlerHelpers.format_common_error(:custom_error, "/path")
      :not_handled
  """
  @spec format_common_error(atom() | tuple() | String.t(), String.t()) ::
          {:ok, String.t()} | :not_handled
  def format_common_error(:enoent, path), do: {:ok, "Path not found: #{path}"}
  def format_common_error(:eacces, path), do: {:ok, "Permission denied: #{path}"}

  def format_common_error(:path_escapes_boundary, path),
    do: {:ok, "Security error: path escapes project boundary: #{path}"}

  def format_common_error(:path_outside_boundary, path),
    do: {:ok, "Security error: path is outside project: #{path}"}

  def format_common_error(:symlink_escapes_boundary, path),
    do: {:ok, "Security error: symlink points outside project: #{path}"}

  def format_common_error(:invalid_session_id, _path),
    do: {:ok, "Invalid session ID format (expected UUID)"}

  def format_common_error(:session_context_required, _path),
    do: {:ok, "Session context required (session_id or project_root must be provided)"}

  def format_common_error(reason, _path) when is_binary(reason), do: {:ok, reason}
  def format_common_error(_reason, _path), do: :not_handled

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp valid_session_id?(session_id) do
    UUIDUtils.valid?(session_id)
  end

  defp emit_context_telemetry(context_type, session_id) do
    :telemetry.execute(
      [:jido_code, :handler_helpers, :context_resolution],
      %{count: 1},
      %{type: context_type, session_id: session_id}
    )
  end

  defp log_deprecation_warning(function_name) do
    unless Application.get_env(:jido_code, :suppress_global_manager_warnings, false) do
      Logger.warning(
        "HandlerHelpers.#{function_name}/1 falling back to global Tools.Manager - " <>
          "migrate to session-aware context with session_id"
      )
    end
  end
end
