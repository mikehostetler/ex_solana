defmodule JidoCode.Session do
  @moduledoc """
  Represents a work session in JidoCode.

  A session encapsulates all context for working on a specific project:
  - Project directory and sandbox boundary
  - LLM configuration (provider, model, parameters)
  - Programming language (auto-detected or manually set)
  - Conversation history and task list (via Session.State)
  - Creation and update timestamps

  Sessions are managed by the SessionRegistry and supervised by SessionSupervisor.
  Each session runs in isolation with its own Manager process for security enforcement.

  ## Path Validation and Security

  Session creation performs comprehensive path validation including:

  - **Existence and Type** - Path must exist and be a directory
  - **Safety Checks** - No path traversal (..), must be absolute, length limits
  - **Symlink Security** - Symlinks are followed and validated for safety
  - **Permission Checks** - User must have read, write, and execute permissions

  These checks prevent common security issues and ensure clear error messages
  upfront rather than confusing failures during file operations.

  ## Example

      iex> session = %JidoCode.Session{
      ...>   id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   name: "my-project",
      ...>   project_path: "/home/user/projects/my-project",
      ...>   config: %{
      ...>     provider: "anthropic",
      ...>     model: "claude-3-5-sonnet-20241022",
      ...>     temperature: 0.7,
      ...>     max_tokens: 4096
      ...>   },
      ...>   created_at: ~U[2024-01-15 10:00:00Z],
      ...>   updated_at: ~U[2024-01-15 10:00:00Z]
      ...> }
      %JidoCode.Session{...}

  ## Fields

  - `id` - RFC 4122 UUID v4 uniquely identifying the session
  - `name` - Display name shown in tabs (defaults to folder name)
  - `project_path` - Absolute path to the project directory (validated for permissions)
  - `config` - LLM configuration map with provider, model, temperature, max_tokens
  - `language` - Programming language atom (auto-detected or manually set, defaults to :elixir)
  - `created_at` - UTC timestamp when session was created
  - `updated_at` - UTC timestamp of last modification
  """

  alias JidoCode.Language

  require Logger

  @typedoc """
  LLM configuration for a session.

  - `provider` - Provider name (e.g., "anthropic", "openai", "ollama")
  - `model` - Model identifier (e.g., "claude-3-5-sonnet-20241022")
  - `temperature` - Sampling temperature (0.0 to 2.0), accepts float or integer
  - `max_tokens` - Maximum tokens in response
  """
  @type config :: %{
          provider: String.t(),
          model: String.t(),
          temperature: float() | integer(),
          max_tokens: pos_integer()
        }

  @typedoc """
  Connection status of the LLM agent for this session.

  - `:disconnected` - LLM agent not started (no credentials or not attempted)
  - `:connected` - LLM agent running and ready
  - `:error` - LLM agent failed to start (credentials invalid, network error, etc.)
  """
  @type connection_status :: :disconnected | :connected | :error

  @typedoc """
  A work session representing an isolated project context.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          project_path: String.t(),
          config: config(),
          language: Language.language(),
          connection_status: connection_status(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :name,
    :project_path,
    :config,
    :created_at,
    :updated_at,
    language: :elixir,
    connection_status: :disconnected
  ]

  # Default LLM configuration when Settings doesn't provide one
  @default_config %{
    provider: "anthropic",
    model: "claude-3-5-sonnet-20241022",
    temperature: 0.7,
    max_tokens: 4096
  }

  # Maximum allowed length for session name
  @max_name_length 50

  # Maximum allowed path length (Linux PATH_MAX)
  @max_path_length 4096

  # Config keys we support (for normalization)
  @config_keys [:provider, :model, :temperature, :max_tokens]

  @doc """
  Creates a new session with the given options.

  Validates the project path through multiple security and accessibility checks:
  - Path safety (no traversal, absolute path)
  - Path existence and type (must be a directory)
  - Symlink safety (if symlink, target must be valid)
  - **Permissions** (user must have read, write, and execute access)

  ## Options

  - `:project_path` (required) - Absolute path to the project directory
  - `:name` (optional) - Display name for the session, defaults to folder name
  - `:config` (optional) - LLM configuration map, defaults to global settings

  ## Returns

  - `{:ok, session}` - Successfully created session
  - `{:error, :missing_project_path}` - project_path option not provided
  - `{:error, :invalid_project_path}` - project_path is not a string
  - `{:error, :path_not_found}` - project_path does not exist
  - `{:error, :path_not_directory}` - project_path is not a directory
  - `{:error, :path_traversal_detected}` - path contains traversal sequences (..)
  - `{:error, :path_not_absolute}` - path is not absolute
  - `{:error, :path_too_long}` - path exceeds 4096 bytes
  - `{:error, :symlink_escape}` - symlink target contains traversal sequences
  - `{:error, :path_permission_denied}` - insufficient read/write/execute permissions
  - `{:error, :path_no_space}` - insufficient disk space for write test

  ## Permission Validation

  The session creation checks that the user has necessary permissions on the directory:

  - **Read permission** - Required to list files and read content
  - **Execute permission** - Required to traverse/access the directory
  - **Write permission** - Required for tool operations (write_file, etc.)

  Permission checks are performed upfront to provide clear error messages rather than
  confusing failures during file operations.

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/home/user/my-project")
      iex> session.name
      "my-project"

      iex> {:ok, session} = JidoCode.Session.new(
      ...>   project_path: "/home/user/my-project",
      ...>   name: "Custom Name"
      ...> )
      iex> session.name
      "Custom Name"

      iex> JidoCode.Session.new(project_path: "/nonexistent/path")
      {:error, :path_not_found}

      iex> JidoCode.Session.new(project_path: "/root/protected")
      {:error, :path_permission_denied}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(opts) when is_list(opts) do
    with {:ok, project_path} <- fetch_project_path(opts),
         :ok <- validate_path_length(project_path),
         :ok <- validate_path_safe(project_path),
         :ok <- validate_path_exists(project_path),
         :ok <- validate_path_is_directory(project_path),
         :ok <- validate_symlink_safe(project_path),
         :ok <- validate_path_permissions(project_path) do
      now = DateTime.utc_now()
      expanded_path = Path.expand(project_path)

      session = %__MODULE__{
        id: generate_id(),
        name: opts[:name] || Path.basename(project_path),
        project_path: expanded_path,
        config: opts[:config] || load_default_config(),
        language: Language.detect(expanded_path),
        created_at: now,
        updated_at: now
      }

      {:ok, session}
    end
  end

  # Fetch and validate project_path from options
  defp fetch_project_path(opts) do
    case Keyword.fetch(opts, :project_path) do
      {:ok, path} when is_binary(path) -> {:ok, path}
      {:ok, _} -> {:error, :invalid_project_path}
      :error -> {:error, :missing_project_path}
    end
  end

  # Validate path length (S4)
  defp validate_path_length(path) do
    if byte_size(path) <= @max_path_length do
      :ok
    else
      {:error, :path_too_long}
    end
  end

  # Validate path doesn't contain traversal sequences (B1)
  defp validate_path_safe(path) do
    expanded = Path.expand(path)

    cond do
      # Check for .. in the original path
      String.contains?(path, "..") ->
        {:error, :path_traversal_detected}

      # Must be absolute after expansion
      not String.starts_with?(expanded, "/") ->
        {:error, :path_not_absolute}

      true ->
        :ok
    end
  end

  # Validate that the path exists
  defp validate_path_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :path_not_found}
    end
  end

  # Validate that the path is a directory
  defp validate_path_is_directory(path) do
    if File.dir?(path) do
      :ok
    else
      {:error, :path_not_directory}
    end
  end

  # Validate symlinks don't escape to unexpected locations (B2)
  defp validate_symlink_safe(path) do
    case File.read_link(path) do
      {:ok, target} ->
        # Path is a symlink, validate the target
        resolved_target =
          if String.starts_with?(target, "/") do
            target
          else
            Path.join(Path.dirname(path), target) |> Path.expand()
          end

        # Ensure symlink target exists and is a directory
        cond do
          not File.exists?(resolved_target) ->
            {:error, :path_not_found}

          not File.dir?(resolved_target) ->
            {:error, :path_not_directory}

          # Check target doesn't contain traversal (belt and suspenders)
          String.contains?(resolved_target, "..") ->
            {:error, :symlink_escape}

          true ->
            :ok
        end

      {:error, :einval} ->
        # Not a symlink, that's fine
        :ok

      {:error, _} ->
        # Other error reading link, path might not exist
        :ok
    end
  end

  # Validate that the user has necessary permissions on the directory
  #
  # This check ensures the user has read, write, and execute permissions
  # before creating a session. This prevents confusing errors later when
  # file operations fail due to permission issues.
  #
  # Implementation approach:
  # - Read + Execute: Tested via File.ls/1 (requires both to list directory)
  # - Write: Tested by creating and deleting a temp file
  #
  # The temp file approach is safe because:
  # - Uses System.unique_integer/1 to avoid collisions
  # - Prefixed with .jido_code_permission_check_ for easy identification
  # - Immediately deleted after successful creation
  # - Empty file (no data written to disk)
  defp validate_path_permissions(path) do
    # Check read + execute permissions by attempting to list directory
    case File.ls(path) do
      {:ok, _} ->
        # Successfully listed - read and execute permissions are OK
        # Now check write permission by attempting to create a temp file
        validate_write_permission(path)

      {:error, :eacces} ->
        {:error, :path_permission_denied}

      {:error, :enoent} ->
        # Should have been caught by validate_path_exists, but handle it anyway
        {:error, :path_not_found}

      {:error, _other} ->
        {:error, :path_permission_denied}
    end
  end

  # Validate write permission by attempting to create and delete a temp file
  defp validate_write_permission(path) do
    # Generate a unique temp filename
    temp_file =
      Path.join(path, ".jido_code_permission_check_#{System.unique_integer([:positive])}")

    case File.write(temp_file, "") do
      :ok ->
        # Write succeeded, clean up and return success
        File.rm(temp_file)
        :ok

      {:error, :eacces} ->
        {:error, :path_permission_denied}

      {:error, :enospc} ->
        {:error, :path_no_space}

      {:error, _other} ->
        {:error, :path_permission_denied}
    end
  end

  # Load default config from Settings or use fallback defaults
  # Settings.load/0 always returns {:ok, settings} but may return empty map if no settings file
  defp load_default_config do
    {:ok, settings} = JidoCode.Settings.load()

    # Log if settings appear to be empty/default (C4 - inform user of fallback)
    if map_size(settings) == 0 do
      Logger.debug("No settings file found, using default configuration")
    end

    %{
      provider: Map.get(settings, "provider", @default_config.provider),
      model: Map.get(settings, "model", @default_config.model),
      temperature: Map.get(settings, "temperature", @default_config.temperature),
      max_tokens: Map.get(settings, "max_tokens", @default_config.max_tokens)
    }
  end

  @doc """
  Generates an RFC 4122 compliant UUID v4 (random).

  The UUID is generated using cryptographically secure random bytes with:
  - Version bits set to 4 (random UUID)
  - Variant bits set to 2 (RFC 4122)
  - Formatted as standard UUID string (8-4-4-4-12)

  ## Examples

      iex> id = JidoCode.Session.generate_id()
      iex> Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, id)
      true
  """
  @spec generate_id() :: String.t()
  def generate_id do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)

    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  # Format hex string as UUID (8-4-4-4-12)
  defp format_uuid(hex) do
    <<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>> = hex
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  @doc """
  Validates a session struct, checking all fields for correctness.

  Returns `{:ok, session}` if all validations pass, or `{:error, reasons}`
  with a list of all validation failures.

  ## Validation Rules

  - `id` - Must be a non-empty string
  - `name` - Must be a non-empty string, max #{@max_name_length} characters
  - `project_path` - Must be an absolute path to an existing directory
  - `config.provider` - Must be a non-empty string
  - `config.model` - Must be a non-empty string
  - `config.temperature` - Must be a float or integer between 0 and 2
  - `config.max_tokens` - Must be a positive integer
  - `created_at` - Must be a DateTime
  - `updated_at` - Must be a DateTime

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> JidoCode.Session.validate(session)
      {:ok, session}

      iex> session = %JidoCode.Session{id: "", name: "test"}
      iex> {:error, reasons} = JidoCode.Session.validate(session)
      iex> :invalid_id in reasons
      true
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [atom()]}
  def validate(%__MODULE__{} = session) do
    errors =
      []
      |> validate_id(session.id)
      |> validate_name(session.name)
      |> validate_project_path(session.project_path)
      |> validate_config(session.config)
      |> validate_created_at(session.created_at)
      |> validate_updated_at(session.updated_at)

    case errors do
      [] -> {:ok, session}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Boolean predicates for validation (C3 - single source of truth)
  defp valid_id?(id), do: is_binary(id) and byte_size(id) > 0
  defp valid_name?(name), do: is_binary(name) and byte_size(name) > 0
  defp valid_name_length?(name), do: String.length(name) <= @max_name_length
  defp valid_provider?(nil), do: true
  defp valid_provider?(p), do: is_binary(p) and byte_size(p) > 0
  defp valid_model?(nil), do: true
  defp valid_model?(m), do: is_binary(m) and byte_size(m) > 0

  defp valid_temperature?(t) do
    (is_float(t) and t >= 0.0 and t <= 2.0) or (is_integer(t) and t >= 0 and t <= 2)
  end

  defp valid_max_tokens?(t), do: is_integer(t) and t > 0

  # Accumulating validators using boolean predicates (C3)
  defp validate_id(errors, id) do
    if valid_id?(id), do: errors, else: [:invalid_id | errors]
  end

  defp validate_name(errors, name) do
    cond do
      not valid_name?(name) -> [:invalid_name | errors]
      not valid_name_length?(name) -> [:name_too_long | errors]
      true -> errors
    end
  end

  # Renamed from validate_session_project_path for consistency
  defp validate_project_path(errors, path) when is_binary(path) do
    cond do
      not String.starts_with?(path, "/") ->
        [:path_not_absolute | errors]

      not File.exists?(path) ->
        [:path_not_found | errors]

      not File.dir?(path) ->
        [:path_not_directory | errors]

      true ->
        errors
    end
  end

  defp validate_project_path(errors, _), do: [:invalid_project_path | errors]

  # Validate config map using boolean predicates
  defp validate_config(errors, config) when is_map(config) do
    normalized = normalize_config_keys(config)

    errors
    |> validate_config_provider(normalized[:provider])
    |> validate_config_model(normalized[:model])
    |> validate_config_temperature(normalized[:temperature])
    |> validate_config_max_tokens(normalized[:max_tokens])
  end

  defp validate_config(errors, _), do: [:invalid_config | errors]

  defp validate_config_provider(errors, provider) do
    if valid_provider?(provider), do: errors, else: [:invalid_provider | errors]
  end

  defp validate_config_model(errors, model) do
    if valid_model?(model), do: errors, else: [:invalid_model | errors]
  end

  defp validate_config_temperature(errors, temp) do
    if valid_temperature?(temp), do: errors, else: [:invalid_temperature | errors]
  end

  defp validate_config_max_tokens(errors, tokens) do
    if valid_max_tokens?(tokens), do: errors, else: [:invalid_max_tokens | errors]
  end

  # Dedicated timestamp validators (S3 - replace then/2 chains)
  defp validate_created_at(errors, %DateTime{}), do: errors
  defp validate_created_at(errors, _), do: [:invalid_created_at | errors]

  defp validate_updated_at(errors, %DateTime{}), do: errors
  defp validate_updated_at(errors, _), do: [:invalid_updated_at | errors]

  @doc """
  Updates the LLM configuration for a session.

  Merges the new config values with the existing config, allowing partial updates.
  Only known config keys (provider, model, temperature, max_tokens) are merged.
  The `updated_at` timestamp is set to the current UTC time.

  ## Parameters

  - `session` - The session to update
  - `new_config` - A map with config values to merge (atom or string keys)

  ## Returns

  - `{:ok, updated_session}` - Successfully updated session
  - `{:error, [reasons]}` - List of validation errors (consistent with validate/1)

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, updated} = JidoCode.Session.update_config(session, %{temperature: 0.5})
      iex> updated.config.temperature
      0.5

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, updated} = JidoCode.Session.update_config(session, %{provider: "openai", model: "gpt-4"})
      iex> {updated.config.provider, updated.config.model}
      {"openai", "gpt-4"}
  """
  @spec update_config(t(), map()) :: {:ok, t()} | {:error, [atom()]}
  def update_config(%__MODULE__{} = session, new_config) when is_map(new_config) do
    merged_config = merge_config(session.config, new_config)

    # C1: Use accumulating validation pattern (consistent with validate/1)
    errors =
      []
      |> validate_config_provider(merged_config[:provider])
      |> validate_config_model(merged_config[:model])
      |> validate_config_temperature(merged_config[:temperature])
      |> validate_config_max_tokens(merged_config[:max_tokens])

    case errors do
      [] ->
        {:ok, touch(session, %{config: merged_config})}

      errors ->
        {:error, Enum.reverse(errors)}
    end
  end

  def update_config(%__MODULE__{}, _), do: {:error, [:invalid_config]}

  # Normalize config keys to atoms (S2)
  defp normalize_config_keys(config) do
    Enum.reduce(@config_keys, %{}, fn key, acc ->
      string_key = Atom.to_string(key)
      value = get_config_value(config, key, string_key)
      Map.put(acc, key, value)
    end)
  end

  # Get config value checking both atom and string keys (C2 - fix || operator issue)
  defp get_config_value(config, atom_key, string_key) do
    cond do
      Map.has_key?(config, atom_key) -> Map.get(config, atom_key)
      Map.has_key?(config, string_key) -> Map.get(config, string_key)
      true -> nil
    end
  end

  # Merge new config values with existing config (C2 - proper handling of falsy values)
  defp merge_config(existing, new_config) do
    existing_normalized = normalize_config_keys(existing)
    new_normalized = normalize_config_keys(new_config)

    # Merge, preferring new values when key is present (even if value is falsy)
    Enum.reduce(@config_keys, %{}, fn key, acc ->
      value =
        if Map.has_key?(new_config, key) or Map.has_key?(new_config, Atom.to_string(key)) do
          new_normalized[key]
        else
          existing_normalized[key]
        end

      Map.put(acc, key, value)
    end)
  end

  @doc """
  Renames a session.

  Updates the session name after validating the new name meets requirements.
  The `updated_at` timestamp is set to the current UTC time.

  ## Parameters

  - `session` - The session to rename
  - `new_name` - The new name for the session

  ## Returns

  - `{:ok, updated_session}` - Successfully renamed session
  - `{:error, :invalid_name}` - new_name is empty or not a string
  - `{:error, :name_too_long}` - new_name exceeds #{@max_name_length} characters

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, renamed} = JidoCode.Session.rename(session, "My Project")
      iex> renamed.name
      "My Project"

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> JidoCode.Session.rename(session, "")
      {:error, :invalid_name}
  """
  @spec rename(t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def rename(%__MODULE__{} = session, new_name) when is_binary(new_name) do
    cond do
      not valid_name?(new_name) ->
        {:error, :invalid_name}

      not valid_name_length?(new_name) ->
        {:error, :name_too_long}

      true ->
        {:ok, touch(session, %{name: new_name})}
    end
  end

  def rename(%__MODULE__{}, _), do: {:error, :invalid_name}

  @doc """
  Sets the programming language for a session.

  Validates and normalizes the language value before setting.
  Accepts language atoms (`:python`), strings (`"python"`), or aliases (`"py"`).
  The `updated_at` timestamp is set to the current UTC time.

  ## Parameters

  - `session` - The session to update
  - `language` - Language atom, string, or alias to set

  ## Returns

  - `{:ok, updated_session}` - Successfully updated session
  - `{:error, :invalid_language}` - language is not a supported value

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, updated} = JidoCode.Session.set_language(session, :python)
      iex> updated.language
      :python

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, updated} = JidoCode.Session.set_language(session, "js")
      iex> updated.language
      :javascript
  """
  @spec set_language(t(), Language.language() | String.t()) :: {:ok, t()} | {:error, :invalid_language}
  def set_language(%__MODULE__{} = session, language) do
    case Language.normalize(language) do
      {:ok, normalized} ->
        {:ok, touch(session, %{language: normalized})}

      {:error, :invalid_language} ->
        {:error, :invalid_language}
    end
  end

  # Helper to update session fields and touch updated_at timestamp (S1)
  defp touch(session, changes) do
    session
    |> Map.merge(changes)
    |> Map.put(:updated_at, DateTime.utc_now())
  end
end
