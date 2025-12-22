defmodule JidoCode.Session.Persistence.Serialization do
  @moduledoc """
  Serialization and deserialization logic for session persistence.

  This module handles converting between runtime data structures (State, Session)
  and persisted JSON-compatible maps. It includes:

  - Building persisted session maps from State
  - Serializing messages, todos, and config
  - Deserializing persisted data back to runtime structures
  - Date/time formatting and parsing
  - Role and status enum conversions

  ## Key Functions

  - `build_persisted_session/1` - Convert State to persisted map
  - `deserialize_session/1` - Convert persisted map to runtime data
  - `normalize_keys_to_strings/1` - Prepare data for JSON encoding
  """

  require Logger

  alias JidoCode.Session.Persistence.Schema

  # ============================================================================
  # Building Persisted Sessions
  # ============================================================================

  @doc """
  Builds a persisted session map from a State process state.

  Takes the current state from Session.State and converts it to a map
  suitable for JSON serialization and disk persistence.

  ## Parameters

  - `state` - The State process state map (from Session.State GenServer)

  ## Returns

  A persisted session map with all data serialized to JSON-compatible types.
  """
  @spec build_persisted_session(map()) :: Schema.persisted_session()
  def build_persisted_session(state) do
    session = state.session

    %{
      version: Schema.schema_version(),
      id: session.id,
      name: session.name,
      project_path: session.project_path,
      config: serialize_config(session.config),
      created_at: format_datetime(session.created_at),
      updated_at: format_datetime(session.updated_at),
      closed_at: DateTime.to_iso8601(DateTime.utc_now()),
      conversation: Enum.map(state.messages, &serialize_message/1),
      todos: Enum.map(state.todos, &serialize_todo/1)
    }
  end

  # ============================================================================
  # Serialization (Runtime -> Persisted)
  # ============================================================================

  # Serialize a message to the persisted format
  defp serialize_message(msg) do
    %{
      id: msg.id,
      role: to_string(msg.role),
      content: msg.content,
      timestamp: format_datetime(msg.timestamp)
    }
  end

  # Serialize a todo to the persisted format
  defp serialize_todo(todo) do
    %{
      content: todo.content,
      status: to_string(todo.status),
      # Fall back to content if active_form not present
      active_form: Map.get(todo, :active_form) || todo.content
    }
  end

  # Serialize config, converting atoms to strings for JSON
  defp serialize_config(config) when is_struct(config) do
    config
    |> Map.from_struct()
    |> serialize_config()
  end

  defp serialize_config(config) when is_map(config) do
    Map.new(config, fn
      {key, value} when is_atom(value) -> {to_string(key), to_string(value)}
      {key, value} when is_map(value) -> {to_string(key), serialize_config(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp serialize_config(other), do: other

  # Format datetime to ISO 8601 string, handling nil
  defp format_datetime(nil), do: DateTime.to_iso8601(DateTime.utc_now())
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  @doc """
  Recursively converts all atom keys to string keys.

  This ensures consistent JSON encoding/decoding and deterministic output.
  Required for HMAC signature generation over JSON.
  """
  @spec normalize_keys_to_strings(term()) :: term()
  def normalize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), normalize_keys_to_strings(value)}

      {key, value} ->
        {key, normalize_keys_to_strings(value)}
    end)
  end

  def normalize_keys_to_strings(list) when is_list(list) do
    Enum.map(list, &normalize_keys_to_strings/1)
  end

  def normalize_keys_to_strings(value), do: value

  # ============================================================================
  # Deserialization (Persisted -> Runtime)
  # ============================================================================

  @doc """
  Deserializes a persisted session map back to runtime data structures.

  Validates schema version, converts string keys to atoms, parses timestamps,
  and deserializes messages and todos.

  ## Parameters

  - `data` - Persisted session map (from JSON file)

  ## Returns

  - `{:ok, session_data}` - Successfully deserialized session with runtime types
  - `{:error, reason}` - Validation or parsing failed
  """
  @spec deserialize_session(map()) :: {:ok, map()} | {:error, term()}
  def deserialize_session(data) when is_map(data) do
    with {:ok, validated} <- Schema.validate_session(data),
         {:ok, _version} <- check_schema_version(validated.version),
         {:ok, messages} <- deserialize_messages(validated.conversation),
         {:ok, todos} <- deserialize_todos(validated.todos),
         {:ok, created_at} <- parse_datetime_required(validated.created_at),
         {:ok, updated_at} <- parse_datetime_required(validated.updated_at) do
      {:ok,
       %{
         id: validated.id,
         name: validated.name,
         project_path: validated.project_path,
         config: deserialize_config(validated.config),
         created_at: created_at,
         updated_at: updated_at,
         conversation: messages,
         todos: todos
       }}
    end
  end

  def deserialize_session(_), do: {:error, :not_a_map}

  # Check schema version compatibility
  defp check_schema_version(version) when is_integer(version) do
    current = Schema.schema_version()

    cond do
      version > current ->
        Logger.warning("Unsupported schema version: #{version} (current: #{current})")
        {:error, :unsupported_version}

      version < 1 ->
        Logger.warning("Invalid schema version: #{version}")
        {:error, :invalid_version}

      true ->
        {:ok, version}
    end
  end

  defp check_schema_version(version) do
    Logger.warning("Invalid schema version type: #{inspect(version)}")
    {:error, :invalid_version}
  end

  # Generic helper for deserializing lists with fail-fast behavior
  # Reduces code duplication between deserialize_messages and deserialize_todos
  defp deserialize_list(items, deserializer_fn, error_key) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case deserializer_fn.(item) do
        {:ok, deserialized} -> {:cont, {:ok, [deserialized | acc]}}
        {:error, reason} -> {:halt, {:error, {error_key, reason}}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp deserialize_list(_, _, error_key), do: {:error, :"#{error_key}s_not_list"}

  # Deserialize list of messages
  defp deserialize_messages(messages) do
    deserialize_list(messages, &deserialize_message/1, :invalid_message)
  end

  # Deserialize single message
  defp deserialize_message(msg) do
    with {:ok, validated} <- Schema.validate_message(msg),
         {:ok, timestamp} <- parse_datetime_required(validated.timestamp),
         {:ok, role} <- parse_role(validated.role) do
      {:ok,
       %{
         id: validated.id,
         role: role,
         content: validated.content,
         timestamp: timestamp
       }}
    end
  end

  # Deserialize list of todos
  defp deserialize_todos(todos) do
    deserialize_list(todos, &deserialize_todo/1, :invalid_todo)
  end

  # Deserialize single todo
  defp deserialize_todo(todo) do
    with {:ok, validated} <- Schema.validate_todo(todo),
         {:ok, status} <- parse_status(validated.status) do
      {:ok,
       %{
         content: validated.content,
         status: status,
         active_form: validated.active_form
       }}
    end
  end

  # Parse ISO 8601 timestamp (required field)
  defp parse_datetime_required(nil), do: {:error, :missing_timestamp}

  defp parse_datetime_required(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      {:error, reason} ->
        # Log detailed error for debugging, return sanitized error
        Logger.debug(
          "Failed to parse timestamp: #{inspect(iso_string)}, reason: #{inspect(reason)}"
        )

        {:error, :invalid_timestamp}
    end
  end

  defp parse_datetime_required(other) do
    Logger.debug("Invalid timestamp type: #{inspect(other)}")
    {:error, :invalid_timestamp}
  end

  # Parse message role string to atom
  defp parse_role("user"), do: {:ok, :user}
  defp parse_role("assistant"), do: {:ok, :assistant}
  defp parse_role("system"), do: {:ok, :system}
  defp parse_role("tool"), do: {:ok, :tool}

  defp parse_role(other) do
    Logger.debug("Invalid role value: #{inspect(other)}")
    {:error, :invalid_role}
  end

  # Parse todo status string to atom
  defp parse_status("pending"), do: {:ok, :pending}
  defp parse_status("in_progress"), do: {:ok, :in_progress}
  defp parse_status("completed"), do: {:ok, :completed}

  defp parse_status(other) do
    Logger.debug("Invalid status value: #{inspect(other)}")
    {:error, :invalid_status}
  end

  # Deserialize config map (string keys to appropriate types)
  defp deserialize_config(config) when is_map(config) do
    # Config uses string keys - just ensure expected structure with defaults
    %{
      "provider" => Map.get(config, "provider", "anthropic"),
      "model" => Map.get(config, "model", "claude-3-5-sonnet-20241022"),
      "temperature" => Map.get(config, "temperature", 0.7),
      "max_tokens" => Map.get(config, "max_tokens", 4096)
    }
  end

  defp deserialize_config(_), do: %{}
end
