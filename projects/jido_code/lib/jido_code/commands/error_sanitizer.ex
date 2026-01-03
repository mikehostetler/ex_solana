defmodule JidoCode.Commands.ErrorSanitizer do
  @moduledoc """
  Sanitizes internal error reasons to user-friendly messages.

  This module prevents information disclosure by converting internal error
  details (file paths, UUIDs, system errors) into generic user-facing messages
  while preserving detailed logging for debugging.

  ## Security Rationale

  Internal errors often contain sensitive information:
  - File system paths (e.g., `/home/user/.jido_code/sessions/abc-123.json`)
  - Session IDs (UUIDs that could be enumerated)
  - System error atoms (`:eacces`, `:enoent`, etc. reveal system state)
  - Stack traces or function names (reveal implementation details)

  By sanitizing these before displaying to users, we prevent:
  - Path traversal reconnaissance
  - Session ID enumeration attacks
  - Information leakage in multi-user systems
  - Detailed error analysis by attackers

  ## Usage

  ```elixir
  case some_operation() do
    {:error, reason} ->
      # Log detailed error internally
      ErrorSanitizer.log_and_sanitize(reason, "operation context")
  end
  ```

  The function will:
  1. Log the detailed error at appropriate level (debug/warn/error)
  2. Return a generic user-friendly error message
  """

  require Logger

  @doc """
  Logs detailed error internally and returns sanitized user-facing message.

  ## Parameters

  - `reason` - Internal error reason (atom, tuple, string, etc.)
  - `context` - Context string for logging (e.g., "list sessions", "resume session")

  ## Returns

  A generic user-friendly error string safe to display to users.

  ## Examples

      iex> ErrorSanitizer.log_and_sanitize({:file_error, "/path/to/file", :eacces}, "read file")
      "Operation failed. Please try again or contact support."

      iex> ErrorSanitizer.log_and_sanitize(:some_internal_error, "save session")
      "Operation failed. Please try again or contact support."
  """
  @spec log_and_sanitize(term(), String.t()) :: String.t()
  def log_and_sanitize(reason, context) do
    # Log detailed error for internal debugging
    Logger.warning("Failed to #{context}: #{inspect(reason)}")

    # Return generic user-friendly message
    sanitize_error(reason)
  end

  @doc """
  Converts internal error reasons to user-friendly messages.

  Returns generic messages for unknown errors to prevent information disclosure.

  ## Examples

      iex> ErrorSanitizer.sanitize_error(:eacces)
      "Permission denied."

      iex> ErrorSanitizer.sanitize_error(:enoent)
      "Resource not found."

      iex> ErrorSanitizer.sanitize_error({:unknown_error, "details"})
      "Operation failed. Please try again or contact support."
  """
  @spec sanitize_error(term()) :: String.t()

  # File system errors - common and should have helpful messages
  def sanitize_error(:eacces), do: "Permission denied."
  def sanitize_error(:enoent), do: "Resource not found."
  def sanitize_error(:enotdir), do: "Invalid path."
  def sanitize_error(:eexist), do: "Resource already exists."
  def sanitize_error(:enospc), do: "Insufficient disk space."
  def sanitize_error(:erofs), do: "Read-only file system."
  def sanitize_error(:emfile), do: "Too many open files."
  def sanitize_error(:enametoolong), do: "Path name too long."

  # Session-specific errors - already have user-friendly messages
  def sanitize_error(:not_found), do: "Session not found."
  def sanitize_error(:project_path_not_found), do: "Project path no longer exists."
  def sanitize_error(:project_path_not_directory), do: "Project path is not a directory."
  def sanitize_error(:project_path_changed), do: "Project path properties changed unexpectedly."
  def sanitize_error(:project_already_open), do: "Project already open in another session."
  def sanitize_error(:session_limit_reached), do: "Maximum sessions reached."

  def sanitize_error(:path_permission_denied),
    do: "Permission denied. Check directory read/write permissions."

  def sanitize_error(:path_no_space), do: "Insufficient disk space."

  # Path validation errors from Session.new/1
  def sanitize_error(:path_not_found), do: "Path does not exist."
  def sanitize_error(:path_not_directory), do: "Path is not a directory."
  def sanitize_error(:path_traversal_detected), do: "Invalid path."
  def sanitize_error(:path_not_absolute), do: "Path must be absolute."
  def sanitize_error(:path_too_long), do: "Path exceeds maximum length."
  def sanitize_error(:symlink_escape), do: "Invalid symlink target."

  def sanitize_error({:session_limit_reached, current, max}),
    do: "Maximum sessions reached (#{current}/#{max} sessions open). Close a session first."

  def sanitize_error(:save_in_progress), do: "Save operation already in progress."

  # Validation errors - generic to avoid exposing internal structure
  def sanitize_error({:missing_fields, _fields}), do: "Invalid data format."
  def sanitize_error({:invalid_id, _}), do: "Invalid identifier."
  def sanitize_error({:invalid_version, _}), do: "Unsupported format version."
  def sanitize_error({:unsupported_version, _}), do: "Unsupported format version."
  def sanitize_error(:invalid_session_id), do: "Invalid session identifier."

  # Cryptographic errors - don't expose details
  def sanitize_error(:signature_verification_failed), do: "Data integrity check failed."
  def sanitize_error({:signature_verification_failed, _}), do: "Data integrity check failed."

  # JSON errors - generic message
  def sanitize_error({:json_encode_error, _}), do: "Data encoding failed."
  def sanitize_error({:json_decode_error, _}), do: "Data format error."

  # File operation errors with details - strip the details
  def sanitize_error({:file_error, _path, reason}), do: sanitize_error(reason)
  def sanitize_error({:read_error, _path, reason}), do: sanitize_error(reason)
  def sanitize_error({:write_error, _path, reason}), do: sanitize_error(reason)

  # Catch-all for any other internal errors
  # This is the most important case - prevents exposing unknown error details
  def sanitize_error(_reason) do
    "Operation failed. Please try again or contact support."
  end
end
