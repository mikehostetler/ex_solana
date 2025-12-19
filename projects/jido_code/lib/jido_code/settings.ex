defmodule JidoCode.Settings do
  @moduledoc """
  Two-level JSON configuration system for JidoCode.

  Settings are stored in two locations:
  - **Global**: `~/.jido_code/settings.json` - applies to all projects
  - **Local**: `./jido_code/settings.json` - project-specific overrides

  ## Settings Schema

  ```json
  {
    "version": 1,
    "provider": "anthropic",
    "model": "claude-3-5-sonnet",
    "providers": ["anthropic", "openai", "openrouter"],
    "models": {
      "anthropic": ["claude-3-5-sonnet", "claude-3-opus"],
      "openai": ["gpt-4o", "gpt-4-turbo"]
    }
  }
  ```

  The `version` field enables future schema migrations when breaking changes
  are introduced. Current schema version: 1.

  All keys are optional. Local settings override global settings.

  ## Usage

      # Load merged settings (cached)
      JidoCode.Settings.load()
      #=> {:ok, %{"provider" => "anthropic", "model" => "gpt-4o"}}

      # Get individual values
      JidoCode.Settings.get("provider")
      #=> "anthropic"

      JidoCode.Settings.get("missing", "default")
      #=> "default"

      # Force reload from disk
      JidoCode.Settings.reload()
      #=> {:ok, %{...}}

      # Get paths
      JidoCode.Settings.global_path()
      #=> "/home/user/.jido_code/settings.json"

      JidoCode.Settings.local_path()
      #=> "/path/to/project/jido_code/settings.json"

      # Validate settings
      JidoCode.Settings.validate(%{"provider" => "anthropic"})
      #=> {:ok, %{"provider" => "anthropic"}}

      # Ensure directories exist
      JidoCode.Settings.ensure_global_dir()
      #=> :ok
  """

  require Logger

  alias Jido.AI.Model.Registry
  alias Jido.AI.Model.Registry.Adapter, as: RegistryAdapter
  alias JidoCode.Settings.Cache

  @global_dir_name ".jido_code"
  @local_dir_name "jido_code"
  @settings_file "settings.json"

  # Current schema version - increment when making breaking changes
  @schema_version 1

  # Valid top-level keys and their expected types
  @valid_keys %{
    "version" => :positive_integer,
    "provider" => :string,
    "model" => :string,
    "providers" => :list_of_strings,
    "models" => :map_of_string_lists,
    "theme" => :string
  }

  @typedoc """
  Settings map structure.

  All keys are optional:
  - `"version"` - Schema version number (positive integer, default: 1)
  - `"provider"` - Default LLM provider name (e.g., "anthropic", "openai")
  - `"model"` - Default model name (e.g., "claude-3-5-sonnet", "gpt-4o")
  - `"providers"` - List of available provider names
  - `"models"` - Map of provider name to list of model names
  """
  @type t :: %{
          optional(String.t()) =>
            pos_integer() | String.t() | [String.t()] | %{optional(String.t()) => [String.t()]}
        }

  # ============================================================================
  # Path Helpers
  # ============================================================================

  @doc """
  Returns the global settings directory path.

  ## Example

      iex> JidoCode.Settings.global_dir()
      "/home/user/.jido_code"
  """
  @spec global_dir() :: String.t()
  def global_dir do
    Path.join(System.user_home!(), @global_dir_name)
  end

  @doc """
  Returns the global settings file path.

  ## Example

      iex> JidoCode.Settings.global_path()
      "/home/user/.jido_code/settings.json"
  """
  @spec global_path() :: String.t()
  def global_path do
    Path.join(global_dir(), @settings_file)
  end

  @doc """
  Returns the local settings directory path (relative to current working directory).

  ## Example

      iex> JidoCode.Settings.local_dir()
      "/path/to/project/jido_code"
  """
  @spec local_dir() :: String.t()
  def local_dir do
    Path.join(File.cwd!(), @local_dir_name)
  end

  @doc """
  Returns the local settings file path.

  ## Example

      iex> JidoCode.Settings.local_path()
      "/path/to/project/jido_code/settings.json"
  """
  @spec local_path() :: String.t()
  def local_path do
    Path.join(local_dir(), @settings_file)
  end

  @doc """
  Returns the current settings schema version.

  This version number is incremented when breaking changes are made to the
  settings schema. It can be used for migration logic.

  ## Example

      iex> JidoCode.Settings.schema_version()
      1
  """
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  # ============================================================================
  # Schema Validation
  # ============================================================================

  @doc """
  Validates a settings map against the expected schema.

  All keys are optional. Returns `{:ok, settings}` if valid,
  or `{:error, reason}` if invalid.

  ## Valid Keys

  - `"version"` - Positive integer, schema version number
  - `"provider"` - String, the LLM provider name
  - `"model"` - String, the model identifier
  - `"providers"` - List of strings, allowed provider names
  - `"models"` - Map of provider name to list of model strings

  ## Examples

      iex> JidoCode.Settings.validate(%{"provider" => "anthropic"})
      {:ok, %{"provider" => "anthropic"}}

      iex> JidoCode.Settings.validate(%{"provider" => 123})
      {:error, "provider must be a string, got: 123"}

      iex> JidoCode.Settings.validate(%{"unknown_key" => "value"})
      {:error, "unknown key: unknown_key"}
  """
  @spec validate(term()) :: {:ok, t()} | {:error, String.t()}
  def validate(settings) when is_map(settings) do
    case validate_keys(settings) do
      :ok -> {:ok, settings}
      {:error, _} = error -> error
    end
  end

  def validate(other) do
    {:error, "settings must be a map, got: #{inspect(other)}"}
  end

  defp validate_keys(settings) do
    Enum.reduce_while(settings, :ok, fn {key, value}, :ok ->
      case validate_key(key, value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_key(key, value) do
    case Map.get(@valid_keys, key) do
      nil -> {:error, "unknown key: #{key}"}
      expected_type -> validate_type(key, value, expected_type)
    end
  end

  defp validate_type(_key, value, :positive_integer) when is_integer(value) and value > 0, do: :ok

  defp validate_type(key, value, :positive_integer) do
    {:error, "#{key} must be a positive integer, got: #{inspect(value)}"}
  end

  defp validate_type(_key, value, :string) when is_binary(value), do: :ok

  defp validate_type(key, value, :string) do
    {:error, "#{key} must be a string, got: #{inspect(value)}"}
  end

  defp validate_type(key, value, :list_of_strings) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      :ok
    else
      {:error, "#{key} must be a list of strings, got: #{inspect(value)}"}
    end
  end

  defp validate_type(key, value, :list_of_strings) do
    {:error, "#{key} must be a list of strings, got: #{inspect(value)}"}
  end

  defp validate_type(key, value, :map_of_string_lists) when is_map(value) do
    invalid =
      Enum.find(value, fn {k, v} ->
        not is_binary(k) or not is_list(v) or not Enum.all?(v, &is_binary/1)
      end)

    case invalid do
      nil -> :ok
      {k, v} -> {:error, "#{key}[#{inspect(k)}] must be a list of strings, got: #{inspect(v)}"}
    end
  end

  defp validate_type(key, value, :map_of_string_lists) do
    {:error, "#{key} must be a map of string lists, got: #{inspect(value)}"}
  end

  # ============================================================================
  # Directory Management
  # ============================================================================

  @doc """
  Ensures the global settings directory exists.

  Creates `~/.jido_code/` if it doesn't exist.

  ## Returns

  - `:ok` - Directory exists or was created
  - `{:error, reason}` - Failed to create directory

  ## Example

      iex> JidoCode.Settings.ensure_global_dir()
      :ok
  """
  @spec ensure_global_dir() :: :ok | {:error, term()}
  def ensure_global_dir do
    ensure_dir(global_dir())
  end

  @doc """
  Ensures the local settings directory exists.

  Creates `./jido_code/` if it doesn't exist.

  ## Returns

  - `:ok` - Directory exists or was created
  - `{:error, reason}` - Failed to create directory

  ## Example

      iex> JidoCode.Settings.ensure_local_dir()
      :ok
  """
  @spec ensure_local_dir() :: :ok | {:error, term()}
  def ensure_local_dir do
    ensure_dir(local_dir())
  end

  defp ensure_dir(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # File Reading
  # ============================================================================

  @doc """
  Reads and parses a settings JSON file.

  ## Returns

  - `{:ok, map}` - Successfully read and parsed
  - `{:error, :not_found}` - File does not exist
  - `{:error, {:invalid_json, reason}}` - File exists but contains invalid JSON

  ## Example

      iex> JidoCode.Settings.read_file("/path/to/settings.json")
      {:ok, %{"provider" => "anthropic"}}

      iex> JidoCode.Settings.read_file("/nonexistent/path.json")
      {:error, :not_found}
  """
  @spec read_file(String.t()) :: {:ok, t()} | {:error, :not_found | {:invalid_json, term()}}
  def read_file(path) do
    case File.read(path) do
      {:ok, content} -> parse_json(content)
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_json(content) do
    case Jason.decode(content) do
      {:ok, data} when is_map(data) ->
        {:ok, data}

      {:ok, data} ->
        {:error, {:invalid_json, "expected object, got: #{inspect(data)}"}}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  # ============================================================================
  # Settings Loading and Caching
  # ============================================================================

  @doc """
  Loads and merges settings from global and local files.

  Settings are loaded with the following precedence (highest to lowest):
  1. Local settings (`./jido_code/settings.json`)
  2. Global settings (`~/.jido_code/settings.json`)

  Results are cached in memory. Use `reload/0` to force a fresh load.

  ## Returns

  - `{:ok, merged_settings}` - Successfully loaded and merged settings

  ## Error Handling

  - Missing files are treated as empty (no error)
  - Malformed JSON logs a warning and is treated as empty
  - Always returns `{:ok, map}`, never fails

  ## Examples

      iex> JidoCode.Settings.load()
      {:ok, %{"provider" => "anthropic", "model" => "gpt-4o"}}
  """
  @spec load() :: {:ok, t()}
  def load do
    case Cache.get() do
      {:ok, settings} ->
        {:ok, settings}

      :miss ->
        settings = load_and_merge()
        Cache.put(settings)
        {:ok, settings}
    end
  end

  @doc """
  Clears the settings cache and reloads from disk.

  ## Returns

  - `{:ok, merged_settings}` - Freshly loaded settings

  ## Example

      iex> JidoCode.Settings.reload()
      {:ok, %{"provider" => "anthropic"}}
  """
  @spec reload() :: {:ok, t()}
  def reload do
    clear_cache()
    load()
  end

  @doc """
  Gets a single setting value by key.

  Loads settings from cache (or disk on first access).

  ## Returns

  - The value if present
  - `nil` if the key doesn't exist

  ## Examples

      iex> JidoCode.Settings.get("provider")
      "anthropic"

      iex> JidoCode.Settings.get("nonexistent")
      nil
  """
  @spec get(String.t()) :: term() | nil
  def get(key) when is_binary(key) do
    {:ok, settings} = load()
    Map.get(settings, key)
  end

  @doc """
  Gets a single setting value by key, with a default.

  Loads settings from cache (or disk on first access).

  ## Returns

  - The value if present
  - The default value if the key doesn't exist

  ## Examples

      iex> JidoCode.Settings.get("provider", "openai")
      "anthropic"

      iex> JidoCode.Settings.get("nonexistent", "default")
      "default"
  """
  @spec get(String.t(), term()) :: term()
  def get(key, default) when is_binary(key) do
    {:ok, settings} = load()
    Map.get(settings, key, default)
  end

  @doc """
  Clears the settings cache.

  The next call to `load/0` or `get/1` will read from disk.

  ## Example

      iex> JidoCode.Settings.clear_cache()
      :ok
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    Cache.clear()
  end

  # ============================================================================
  # Private: Loading and Merging
  # ============================================================================

  defp load_and_merge do
    global = load_settings_file(global_path(), "global")
    local = load_settings_file(local_path(), "local")

    deep_merge(global, local)
  end

  defp load_settings_file(path, label) do
    case read_file(path) do
      {:ok, settings} ->
        settings

      {:error, :not_found} ->
        %{}

      {:error, {:invalid_json, reason}} ->
        Logger.warning("Malformed JSON in #{label} settings file #{path}: #{reason}")
        %{}

      {:error, reason} ->
        Logger.warning("Failed to read #{label} settings file #{path}: #{inspect(reason)}")
        %{}
    end
  end

  defp deep_merge(base, overlay) do
    Map.merge(base, overlay, fn
      # Deep merge the "models" key (map of provider -> model list)
      "models", base_models, overlay_models when is_map(base_models) and is_map(overlay_models) ->
        Map.merge(base_models, overlay_models)

      # For all other keys, overlay wins
      _key, _base_value, overlay_value ->
        overlay_value
    end)
  end

  # ============================================================================
  # Settings Persistence
  # ============================================================================

  @doc """
  Saves settings to the specified scope file.

  Uses atomic write pattern (write to temp file, then rename) to prevent
  corruption. Invalidates cache after successful save.

  ## Parameters

  - `scope` - `:global` or `:local`
  - `settings` - Map of settings to save

  ## Returns

  - `:ok` - Settings saved successfully
  - `{:error, reason}` - Failed to save

  ## Examples

      iex> JidoCode.Settings.save(:local, %{"provider" => "anthropic"})
      :ok

      iex> JidoCode.Settings.save(:global, %{"model" => "gpt-4o"})
      :ok
  """
  @spec save(atom(), t()) :: :ok | {:error, term()}
  def save(scope, settings) when scope in [:global, :local] and is_map(settings) do
    case validate(settings) do
      {:ok, _} ->
        path = scope_to_path(scope)
        dir = Path.dirname(path)

        with :ok <- ensure_dir(dir),
             :ok <- write_atomic(path, settings) do
          clear_cache()
          :ok
        end

      {:error, _} = error ->
        error
    end
  end

  def save(scope, _settings) when scope not in [:global, :local] do
    {:error, "scope must be :global or :local, got: #{inspect(scope)}"}
  end

  def save(_scope, settings) when not is_map(settings) do
    {:error, "settings must be a map, got: #{inspect(settings)}"}
  end

  @doc """
  Updates a single setting key in the specified scope.

  Reads current settings for the scope, merges the new key/value,
  and saves. Invalidates cache after successful save.

  ## Parameters

  - `scope` - `:global` or `:local`
  - `key` - Setting key (string)
  - `value` - Setting value

  ## Returns

  - `:ok` - Setting updated successfully
  - `{:error, reason}` - Failed to update

  ## Examples

      iex> JidoCode.Settings.set(:local, "provider", "openai")
      :ok

      iex> JidoCode.Settings.set(:global, "model", "claude-3-opus")
      :ok
  """
  @spec set(atom(), String.t(), term()) :: :ok | {:error, term()}
  def set(scope, key, value) when scope in [:global, :local] and is_binary(key) do
    current = read_scope_settings(scope)
    updated = Map.put(current, key, value)
    save(scope, updated)
  end

  @doc """
  Adds a provider to the providers list in the specified scope.

  If the provider already exists, it won't be duplicated.

  ## Parameters

  - `scope` - `:global` or `:local`
  - `provider` - Provider name (string)

  ## Returns

  - `:ok` - Provider added successfully
  - `{:error, reason}` - Failed to add

  ## Examples

      iex> JidoCode.Settings.add_provider(:global, "openrouter")
      :ok
  """
  @spec add_provider(atom(), String.t()) :: :ok | {:error, term()}
  def add_provider(scope, provider) when scope in [:global, :local] and is_binary(provider) do
    current = read_scope_settings(scope)
    providers = Map.get(current, "providers", [])

    if provider in providers do
      :ok
    else
      updated = Map.put(current, "providers", providers ++ [provider])
      save(scope, updated)
    end
  end

  @doc """
  Adds a model to a provider's model list in the specified scope.

  If the model already exists for the provider, it won't be duplicated.

  ## Parameters

  - `scope` - `:global` or `:local`
  - `provider` - Provider name (string)
  - `model` - Model name (string)

  ## Returns

  - `:ok` - Model added successfully
  - `{:error, reason}` - Failed to add

  ## Examples

      iex> JidoCode.Settings.add_model(:local, "anthropic", "claude-3-5-sonnet")
      :ok
  """
  @spec add_model(atom(), String.t(), String.t()) :: :ok | {:error, term()}
  def add_model(scope, provider, model)
      when scope in [:global, :local] and is_binary(provider) and is_binary(model) do
    current = read_scope_settings(scope)
    models = Map.get(current, "models", %{})
    provider_models = Map.get(models, provider, [])

    if model in provider_models do
      :ok
    else
      updated_provider_models = provider_models ++ [model]
      updated_models = Map.put(models, provider, updated_provider_models)
      updated = Map.put(current, "models", updated_models)
      save(scope, updated)
    end
  end

  # ============================================================================
  # Private: Persistence Helpers
  # ============================================================================

  defp scope_to_path(:global), do: global_path()
  defp scope_to_path(:local), do: local_path()

  defp read_scope_settings(scope) do
    path = scope_to_path(scope)

    case read_file(path) do
      {:ok, settings} -> settings
      {:error, _} -> %{}
    end
  end

  defp write_atomic(path, settings) do
    temp_path = path <> ".tmp"
    json = Jason.encode!(settings, pretty: true)
    expected_size = byte_size(json)

    try do
      File.write!(temp_path, json)
      File.rename!(temp_path, path)

      # Set file permissions to owner read/write only (0o600)
      File.chmod(path, 0o600)

      # Verify the final file exists and has expected size
      case File.stat(path) do
        {:ok, %{size: ^expected_size}} ->
          :ok

        {:ok, %{size: actual_size}} ->
          {:error,
           "File size mismatch after write: expected #{expected_size}, got #{actual_size}"}

        {:error, reason} ->
          {:error, "Failed to verify written file: #{inspect(reason)}"}
      end
    rescue
      e in File.Error ->
        # Clean up temp file if it exists
        File.rm(temp_path)
        {:error, Exception.message(e)}
    end
  end

  # ============================================================================
  # Provider and Model Lists
  # ============================================================================

  @doc """
  Returns the list of available providers.

  First checks settings for a user-configured "providers" list.
  If not configured or empty, falls back to `Jido.AI.Provider.providers/0`.

  ## Returns

  List of provider name strings.

  ## Examples

      # When settings has providers configured
      iex> JidoCode.Settings.get_providers()
      ["anthropic", "openai", "openrouter"]

      # Falls back to JidoAI discovery when not configured
      iex> JidoCode.Settings.get_providers()
      ["anthropic", "azure", "openai", ...]
  """
  @spec get_providers() :: [String.t()]
  def get_providers do
    case get("providers") do
      providers when is_list(providers) and providers != [] ->
        providers

      _ ->
        get_jido_providers()
    end
  end

  @doc """
  Returns the list of available models for a provider.

  First checks settings for a user-configured "models[provider]" list.
  If not configured or empty, falls back to JidoAI discovery.

  ## Parameters

  - `provider` - Provider name (string)

  ## Returns

  List of model name strings. Returns empty list for unknown providers.

  ## Examples

      # When settings has models configured
      iex> JidoCode.Settings.get_models("anthropic")
      ["claude-3-5-sonnet", "claude-3-opus"]

      # Falls back to JidoAI discovery when not configured
      iex> JidoCode.Settings.get_models("openai")
      ["gpt-4o", "gpt-4-turbo", ...]
  """
  @spec get_models(String.t()) :: [String.t()]
  def get_models(provider) when is_binary(provider) do
    models_map = get("models") || %{}

    case Map.get(models_map, provider) do
      models when is_list(models) and models != [] ->
        models

      _ ->
        get_jido_models(provider)
    end
  end

  # ============================================================================
  # Private: JidoAI Integration (ReqLLM APIs)
  # ============================================================================

  defp get_jido_providers do
    # Use ReqLLM registry via RegistryAdapter
    # This returns all 57+ ReqLLM providers without legacy fallback warnings
    case RegistryAdapter.list_providers() do
      {:ok, providers} when is_list(providers) ->
        Enum.map(providers, &Atom.to_string/1)

      _ ->
        []
    end
  end

  defp get_jido_models(provider) do
    # Use String.to_existing_atom/1 to avoid atom exhaustion
    # If the provider atom doesn't exist, we won't find models anyway
    provider_atom =
      try do
        String.to_existing_atom(provider)
      rescue
        ArgumentError -> nil
      end

    if provider_atom do
      # Use ReqLLM registry via Registry
      # This returns ReqLLM.Model structs with full metadata
      # Wrap in try/rescue to handle ETS table not existing
      try do
        case Registry.list_models(provider_atom) do
          {:ok, models} when is_list(models) ->
            extract_model_names(models)

          _ ->
            []
        end
      rescue
        ArgumentError ->
          # ETS table doesn't exist - registry not initialized
          []
      end
    else
      []
    end
  end

  defp extract_model_names(models) do
    models
    |> Enum.map(fn model ->
      # ReqLLM.Model structs have a :model field with the model name
      case model do
        %{model: name} when is_binary(name) -> name
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
