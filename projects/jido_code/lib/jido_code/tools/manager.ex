defmodule JidoCode.Tools.Manager do
  @moduledoc """
  GenServer wrapping the Luerl Lua runtime for sandboxed tool execution.

  The Manager maintains a Lua state with dangerous functions removed to prevent:
  - Shell command execution (os.execute, io.popen)
  - Process termination (os.exit)
  - Arbitrary file loading (loadfile, dofile, require)
  - Module system access (package)

  ## Deprecation Notice

  **The global Tools.Manager is deprecated.** For new code, use session-scoped
  managers via `JidoCode.Session.Manager` instead.

  All API functions now accept an optional `:session_id` option. When provided,
  the call is delegated to `Session.Manager` for that session. When omitted,
  the global manager is used with a deprecation warning.

  ### Migration Path

  **Before (deprecated):**

      {:ok, path} = Tools.Manager.project_root()
      {:ok, content} = Tools.Manager.read_file("src/file.ex")

  **After (recommended):**

      {:ok, path} = Tools.Manager.project_root(session_id: session.id)
      {:ok, content} = Tools.Manager.read_file("src/file.ex", session_id: session.id)

  Or use `Session.Manager` directly:

      {:ok, path} = Session.Manager.project_root(session.id)
      {:ok, content} = Session.Manager.read_file(session.id, "src/file.ex")

  ## Usage

  The Manager is started as part of the application supervision tree with
  a project root path that defines the boundary for file operations.

      # Via supervision tree (automatic)
      JidoCode.Tools.Manager.execute("my_tool", %{"arg" => "value"})

      # Get project root (session-aware)
      {:ok, path} = JidoCode.Tools.Manager.project_root(session_id: "abc123")

      # Get project root (global, deprecated)
      {:ok, path} = JidoCode.Tools.Manager.project_root()

  ## Sandboxed File Operations

  All file and shell operations should go through the Manager API to ensure
  they are executed within the Lua sandbox with proper security validation:

      # Read a file through the sandbox (session-aware)
      {:ok, content} = JidoCode.Tools.Manager.read_file("src/main.ex", session_id: id)

      # Write a file through the sandbox
      :ok = JidoCode.Tools.Manager.write_file("output.txt", "Hello", session_id: id)

      # Execute a shell command through the sandbox
      {:ok, result} = JidoCode.Tools.Manager.shell("mix", ["test"])

  ## Sandbox Restrictions

  The following Lua functions are removed from the sandbox:

  - `os.execute` - Shell command execution
  - `os.exit` - Process termination
  - `io.popen` - Shell command with pipe
  - `loadfile` - Load Lua code from file
  - `dofile` - Execute Lua file
  - `package` - Module loading system
  - `require` - Module require

  ## Tool Execution

  Tools are executed by loading their Lua script and calling it with the
  provided arguments. The script is expected to return a result that will
  be converted to Elixir terms.
  """

  use GenServer

  alias JidoCode.ErrorFormatter
  alias JidoCode.Session
  alias JidoCode.Tools.{Bridge, Security}

  require Logger

  @type state :: %{
          lua_state: :luerl.luerl_state(),
          project_root: String.t()
        }

  @default_timeout 30_000

  # Dangerous functions to remove from sandbox
  @restricted_functions [
    [:os, :execute],
    [:os, :exit],
    [:io, :popen],
    [:loadfile],
    [:dofile],
    [:package],
    [:require]
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the Manager GenServer.

  ## Options

  - `:project_root` - Root directory for file operations (default: cwd)
  - `:name` - GenServer name (default: `__MODULE__`)

  ## Examples

      {:ok, pid} = Manager.start_link(project_root: "/my/project")
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a Lua script in the sandbox.

  The script is executed with the provided arguments available as a global
  `args` table. The script should return a value that becomes the result.

  ## Parameters

  - `script` - Lua code to execute
  - `args` - Map of arguments (available as `args` table in Lua)
  - `timeout` - Execution timeout in milliseconds (default: 30000)

  ## Returns

  - `{:ok, result}` - Execution succeeded with result
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, result} = Manager.execute("return args.x + args.y", %{"x" => 1, "y" => 2})
      # => {:ok, 3.0}

      {:error, reason} = Manager.execute("os.execute('rm -rf /')", %{})
      # => {:error, "attempt to call a nil value"}
  """
  @spec execute(String.t(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}
  def execute(script, args \\ %{}, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:execute, script, args}, timeout + 1000)
  end

  @doc """
  Gets the project root path.

  ## Options

  - `:session_id` - When provided, delegates to `Session.Manager.project_root/1`
    for the specified session. When omitted, uses the global manager (deprecated).

  ## Returns

  - `{:ok, path}` - The project root path
  - `{:error, :not_found}` - Session manager not found (when using session_id)

  ## Examples

      # Session-aware (preferred)
      {:ok, path} = Manager.project_root(session_id: "abc123")

      # Global (deprecated)
      {:ok, path} = Manager.project_root()
  """
  @spec project_root(keyword()) :: {:ok, String.t()} | {:error, :not_found}
  def project_root(opts \\ []) do
    case Keyword.get(opts, :session_id) do
      nil ->
        warn_global_usage(:project_root)
        GenServer.call(__MODULE__, :project_root)

      session_id ->
        Session.Manager.project_root(session_id)
    end
  end

  @doc """
  Validates a path is within the project boundary.

  This delegates to `JidoCode.Tools.Security.validate_path/3` using the
  Manager's configured project root.

  ## Parameters

  - `path` - The path to validate (relative or absolute)
  - `opts` - Options:
    - `:session_id` - When provided, delegates to `Session.Manager.validate_path/2`
    - Other options are passed to Security.validate_path/3

  ## Returns

  - `{:ok, resolved_path}` - Path is valid and resolved
  - `{:error, reason}` - Path violates security boundary
  - `{:error, :not_found}` - Session manager not found (when using session_id)

  ## Examples

      # Session-aware (preferred)
      {:ok, safe_path} = Manager.validate_path("src/file.ex", session_id: "abc123")

      # Global (deprecated)
      {:ok, safe_path} = Manager.validate_path("src/file.ex")
      {:error, :path_escapes_boundary} = Manager.validate_path("../../../etc/passwd")
  """
  @spec validate_path(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def validate_path(path, opts \\ []) do
    {session_id, security_opts} = Keyword.pop(opts, :session_id)

    case session_id do
      nil ->
        warn_global_usage(:validate_path)
        GenServer.call(__MODULE__, {:validate_path, path, security_opts})

      session_id ->
        Session.Manager.validate_path(session_id, path)
    end
  end

  @doc """
  Checks if a function is restricted in the sandbox.

  ## Parameters

  - `path` - Function path as list of atoms (e.g., `[:os, :execute]`)

  ## Returns

  - `true` if the function is restricted
  - `false` if the function is allowed
  """
  @spec restricted?(list(atom())) :: boolean()
  def restricted?(path) when is_list(path) do
    path in @restricted_functions
  end

  # ============================================================================
  # Sandboxed File/Shell Operations API
  # ============================================================================

  @doc """
  Reads a file through the Lua sandbox.

  Executes `jido.read_file(path, opts)` in the Lua sandbox which provides:
  - TOCTOU-safe reading via `Security.atomic_read/3`
  - Line-numbered output formatting (cat -n style)
  - Offset/limit pagination for large files
  - Binary file detection and rejection
  - Long line truncation at 2000 characters

  ## Parameters

  - `path` - Path to the file (relative or absolute)
  - `opts` - Options:
    - `:session_id` - When provided, delegates to `Session.Manager.read_file/3`
    - `:offset` - Line number to start from (1-indexed, default: 1)
    - `:limit` - Maximum lines to read (default: 2000)

  ## Returns

  - `{:ok, content}` - Line-numbered file contents
  - `{:error, reason}` - Error message
  - `{:error, :not_found}` - Session manager not found (when using session_id)

  ## Examples

      # Session-aware (preferred)
      {:ok, content} = Manager.read_file("src/file.ex", session_id: "abc123")
      {:ok, content} = Manager.read_file("src/file.ex", session_id: "abc123", offset: 10, limit: 50)

      # Global (deprecated)
      {:ok, content} = Manager.read_file("src/file.ex")
  """
  @spec read_file(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t() | :not_found}
  def read_file(path, opts \\ []) do
    {session_id, read_opts} = Keyword.pop(opts, :session_id)

    case session_id do
      nil ->
        warn_global_usage(:read_file)
        GenServer.call(__MODULE__, {:sandbox_read_file, path, read_opts})

      session_id ->
        Session.Manager.read_file(session_id, path, read_opts)
    end
  end

  @doc """
  Writes content to a file through the Lua sandbox.

  The path is validated against the project boundary before writing.

  ## Parameters

  - `path` - Path to the file (relative or absolute)
  - `content` - Content to write
  - `opts` - Options:
    - `:session_id` - When provided, delegates to `Session.Manager.write_file/3`

  ## Returns

  - `:ok` - File written successfully
  - `{:error, reason}` - Error message
  - `{:error, :not_found}` - Session manager not found (when using session_id)

  ## Examples

      # Session-aware (preferred)
      :ok = Manager.write_file("output.txt", "Hello", session_id: "abc123")

      # Global (deprecated)
      :ok = Manager.write_file("output.txt", "Hello")
  """
  @spec write_file(String.t(), String.t(), keyword()) :: :ok | {:error, String.t() | :not_found}
  def write_file(path, content, opts \\ []) do
    case Keyword.get(opts, :session_id) do
      nil ->
        warn_global_usage(:write_file)
        GenServer.call(__MODULE__, {:sandbox_write_file, path, content})

      session_id ->
        Session.Manager.write_file(session_id, path, content)
    end
  end

  @doc """
  Lists directory contents through the Lua sandbox.

  The path is validated against the project boundary before listing.

  ## Parameters

  - `path` - Path to the directory (relative or absolute)
  - `opts` - Options:
    - `:session_id` - When provided, delegates to `Session.Manager.list_dir/2`

  ## Returns

  - `{:ok, entries}` - List of directory entry names
  - `{:error, reason}` - Error message
  - `{:error, :not_found}` - Session manager not found (when using session_id)

  ## Examples

      # Session-aware (preferred)
      {:ok, entries} = Manager.list_dir("src", session_id: "abc123")

      # Global (deprecated)
      {:ok, entries} = Manager.list_dir("src")
  """
  @spec list_dir(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, String.t() | :not_found}
  def list_dir(path, opts \\ []) do
    case Keyword.get(opts, :session_id) do
      nil ->
        warn_global_usage(:list_dir)
        GenServer.call(__MODULE__, {:sandbox_list_dir, path})

      session_id ->
        Session.Manager.list_dir(session_id, path)
    end
  end

  @doc """
  Gets file stats through the Lua sandbox.

  The path is validated against the project boundary before stat.

  ## Parameters

  - `path` - Path to the file (relative or absolute)

  ## Returns

  - `{:ok, stat}` - File.Stat struct
  - `{:error, reason}` - Error message
  """
  @spec file_stat(String.t()) :: {:ok, File.Stat.t()} | {:error, String.t()}
  def file_stat(path) do
    GenServer.call(__MODULE__, {:sandbox_file_stat, path})
  end

  @doc """
  Checks if a path exists through the Lua sandbox.

  The path is validated against the project boundary.

  ## Parameters

  - `path` - Path to check (relative or absolute)

  ## Returns

  - `{:ok, exists}` - Boolean indicating existence
  - `{:error, reason}` - Error message (security violation)
  """
  @spec file_exists?(String.t()) :: {:ok, boolean()} | {:error, String.t()}
  def file_exists?(path) do
    GenServer.call(__MODULE__, {:sandbox_file_exists, path})
  end

  @doc """
  Checks if a path is a regular file through the Lua sandbox.

  The path is validated against the project boundary.

  ## Parameters

  - `path` - Path to check (relative or absolute)

  ## Returns

  - `{:ok, is_file}` - Boolean indicating if path is a regular file
  - `{:error, reason}` - Error message (security violation)
  """
  @spec file?(String.t()) :: {:ok, boolean()} | {:error, String.t()}
  def file?(path) do
    GenServer.call(__MODULE__, {:sandbox_is_file, path})
  end

  @doc """
  Checks if a path is a directory through the Lua sandbox.

  The path is validated against the project boundary.

  ## Parameters

  - `path` - Path to check (relative or absolute)

  ## Returns

  - `{:ok, is_dir}` - Boolean indicating if path is a directory
  - `{:error, reason}` - Error message (security violation)
  """
  @spec directory?(String.t()) :: {:ok, boolean()} | {:error, String.t()}
  def directory?(path) do
    GenServer.call(__MODULE__, {:sandbox_is_dir, path})
  end

  @doc """
  Deletes a file through the Lua sandbox.

  The path is validated against the project boundary before deletion.

  ## Parameters

  - `path` - Path to the file (relative or absolute)

  ## Returns

  - `:ok` - File deleted successfully
  - `{:error, reason}` - Error message
  """
  @spec delete_file(String.t()) :: :ok | {:error, String.t()}
  def delete_file(path) do
    GenServer.call(__MODULE__, {:sandbox_delete_file, path})
  end

  @doc """
  Creates a directory (and parents) through the Lua sandbox.

  The path is validated against the project boundary before creation.

  ## Parameters

  - `path` - Path to the directory (relative or absolute)

  ## Returns

  - `:ok` - Directory created successfully
  - `{:error, reason}` - Error message
  """
  @spec mkdir_p(String.t()) :: :ok | {:error, String.t()}
  def mkdir_p(path) do
    GenServer.call(__MODULE__, {:sandbox_mkdir_p, path})
  end

  @doc """
  Executes a shell command through the Lua sandbox.

  The command is validated against the allowlist before execution.

  ## Parameters

  - `command` - Command to execute (must be in allowlist)
  - `args` - List of command arguments

  ## Returns

  - `{:ok, result}` - Map with exit_code, stdout, stderr
  - `{:error, reason}` - Error message
  """
  @spec shell(String.t(), [String.t()]) :: {:ok, map()} | {:error, String.t()}
  def shell(command, args) do
    GenServer.call(__MODULE__, {:sandbox_shell, command, args}, @default_timeout + 5_000)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    Logger.info("Starting Tools.Manager with project_root: #{project_root}")

    # Initialize Lua state, apply sandbox restrictions, and register bridge functions
    lua_state =
      :luerl.init()
      |> apply_sandbox_restrictions()
      |> Bridge.register(project_root)

    {:ok, %{lua_state: lua_state, project_root: project_root}}
  end

  @impl true
  def handle_call({:execute, script, args}, _from, state) do
    result = execute_script(script, args, state.lua_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:project_root, _from, state) do
    {:reply, {:ok, state.project_root}, state}
  end

  @impl true
  def handle_call({:validate_path, path, opts}, _from, state) do
    result = Security.validate_path(path, state.project_root, opts)
    {:reply, result, state}
  end

  # Sandbox file operations - call Bridge functions through Lua state

  # Backward compatibility: 2-tuple format without options
  @impl true
  def handle_call({:sandbox_read_file, path}, _from, state) do
    handle_call({:sandbox_read_file, path, []}, {:sandbox_read_file, path}, state)
  end

  # New format with options - passes options to Lua bridge
  @impl true
  def handle_call({:sandbox_read_file, path, opts}, _from, state) do
    # Build Lua options table from keyword list
    lua_opts = build_lua_read_opts(opts)
    args = if lua_opts == [], do: [path], else: [path, lua_opts]
    result = call_bridge_function(state.lua_state, "read_file", args)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sandbox_write_file, path, content}, _from, state) do
    result = call_bridge_function(state.lua_state, "write_file", [path, content])

    case result do
      {:ok, true} -> {:reply, :ok, state}
      {:ok, _} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:sandbox_list_dir, path}, _from, state) do
    result = call_bridge_function(state.lua_state, "list_dir", [path])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sandbox_file_stat, path}, _from, state) do
    case call_bridge_function(state.lua_state, "file_stat", [path]) do
      {:ok, stat_map} when is_map(stat_map) ->
        # Convert the map to a File.Stat-like struct with mtime
        stat = %File.Stat{
          size: Map.get(stat_map, "size", 0),
          type: String.to_atom(Map.get(stat_map, "type", "regular")),
          access: String.to_atom(Map.get(stat_map, "access", "read")),
          mtime: parse_mtime(Map.get(stat_map, "mtime"))
        }

        {:reply, {:ok, stat}, state}

      {:ok, other} ->
        {:reply, {:ok, other}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:sandbox_file_exists, path}, _from, state) do
    result = call_bridge_function(state.lua_state, "file_exists", [path])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sandbox_is_file, path}, _from, state) do
    result = call_bridge_function(state.lua_state, "is_file", [path])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sandbox_is_dir, path}, _from, state) do
    result = call_bridge_function(state.lua_state, "is_dir", [path])
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sandbox_delete_file, path}, _from, state) do
    result = call_bridge_function(state.lua_state, "delete_file", [path])

    case result do
      {:ok, true} -> {:reply, :ok, state}
      {:ok, _} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:sandbox_mkdir_p, path}, _from, state) do
    result = call_bridge_function(state.lua_state, "mkdir_p", [path])

    case result do
      {:ok, true} -> {:reply, :ok, state}
      {:ok, _} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:sandbox_shell, command, args}, _from, state) do
    # Convert args to Lua array format
    lua_args = Enum.with_index(args, 1) |> Enum.map(fn {arg, idx} -> {idx, arg} end)
    result = call_bridge_function(state.lua_state, "shell", [command, lua_args])
    {:reply, result, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Build Lua table format for read_file options
  # Returns a list of tuples that luerl will encode as a table
  defp build_lua_read_opts([]), do: []

  defp build_lua_read_opts(opts) do
    opts
    |> Keyword.take([:offset, :limit])
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  # Parse ISO 8601 datetime string to erlang datetime tuple
  defp parse_mtime(nil), do: {{1970, 1, 1}, {0, 0, 0}}
  defp parse_mtime(""), do: {{1970, 1, 1}, {0, 0, 0}}

  defp parse_mtime(mtime_str) when is_binary(mtime_str) do
    case Regex.run(~r/(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/, mtime_str) do
      [_, year, month, day, hour, minute, second] ->
        {{String.to_integer(year), String.to_integer(month), String.to_integer(day)},
         {String.to_integer(hour), String.to_integer(minute), String.to_integer(second)}}

      _ ->
        {{1970, 1, 1}, {0, 0, 0}}
    end
  end

  defp parse_mtime(_), do: {{1970, 1, 1}, {0, 0, 0}}

  defp call_bridge_function(lua_state, func_name, args) do
    # Build Lua call: jido.func_name(args...)
    args_str = Enum.map_join(args, ", ", &lua_encode_arg/1)

    script = "return jido.#{func_name}(#{args_str})"

    case :luerl.do(script, lua_state) do
      {:ok, [nil, error_msg], _state} when is_binary(error_msg) ->
        {:error, error_msg}

      {:ok, [result], _state} ->
        {:ok, decode_lua_result(result, lua_state)}

      {:ok, [], _state} ->
        {:ok, nil}

      {:error, reason, _state} ->
        {:error, ErrorFormatter.format(reason)}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp lua_encode_arg(arg) when is_binary(arg) do
    # Escape special characters in string
    escaped =
      arg
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"#{escaped}\""
  end

  defp lua_encode_arg(arg) when is_integer(arg), do: Integer.to_string(arg)
  defp lua_encode_arg(arg) when is_float(arg), do: Float.to_string(arg)
  defp lua_encode_arg(true), do: "true"
  defp lua_encode_arg(false), do: "false"
  defp lua_encode_arg(nil), do: "nil"

  defp lua_encode_arg(arg) when is_list(arg) do
    # Encode as Lua table
    items =
      Enum.map_join(arg, ", ", fn
        {k, v} when is_integer(k) -> "[#{k}] = #{lua_encode_arg(v)}"
        {k, v} -> "[\"#{k}\"] = #{lua_encode_arg(v)}"
      end)

    "{#{items}}"
  end

  defp decode_lua_result({:tref, _} = tref, lua_state) do
    decoded = :luerl.decode(tref, lua_state)
    decode_lua_table(decoded, lua_state)
  end

  defp decode_lua_result(list, lua_state) when is_list(list) do
    decode_lua_table(list, lua_state)
  end

  defp decode_lua_result(value, _lua_state), do: value

  defp apply_sandbox_restrictions(lua_state) do
    Enum.reduce(@restricted_functions, lua_state, fn path, state ->
      remove_function(state, path)
    end)
  end

  defp remove_function(lua_state, [key]) when is_atom(key) do
    # Remove top-level global
    key_str = Atom.to_string(key)
    {:ok, state} = :luerl.set_table_keys([key_str], nil, lua_state)
    state
  end

  defp remove_function(lua_state, path) when is_list(path) do
    # Remove nested function (e.g., [:os, :execute])
    path_strs = Enum.map(path, &Atom.to_string/1)
    {:ok, state} = :luerl.set_table_keys(path_strs, nil, lua_state)
    state
  end

  defp execute_script(script, args, lua_state) do
    # Set args as global table using luerl's encode
    {encoded_args, lua_state} = encode_args(args, lua_state)
    {:ok, lua_state} = :luerl.set_table_keys(["args"], encoded_args, lua_state)

    # Execute the script
    case :luerl.do(script, lua_state) do
      {:ok, results, new_state} ->
        # Decode results - luerl returns a list of return values
        result = decode_results(results, new_state)
        {:ok, result}

      {:error, reason, _state} ->
        {:error, ErrorFormatter.format(reason)}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp encode_args(args, lua_state) when map_size(args) == 0 do
    # Create empty Lua table
    :luerl.encode([], lua_state)
  end

  defp encode_args(args, lua_state) do
    # Convert to list of tuples for Lua table
    lua_table = Enum.map(args, fn {k, v} -> {to_string(k), encode_value(v)} end)
    :luerl.encode(lua_table, lua_state)
  end

  defp encode_value(v) when is_map(v) do
    Enum.map(v, fn {k, val} -> {to_string(k), encode_value(val)} end)
  end

  defp encode_value(v) when is_list(v) do
    Enum.with_index(v, 1) |> Enum.map(fn {val, idx} -> {idx, encode_value(val)} end)
  end

  defp encode_value(v) when is_binary(v), do: v
  defp encode_value(v) when is_number(v), do: v
  defp encode_value(v) when is_boolean(v), do: v
  defp encode_value(nil), do: nil
  defp encode_value(v) when is_atom(v), do: Atom.to_string(v)

  defp decode_results([], _state), do: nil
  defp decode_results([single], state), do: decode_value(single, state)
  defp decode_results(multiple, state), do: Enum.map(multiple, &decode_value(&1, state))

  defp decode_value(v, _state) when is_binary(v), do: v
  defp decode_value(v, _state) when is_number(v), do: v
  defp decode_value(v, _state) when is_boolean(v), do: v
  defp decode_value(nil, _state), do: nil

  defp decode_value({:tref, _} = tref, state) do
    # Decode table reference using luerl
    decoded = :luerl.decode(tref, state)
    decode_lua_table(decoded, state)
  end

  defp decode_value(other, _state), do: inspect(other)

  defp decode_lua_table(table, state) when is_list(table) do
    # Check if it's an array (sequential integer keys starting at 1)
    if array_table?(table) do
      table
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {_k, v} -> decode_nested_value(v, state) end)
    else
      Map.new(table, fn {k, v} -> {decode_key(k), decode_nested_value(v, state)} end)
    end
  end

  defp decode_lua_table(other, _state), do: other

  # Decode nested values which may be lists (tables) or table refs
  defp decode_nested_value({:tref, _} = tref, state) do
    decoded = :luerl.decode(tref, state)
    decode_lua_table(decoded, state)
  end

  defp decode_nested_value(list, state) when is_list(list) do
    # This is an inline table, decode it
    decode_lua_table(list, state)
  end

  defp decode_nested_value(v, _state) when is_binary(v), do: v
  defp decode_nested_value(v, _state) when is_number(v), do: v
  defp decode_nested_value(v, _state) when is_boolean(v), do: v
  defp decode_nested_value(nil, _state), do: nil
  defp decode_nested_value(other, _state), do: inspect(other)

  defp decode_key(k) when is_binary(k), do: k
  defp decode_key(k) when is_number(k), do: trunc(k)
  defp decode_key(k), do: inspect(k)

  defp array_table?(table) when is_list(table) do
    keys = Enum.map(table, fn {k, _v} -> k end)

    # Empty list is considered an array
    if Enum.empty?(keys) do
      true
    else
      num_keys = length(keys)
      expected = Enum.to_list(1..num_keys)
      sorted_int_keys = keys |> Enum.map(&to_int_key/1) |> Enum.sort()
      sorted_int_keys == expected
    end
  end

  defp to_int_key(k) when is_integer(k), do: k
  defp to_int_key(k) when is_float(k), do: trunc(k)
  defp to_int_key(_), do: nil

  # ============================================================================
  # Deprecation Warning
  # ============================================================================

  # Warns about using the global manager without a session_id.
  # The warning can be suppressed by setting :suppress_global_manager_warnings
  # in the :jido_code application config.
  defp warn_global_usage(function_name) do
    unless Application.get_env(:jido_code, :suppress_global_manager_warnings, false) do
      Logger.warning(
        "Tools.Manager.#{function_name}/1 called without session_id. " <>
          "Global manager usage is deprecated. " <>
          "Pass session_id: your_session_id or use Session.Manager directly."
      )
    end
  end
end
