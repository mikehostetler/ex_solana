defmodule JidoCode.Session.Settings do
  @moduledoc """
  Per-session settings loader that respects project-local configuration.

  This module provides session-scoped settings by accepting a `project_path`
  parameter, unlike `JidoCode.Settings` which uses `File.cwd!()` for the local path.

  ## Settings Paths

  - **Global**: `~/.jido_code/settings.json` (managed by `JidoCode.Settings`)
  - **Local**: `{project_path}/.jido_code/settings.json`

  ## Merge Behavior

  Local settings override global settings using shallow merge (`Map.merge/2`):

  ```
  global < local
  ```

  When loading settings for a session, the global settings are loaded first,
  then local settings are merged on top, with local values taking precedence.

  **Note**: This uses shallow merge intentionally. Session-specific settings
  typically override entire keys rather than merging nested structures.
  For deep merge behavior (e.g., combining model lists), use `JidoCode.Settings`
  directly with its caching and deep merge capabilities.

  ## Security

  All `project_path` parameters are validated to prevent:
  - Path traversal attacks (`..` components)
  - Non-absolute paths
  - Symlink-based escapes

  ## Caching

  This module does not cache settings. Each call reads from disk. This is
  intentional for session-scoped settings where:
  - Sessions are typically long-lived
  - Settings changes should be immediately visible
  - Per-session caching would add complexity without significant benefit

  For cached global settings, use `JidoCode.Settings` directly.

  ## Usage

      # Get local settings path for a project
      Session.Settings.local_path("/path/to/project")
      #=> "/path/to/project/.jido_code/settings.json"

      # Get local settings directory for a project
      Session.Settings.local_dir("/path/to/project")
      #=> "/path/to/project/.jido_code"

  ## Related Modules

  - `JidoCode.Settings` - Global settings management and caching
  - `JidoCode.Session` - Session struct with project_path field
  - `JidoCode.Session.Manager` - Per-session manager with security sandbox
  """

  require Logger

  alias JidoCode.Settings

  @local_dir_name ".jido_code"
  @settings_file "settings.json"
  @max_path_length 4096

  # ============================================================================
  # Settings Loading
  # ============================================================================

  @doc """
  Loads and merges settings from global and local files for a project.

  Settings are loaded with the following precedence (highest to lowest):
  1. Local settings (`{project_path}/.jido_code/settings.json`)
  2. Global settings (`~/.jido_code/settings.json`)

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  Merged settings map. Missing files are treated as empty maps.

  ## Error Handling

  - Missing files return empty map (no error)
  - Malformed JSON logs a warning and returns empty map
  - Invalid project_path raises ArgumentError
  - Always returns a map on success

  ## Examples

      iex> Session.Settings.load("/path/to/project")
      %{"provider" => "anthropic", "model" => "gpt-4o"}
  """
  @spec load(String.t()) :: map()
  def load(project_path) when is_binary(project_path) do
    safe_path = validate_project_path!(project_path)
    global = load_global()
    local = load_settings_file(local_path(safe_path), "local")
    Map.merge(global, local)
  end

  @doc """
  Loads settings from the global settings file.

  Reads from `~/.jido_code/settings.json`.

  ## Returns

  Settings map from the global file, or empty map if file doesn't exist
  or contains invalid JSON.

  ## Examples

      iex> Session.Settings.load_global()
      %{"provider" => "anthropic"}

      # When file doesn't exist
      iex> Session.Settings.load_global()
      %{}
  """
  @spec load_global() :: map()
  def load_global do
    load_settings_file(Settings.global_path(), "global")
  end

  @doc """
  Loads settings from a project's local settings file.

  Reads from `{project_path}/.jido_code/settings.json`.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  Settings map from the local file, or empty map if file doesn't exist
  or contains invalid JSON.

  ## Examples

      iex> Session.Settings.load_local("/path/to/project")
      %{"model" => "gpt-4o"}

      # When file doesn't exist
      iex> Session.Settings.load_local("/tmp/no-settings")
      %{}
  """
  @spec load_local(String.t()) :: map()
  def load_local(project_path) when is_binary(project_path) do
    safe_path = validate_project_path!(project_path)
    load_settings_file(local_path(safe_path), "local")
  end

  # ============================================================================
  # Settings Saving
  # ============================================================================

  @doc """
  Saves settings to a project's local settings file.

  Writes to `{project_path}/.jido_code/settings.json`. Creates the directory
  if it doesn't exist. Uses atomic write (temp file + rename) for crash safety.

  ## Parameters

  - `project_path` - Absolute path to the project root
  - `settings` - Settings map to save

  ## Returns

  - `:ok` - Settings saved successfully
  - `{:error, reason}` - Failed to save

  ## Examples

      iex> Session.Settings.save("/path/to/project", %{"provider" => "anthropic"})
      :ok

      iex> Session.Settings.save("/readonly/path", %{"model" => "gpt-4o"})
      {:error, "Permission denied"}
  """
  @spec save(String.t(), map()) :: :ok | {:error, term()}
  def save(project_path, settings) when is_binary(project_path) and is_map(settings) do
    safe_path = validate_project_path!(project_path)

    with {:ok, _} <- Settings.validate(settings),
         {:ok, _dir} <- ensure_local_dir(safe_path) do
      write_atomic(local_path(safe_path), settings)
    end
  end

  @doc """
  Updates a single setting key in a project's local settings file.

  Reads current local settings, merges the new key/value, and saves.

  ## Parameters

  - `project_path` - Absolute path to the project root
  - `key` - Setting key (string)
  - `value` - Setting value

  ## Returns

  - `:ok` - Setting updated successfully
  - `{:error, reason}` - Failed to update

  ## Examples

      iex> Session.Settings.set("/path/to/project", "provider", "openai")
      :ok

      iex> Session.Settings.set("/path/to/project", "model", "gpt-4o")
      :ok
  """
  @spec set(String.t(), String.t(), term()) :: :ok | {:error, term()}
  def set(project_path, key, value) when is_binary(project_path) and is_binary(key) do
    safe_path = validate_project_path!(project_path)
    current = load_settings_file(local_path(safe_path), "local")
    updated = Map.put(current, key, value)
    save(safe_path, updated)
  end

  # ============================================================================
  # Private: Path Validation (Security)
  # ============================================================================

  @doc false
  def validate_project_path!(path) when is_binary(path) do
    case validate_project_path(path) do
      {:ok, safe_path} -> safe_path
      {:error, reason} -> raise ArgumentError, "Invalid project path: #{reason}"
    end
  end

  @doc """
  Validates a project path for security.

  Checks for:
  - Path traversal attacks (`..` components)
  - Non-absolute paths
  - Excessive path length
  - Null bytes

  ## Parameters

  - `path` - Path to validate

  ## Returns

  - `{:ok, expanded_path}` - Path is safe, returns expanded absolute path
  - `{:error, reason}` - Path is invalid

  ## Examples

      iex> Session.Settings.validate_project_path("/home/user/project")
      {:ok, "/home/user/project"}

      iex> Session.Settings.validate_project_path("../escape")
      {:error, "path contains '..' traversal"}
  """
  @spec validate_project_path(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_project_path(path) when is_binary(path) do
    cond do
      byte_size(path) > @max_path_length ->
        {:error, "path exceeds maximum length of #{@max_path_length} bytes"}

      String.contains?(path, "\0") ->
        {:error, "path contains null byte"}

      String.contains?(path, "..") ->
        {:error, "path contains '..' traversal"}

      true ->
        expanded = Path.expand(path)

        if String.starts_with?(expanded, "/") do
          {:ok, expanded}
        else
          {:error, "path must be absolute"}
        end
    end
  end

  # ============================================================================
  # Private: Settings File Loading
  # ============================================================================

  defp load_settings_file(path, label) do
    case Settings.read_file(path) do
      {:ok, settings} ->
        settings

      {:error, :not_found} ->
        %{}

      {:error, {:invalid_json, reason}} ->
        Logger.warning("Malformed JSON in #{label} settings file")
        Logger.debug("Malformed JSON in #{label} settings file #{path}: #{reason}")
        %{}

      {:error, reason} ->
        Logger.warning("Failed to read #{label} settings file")
        Logger.debug("Failed to read #{label} settings file #{path}: #{inspect(reason)}")
        %{}
    end
  end

  # ============================================================================
  # Path Helpers
  # ============================================================================

  @doc """
  Returns the local settings directory path for a project.

  The settings directory is `{project_path}/.jido_code`.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  The full path to the settings directory.

  ## Examples

      iex> Session.Settings.local_dir("/home/user/myproject")
      "/home/user/myproject/.jido_code"

      iex> Session.Settings.local_dir("/tmp/test")
      "/tmp/test/.jido_code"
  """
  @spec local_dir(String.t()) :: String.t()
  def local_dir(project_path) when is_binary(project_path) do
    Path.join(project_path, @local_dir_name)
  end

  @doc """
  Returns the local settings file path for a project.

  The settings file is `{project_path}/.jido_code/settings.json`.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  The full path to the settings JSON file.

  ## Examples

      iex> Session.Settings.local_path("/home/user/myproject")
      "/home/user/myproject/.jido_code/settings.json"

      iex> Session.Settings.local_path("/tmp/test")
      "/tmp/test/.jido_code/settings.json"
  """
  @spec local_path(String.t()) :: String.t()
  def local_path(project_path) when is_binary(project_path) do
    Path.join(local_dir(project_path), @settings_file)
  end

  @doc """
  Ensures the local settings directory exists for a project.

  Creates `{project_path}/.jido_code` directory if it doesn't exist.
  Uses `File.mkdir_p/1` for recursive directory creation.

  Also validates that the created directory is not a symlink to prevent
  symlink-based attacks.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  - `{:ok, dir_path}` - Directory exists or was created successfully
  - `{:error, reason}` - Failed to create directory

  ## Examples

      iex> Session.Settings.ensure_local_dir("/path/to/project")
      {:ok, "/path/to/project/.jido_code"}

      iex> Session.Settings.ensure_local_dir("/readonly/path")
      {:error, "Permission denied"}
  """
  @spec ensure_local_dir(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def ensure_local_dir(project_path) when is_binary(project_path) do
    dir = local_dir(project_path)

    with :ok <- File.mkdir_p(dir),
         :ok <- validate_not_symlink(dir) do
      {:ok, dir}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, format_posix_error(reason)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_not_symlink(path) do
    case File.read_link(path) do
      {:ok, _target} ->
        {:error, "security violation: path is a symlink"}

      {:error, :einval} ->
        # Not a symlink, this is what we want
        :ok

      {:error, :enoent} ->
        # Path doesn't exist yet, that's fine
        :ok

      {:error, reason} ->
        {:error, format_posix_error(reason)}
    end
  end

  # ============================================================================
  # Private: Atomic File Writing
  # ============================================================================

  defp write_atomic(path, settings) do
    # Use random suffix to prevent TOCTOU attacks
    random_suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    temp_path = "#{path}.tmp.#{random_suffix}"
    json = Jason.encode!(settings, pretty: true)
    expected_size = byte_size(json)

    try do
      # Write to temp file
      File.write!(temp_path, json)

      # Set permissions on temp file BEFORE rename to prevent race condition
      File.chmod!(temp_path, 0o600)

      # Verify temp file is not a symlink before rename
      case File.read_link(temp_path) do
        {:ok, _} ->
          {:error, "security violation: temp file replaced with symlink"}

        {:error, :einval} ->
          # Not a symlink, safe to proceed
          File.rename!(temp_path, path)

          # Verify the final file exists and has expected size
          case File.stat(path) do
            {:ok, %{size: ^expected_size}} ->
              :ok

            {:ok, %{size: actual_size}} ->
              {:error,
               "File size mismatch after write: expected #{expected_size}, got #{actual_size}"}

            {:error, reason} ->
              {:error, "Failed to verify written file: #{format_posix_error(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to verify temp file: #{format_posix_error(reason)}"}
      end
    rescue
      e in File.Error ->
        # Clean up temp file on error
        File.rm(temp_path)
        {:error, Exception.message(e)}
    end
  end

  defp format_posix_error(:eacces), do: "Permission denied"
  defp format_posix_error(:enoent), do: "No such file or directory"
  defp format_posix_error(:enospc), do: "No space left on device"
  defp format_posix_error(:eexist), do: "File already exists"
  defp format_posix_error(:eisdir), do: "Is a directory"
  defp format_posix_error(:enotdir), do: "Not a directory"
  defp format_posix_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_posix_error(reason), do: inspect(reason)
end
