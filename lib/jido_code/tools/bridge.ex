defmodule JidoCode.Tools.Bridge do
  @moduledoc """
  Erlang-Lua bridge functions for the sandbox.

  This module provides Elixir functions that can be called from Lua scripts.
  All file operations validate paths using `Security.validate_path/3` before
  execution.

  ## Available Bridge Functions

  File operations:
  - `jido.read_file(path)` - Read file contents
  - `jido.write_file(path, content)` - Write content to file
  - `jido.list_dir(path)` - List directory contents
  - `jido.glob(pattern)` - Find files matching glob pattern
  - `jido.file_exists(path)` - Check if path exists
  - `jido.file_stat(path)` - Get file metadata (size, type, access)
  - `jido.is_file(path)` - Check if path is a regular file
  - `jido.is_dir(path)` - Check if path is a directory
  - `jido.delete_file(path)` - Delete a file
  - `jido.mkdir_p(path)` - Create directory (and parents)

  Shell operations:
  - `jido.shell(command, args)` - Execute shell command (validated against allowlist)

  ## Usage in Lua

      -- Read a file
      local content = jido.read_file("src/main.ex")

      -- Write a file
      jido.write_file("output.txt", "Hello, World!")

      -- List directory
      local files = jido.list_dir("src")

      -- Check existence
      if jido.file_exists("config.json") then ... end

      -- Run shell command (only allowed commands)
      local result = jido.shell("mix", {"test"})
      -- result = {exit_code = 0, stdout = "...", stderr = "..."}

  ## Error Handling

  Bridge functions return `{nil, error_message}` on failure, allowing
  Lua scripts to handle errors gracefully.

  ## Security

  Shell commands are validated against the same allowlist used by the
  `run_command` tool. Shell interpreters (bash, sh, zsh, etc.) are blocked.
  Path arguments are validated to prevent traversal attacks.
  """

  alias JidoCode.Tools.Handlers.Shell
  alias JidoCode.Tools.Helpers.GlobMatcher
  alias JidoCode.Tools.Security

  require Logger

  @default_shell_timeout 60_000

  # Read file defaults
  @default_offset 1
  @default_limit 2000
  @max_line_length 2000

  # ============================================================================
  # File Operations
  # ============================================================================

  @doc """
  Reads a file's contents with line numbers. Called from Lua as `jido.read_file(path)` or
  `jido.read_file(path, opts)`.

  Returns line-numbered output in cat -n style format:
  ```
       1→first line
       2→second line
  ```

  ## Parameters

  - `args` - Lua arguments: `[path]` or `[path, opts_table]`
    - `opts.offset` - Line to start from (1-indexed, default: 1)
    - `opts.limit` - Maximum lines to read (default: 2000)
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[content], state}` on success (line-numbered content)
  - `{[nil, error], state}` on failure

  ## Errors

  - Binary files are rejected (files containing null bytes)
  - Paths outside project boundary are rejected
  - Long lines (>2000 chars) are truncated with `[truncated]` indicator
  """
  def lua_read_file(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        do_read_file(path, %{}, state, project_root)

      # Handle decoded Elixir list (direct calls from tests)
      [path, opts] when is_binary(path) and is_list(opts) ->
        parsed_opts = parse_read_opts(opts)
        do_read_file(path, parsed_opts, state, project_root)

      # Handle Lua table reference (calls via luerl.do)
      [path, {:tref, _} = tref] when is_binary(path) ->
        opts = :luerl.decode(tref, state)
        parsed_opts = parse_read_opts(opts)
        do_read_file(path, parsed_opts, state, project_root)

      [path, opts] when is_binary(path) and is_map(opts) ->
        do_read_file(path, opts, state, project_root)

      _ ->
        {[nil, "read_file requires a path argument"], state}
    end
  end

  defp parse_read_opts(opts) when is_list(opts) do
    Enum.reduce(opts, %{}, fn
      {"offset", offset}, acc when is_number(offset) -> Map.put(acc, :offset, trunc(offset))
      {"limit", limit}, acc when is_number(limit) -> Map.put(acc, :limit, trunc(limit))
      _, acc -> acc
    end)
  end

  @spec do_read_file(String.t(), map(), :luerl.luerl_state(), String.t()) ::
          {list(), :luerl.luerl_state()}
  defp do_read_file(path, opts, state, project_root) do
    offset = Map.get(opts, :offset, @default_offset)
    limit = Map.get(opts, :limit, @default_limit)

    # SEC-2 Fix: Use atomic_read to mitigate TOCTOU race conditions
    case Security.atomic_read(path, project_root) do
      {:ok, content} ->
        process_file_content(content, offset, limit, path, state)

      {:error, reason} ->
        handle_operation_error(reason, path, state)
    end
  end

  # Unified error handling for security and file errors
  # Converts {:error, reason} to Lua-compatible {[nil, message], state}
  @security_errors [:path_escapes_boundary, :path_outside_boundary, :symlink_escapes_boundary]

  @spec handle_operation_error(atom(), String.t(), :luerl.luerl_state()) ::
          {list(), :luerl.luerl_state()}
  defp handle_operation_error(reason, path, state) when reason in @security_errors do
    {[nil, format_security_error(reason, path)], state}
  end

  defp handle_operation_error(reason, path, state) do
    {[nil, format_file_error(reason, path)], state}
  end

  defp process_file_content(content, offset, limit, path, state) do
    # Check for binary content (null bytes indicate binary file)
    if is_binary_content?(content) do
      {[nil, "Binary file detected: #{path}. Cannot read binary files."], state}
    else
      formatted = format_with_line_numbers(content, offset, limit)
      {[formatted], state}
    end
  end

  @doc false
  # Detects binary files by checking for null bytes in the first 8KB
  def is_binary_content?(content) when is_binary(content) do
    # Check the first 8KB for null bytes (common binary file indicator)
    sample_size = min(byte_size(content), 8192)
    sample = :binary.part(content, 0, sample_size)
    String.contains?(sample, <<0>>)
  end

  @doc false
  # Formats file content with line numbers (cat -n style)
  # Applies offset and limit, truncates long lines
  def format_with_line_numbers(content, offset, limit) when is_binary(content) do
    lines = String.split(content, ~r/\r?\n/, parts: :infinity)
    total_lines = length(lines)

    # Calculate the width needed for line numbers based on total lines
    line_num_width = max(6, String.length(Integer.to_string(total_lines)))

    lines
    |> Enum.with_index(1)
    |> Enum.drop(max(0, offset - 1))
    |> Enum.take(limit)
    |> Enum.map(fn {line, idx} ->
      truncated_line = truncate_line(line)
      pad_line_number(idx, line_num_width) <> "→" <> truncated_line
    end)
    |> Enum.join("\n")
  end

  defp truncate_line(line) when byte_size(line) > @max_line_length do
    truncated = String.slice(line, 0, @max_line_length)
    truncated <> " [truncated]"
  end

  defp truncate_line(line), do: line

  defp pad_line_number(num, width) do
    String.pad_leading(Integer.to_string(num), width, " ")
  end

  @doc """
  Writes content to a file. Called from Lua as `jido.write_file(path, content)`.

  ## Parameters

  - `args` - Lua arguments: `[path, content]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` on success
  - `{[nil, error], state}` on failure
  """
  def lua_write_file(args, state, project_root) do
    case args do
      [path, content] when is_binary(path) and is_binary(content) ->
        do_write_file(path, content, state, project_root)

      [path, _content] when is_binary(path) ->
        {[nil, "write_file content must be a string"], state}

      _ ->
        {[nil, "write_file requires path and content arguments"], state}
    end
  end

  @spec do_write_file(String.t(), String.t(), :luerl.luerl_state(), String.t()) ::
          {list(), :luerl.luerl_state()}
  defp do_write_file(path, content, state, project_root) do
    # SEC-2 Fix: Use atomic_write to mitigate TOCTOU race conditions
    case Security.atomic_write(path, content, project_root) do
      :ok ->
        {[true], state}

      {:error, reason} ->
        handle_operation_error(reason, path, state)
    end
  end

  @doc """
  Lists directory contents. Called from Lua as `jido.list_dir(path)` or
  `jido.list_dir(path, opts)`.

  ## Parameters

  - `args` - Lua arguments: `[path]` or `[path, opts]`
    - `path` - Directory path to list
    - `opts` - Optional Lua table with:
      - `ignore_patterns` - Array of glob patterns to exclude
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[entries], state}` on success (entries as Lua array of tables with name/type)
  - `{[nil, error], state}` on failure

  ## Entry Format

  Each entry is a Lua table with:
  - `name` - Entry name (string)
  - `type` - Either "file" or "directory"

  ## Sorting

  Entries are sorted with directories first, then alphabetically within each group.
  """
  @spec lua_list_dir(list(), :luerl.luerl_state(), String.t()) :: {list(), :luerl.luerl_state()}
  def lua_list_dir(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        do_list_dir(path, [], state, project_root)

      [path, opts] when is_binary(path) ->
        ignore_patterns = extract_ignore_patterns(opts)
        do_list_dir(path, ignore_patterns, state, project_root)

      [] ->
        # Default to project root
        lua_list_dir([""], state, project_root)

      _ ->
        {[nil, "list_dir requires a path argument"], state}
    end
  end

  # Extract ignore_patterns from Lua options table
  @spec extract_ignore_patterns(list() | any()) :: list(String.t())
  defp extract_ignore_patterns(opts) when is_list(opts) do
    case List.keyfind(opts, "ignore_patterns", 0) do
      {"ignore_patterns", patterns} when is_list(patterns) ->
        # Convert Lua array (list of {index, value} tuples) to list of strings
        patterns
        |> Enum.map(fn
          {_idx, pattern} when is_binary(pattern) -> pattern
          pattern when is_binary(pattern) -> pattern
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_ignore_patterns(_), do: []

  @spec do_list_dir(String.t(), list(String.t()), :luerl.luerl_state(), String.t()) ::
          {list(), :luerl.luerl_state()}
  defp do_list_dir(path, ignore_patterns, state, project_root) do
    with {:ok, safe_path} <- Security.validate_path(path, project_root),
         {:ok, entries} <- File.ls(safe_path) do
      # Filter, sort (directories first), and convert to Lua array format
      lua_array =
        entries
        |> Enum.reject(&GlobMatcher.matches_any?(&1, ignore_patterns))
        |> GlobMatcher.sort_directories_first(safe_path)
        |> Enum.with_index(1)
        |> Enum.map(fn {entry, idx} ->
          info = GlobMatcher.entry_info(safe_path, entry)
          {idx, [{"name", info.name}, {"type", info.type}]}
        end)

      {[lua_array], state}
    else
      {:error, reason} ->
        handle_operation_error(reason, path, state)
    end
  end

  @doc """
  Finds files matching a glob pattern. Called from Lua as `jido.glob(pattern)` or
  `jido.glob(pattern, path)`.

  ## Parameters

  - `args` - Lua arguments: `[pattern]` or `[pattern, path]`
    - `pattern` - Glob pattern (e.g., "**/*.ex", "*.{ex,exs}")
    - `path` - Base directory to search from (defaults to project root)
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[paths], state}` on success (paths as Lua array of relative paths)
  - `{[nil, error], state}` on failure

  ## Supported Patterns

  - `*` - Match any characters (not path separator)
  - `**` - Match any characters including path separators
  - `?` - Match any single character
  - `{a,b}` - Match either pattern a or pattern b
  - `[abc]` - Match any character in the set

  ## Sorting

  Results are sorted by modification time with newest files first.
  """
  @spec lua_glob(list(), :luerl.luerl_state(), String.t()) :: {list(), :luerl.luerl_state()}
  def lua_glob(args, state, project_root) do
    case args do
      [pattern] when is_binary(pattern) ->
        do_glob(pattern, ".", state, project_root)

      [pattern, path] when is_binary(pattern) and is_binary(path) ->
        do_glob(pattern, path, state, project_root)

      [] ->
        {[nil, "glob requires a pattern argument"], state}

      _ ->
        {[nil, "glob requires a pattern argument"], state}
    end
  end

  @spec do_glob(String.t(), String.t(), :luerl.luerl_state(), String.t()) ::
          {list(), :luerl.luerl_state()}
  defp do_glob(pattern, base_path, state, project_root) do
    with {:ok, safe_base} <- Security.validate_path(base_path, project_root),
         {:ok, _} <- ensure_exists(safe_base) do
      # Build full pattern path
      full_pattern = Path.join(safe_base, pattern)

      # Find matching files, filter to boundary, sort by mtime
      # Uses GlobMatcher for consistent behavior with GlobSearch handler
      matches =
        full_pattern
        |> Path.wildcard(match_dot: false)
        |> GlobMatcher.filter_within_boundary(project_root)
        |> GlobMatcher.sort_by_mtime_desc()
        |> GlobMatcher.make_relative(project_root)

      # Convert to Lua array format
      lua_array =
        matches
        |> Enum.with_index(1)
        |> Enum.map(fn {path, idx} -> {idx, path} end)

      {[lua_array], state}
    else
      {:error, :enoent} ->
        handle_operation_error(:enoent, base_path, state)

      {:error, reason} ->
        handle_operation_error(reason, base_path, state)
    end
  end

  # Helper to check file existence in a with-compatible format
  @spec ensure_exists(String.t()) :: {:ok, String.t()} | {:error, :enoent}
  defp ensure_exists(path) do
    if File.exists?(path), do: {:ok, path}, else: {:error, :enoent}
  end

  @doc """
  Checks if a path exists. Called from Lua as `jido.file_exists(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` if path exists
  - `{[false], state}` if path doesn't exist
  - `{[nil, error], state}` on security violation
  """
  def lua_file_exists(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        case Security.validate_path(path, project_root) do
          {:ok, safe_path} ->
            {[File.exists?(safe_path)], state}

          {:error, reason} ->
            {[nil, format_security_error(reason, path)], state}
        end

      _ ->
        {[nil, "file_exists requires a path argument"], state}
    end
  end

  @doc """
  Gets file stats. Called from Lua as `jido.file_stat(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[stat_table], state}` on success (stat as Lua table with size, type, etc.)
  - `{[nil, error], state}` on failure
  """
  def lua_file_stat(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        with {:ok, safe_path} <- Security.validate_path(path, project_root),
             {:ok, stat} <- File.stat(safe_path) do
          # Convert stat to Lua table format
          # Format mtime as ISO 8601 string
          mtime_str = format_datetime(stat.mtime)

          stat_table = [
            {"size", stat.size},
            {"type", Atom.to_string(stat.type)},
            {"access", Atom.to_string(stat.access)},
            {"mtime", mtime_str}
          ]

          {[stat_table], state}
        else
          {:error, reason}
          when reason in [
                 :path_escapes_boundary,
                 :path_outside_boundary,
                 :symlink_escapes_boundary
               ] ->
            {[nil, format_security_error(reason, path)], state}

          {:error, reason} ->
            {[nil, format_file_error(reason, path)], state}
        end

      _ ->
        {[nil, "file_stat requires a path argument"], state}
    end
  end

  defp format_datetime({{year, month, day}, {hour, minute, second}}) do
    # Format as ISO 8601
    :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", [
      year,
      month,
      day,
      hour,
      minute,
      second
    ])
    |> IO.iodata_to_binary()
  end

  defp format_datetime(_), do: ""

  @doc """
  Checks if a path is a regular file. Called from Lua as `jido.is_file(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` if path is a regular file
  - `{[false], state}` if path is not a regular file (or doesn't exist)
  - `{[nil, error], state}` on security violation
  """
  def lua_is_file(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        case Security.validate_path(path, project_root) do
          {:ok, safe_path} ->
            {[File.regular?(safe_path)], state}

          {:error, reason} ->
            {[nil, format_security_error(reason, path)], state}
        end

      _ ->
        {[nil, "is_file requires a path argument"], state}
    end
  end

  @doc """
  Checks if a path is a directory. Called from Lua as `jido.is_dir(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` if path is a directory
  - `{[false], state}` if path is not a directory (or doesn't exist)
  - `{[nil, error], state}` on security violation
  """
  def lua_is_dir(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        case Security.validate_path(path, project_root) do
          {:ok, safe_path} ->
            {[File.dir?(safe_path)], state}

          {:error, reason} ->
            {[nil, format_security_error(reason, path)], state}
        end

      _ ->
        {[nil, "is_dir requires a path argument"], state}
    end
  end

  @doc """
  Deletes a file. Called from Lua as `jido.delete_file(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` on success
  - `{[nil, error], state}` on failure
  """
  def lua_delete_file(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        with {:ok, safe_path} <- Security.validate_path(path, project_root),
             :ok <- File.rm(safe_path) do
          {[true], state}
        else
          {:error, reason}
          when reason in [
                 :path_escapes_boundary,
                 :path_outside_boundary,
                 :symlink_escapes_boundary
               ] ->
            {[nil, format_security_error(reason, path)], state}

          {:error, reason} ->
            {[nil, format_file_error(reason, path)], state}
        end

      _ ->
        {[nil, "delete_file requires a path argument"], state}
    end
  end

  @doc """
  Creates a directory (and parents). Called from Lua as `jido.mkdir_p(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` on success
  - `{[nil, error], state}` on failure
  """
  def lua_mkdir_p(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        with {:ok, safe_path} <- Security.validate_path(path, project_root),
             :ok <- File.mkdir_p(safe_path) do
          {[true], state}
        else
          {:error, reason}
          when reason in [
                 :path_escapes_boundary,
                 :path_outside_boundary,
                 :symlink_escapes_boundary
               ] ->
            {[nil, format_security_error(reason, path)], state}

          {:error, reason} ->
            {[nil, format_file_error(reason, path)], state}
        end

      _ ->
        {[nil, "mkdir_p requires a path argument"], state}
    end
  end

  # ============================================================================
  # Shell Operations
  # ============================================================================

  @doc """
  Executes a shell command. Called from Lua as `jido.shell(command, args)`.

  The command runs in the project directory with a configurable timeout.
  Returns exit code, stdout, and stderr.

  ## Parameters

  - `args` - Lua arguments: `[command]` or `[command, args_table]` or `[command, args_table, opts_table]`
  - `state` - Lua state
  - `project_root` - Project root (used as working directory)

  ## Returns

  - `{[result_table], state}` with `{exit_code, stdout, stderr}`
  - `{[nil, error], state}` on failure

  ## Examples in Lua

      -- Simple command
      local result = jido.shell("ls")

      -- Command with arguments
      local result = jido.shell("mix", {"test", "--trace"})

      -- Command with timeout
      local result = jido.shell("mix", {"compile"}, {timeout = 120000})
  """
  def lua_shell(args, state, project_root) do
    # Decode any table references in args before parsing
    decoded_args = decode_shell_args(args, state)

    case parse_shell_args(decoded_args) do
      {:ok, command, cmd_args, opts} ->
        # SEC-1 Fix: Validate command against allowlist (same as RunCommand handler)
        case Shell.validate_command(command) do
          {:ok, _} ->
            # SEC-3 Fix: Validate arguments for path traversal attacks
            case validate_shell_args(cmd_args, project_root) do
              :ok ->
                execute_validated_shell(command, cmd_args, opts, project_root, state)

              {:error, reason} ->
                {[nil, format_shell_security_error(reason)], state}
            end

          {:error, :shell_interpreter_blocked} ->
            {[nil, "Security error: shell interpreters are blocked (#{command})"], state}

          {:error, :command_not_allowed} ->
            {[nil, "Security error: command not in allowlist (#{command})"], state}
        end

      {:error, message} ->
        {[nil, message], state}
    end
  end

  defp execute_validated_shell(command, cmd_args, opts, project_root, state) do
    timeout = Keyword.get(opts, :timeout, @default_shell_timeout)

    # Wrap System.cmd in a Task to enforce timeout
    # System.cmd doesn't support timeout directly, so we use Task.async with Task.yield
    task =
      Task.async(fn ->
        try do
          {output, exit_code} =
            System.cmd(command, cmd_args,
              cd: project_root,
              stderr_to_stdout: false,
              into: "",
              env: []
            )

          {:ok, exit_code, output}
        catch
          :error, :enoent ->
            {:error, "Command not found: #{command}"}

          kind, reason ->
            {:error, "Shell error: #{kind} - #{inspect(reason)}"}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, exit_code, output}} ->
        # Return as list of tuples - luerl will convert inline to Lua table
        result = [
          {"exit_code", exit_code},
          {"stdout", output},
          {"stderr", ""}
        ]

        {[result], state}

      {:ok, {:error, message}} ->
        {[nil, message], state}

      nil ->
        # Task timed out
        {[nil, "Command timed out after #{timeout}ms"], state}
    end
  end

  # SEC-3 Fix: Validate shell arguments for path traversal
  @safe_system_paths ~w(/dev/null /dev/zero /dev/urandom /dev/random /dev/stdin /dev/stdout /dev/stderr)

  defp validate_shell_args(args, project_root) do
    Enum.reduce_while(args, :ok, fn arg, :ok ->
      case validate_shell_arg(arg, project_root) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_shell_arg(arg, project_root) do
    cond do
      # Block path traversal patterns
      String.contains?(arg, "..") ->
        {:error, {:path_traversal, arg}}

      # Allow safe system paths
      String.starts_with?(arg, "/") and arg in @safe_system_paths ->
        :ok

      # Block absolute paths outside project
      String.starts_with?(arg, "/") and not String.starts_with?(arg, project_root) ->
        {:error, {:absolute_path_outside_project, arg}}

      true ->
        :ok
    end
  end

  defp format_shell_security_error({:path_traversal, arg}) do
    "Security error: path traversal not allowed in argument: #{arg}"
  end

  defp format_shell_security_error({:absolute_path_outside_project, arg}) do
    "Security error: absolute paths outside project not allowed: #{arg}"
  end

  # ============================================================================
  # Registration
  # ============================================================================

  @doc """
  Registers all bridge functions in the Lua state.

  Creates the `jido` namespace table and registers each function.

  ## Parameters

  - `lua_state` - The Lua state to modify
  - `project_root` - Project root for path validation

  ## Returns

  The modified Lua state with bridge functions registered.
  """
  def register(lua_state, project_root) do
    # Create jido namespace as an empty Lua table
    {tref, lua_state} = :luerl.encode([], lua_state)
    {:ok, lua_state} = :luerl.set_table_keys(["jido"], tref, lua_state)

    # Register each bridge function
    lua_state
    |> register_function("read_file", &lua_read_file/3, project_root)
    |> register_function("write_file", &lua_write_file/3, project_root)
    |> register_function("list_dir", &lua_list_dir/3, project_root)
    |> register_function("glob", &lua_glob/3, project_root)
    |> register_function("file_exists", &lua_file_exists/3, project_root)
    |> register_function("file_stat", &lua_file_stat/3, project_root)
    |> register_function("is_file", &lua_is_file/3, project_root)
    |> register_function("is_dir", &lua_is_dir/3, project_root)
    |> register_function("delete_file", &lua_delete_file/3, project_root)
    |> register_function("mkdir_p", &lua_mkdir_p/3, project_root)
    |> register_function("shell", &lua_shell/3, project_root)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp register_function(lua_state, name, fun, project_root) do
    # Create a wrapper that captures project_root
    wrapper = fn args, state ->
      fun.(args, state, project_root)
    end

    # Wrap as {:erl_func, Fun} for luerl to recognize it as callable
    {:ok, state} = :luerl.set_table_keys(["jido", name], {:erl_func, wrapper}, lua_state)
    state
  end

  # Decode table references (tref) in shell args
  defp decode_shell_args(args, state) do
    Enum.map(args, fn
      {:tref, _} = tref ->
        # Decode Lua table reference
        :luerl.decode(tref, state)

      other ->
        other
    end)
  end

  defp parse_shell_args([command]) when is_binary(command) do
    {:ok, command, [], []}
  end

  defp parse_shell_args([command, args_table]) when is_binary(command) and is_list(args_table) do
    # Convert Lua array to list of strings
    cmd_args = decode_args_table(args_table)
    {:ok, command, cmd_args, []}
  end

  # Handle Lua table reference (tref) for args
  defp parse_shell_args([command, {:tref, _}]) when is_binary(command) do
    # Table reference needs to be decoded - but we don't have access to lua state here
    # This case shouldn't happen if we pre-decode in lua_shell
    {:error, "shell args must be pre-decoded (got tref)"}
  end

  defp parse_shell_args([command, args_table, opts_table])
       when is_binary(command) and is_list(args_table) and is_list(opts_table) do
    cmd_args = decode_args_table(args_table)
    opts = parse_shell_opts(opts_table)
    {:ok, command, cmd_args, opts}
  end

  defp parse_shell_args(_) do
    {:error, "shell requires a command string and optional args array"}
  end

  defp decode_args_table(args_table) when is_list(args_table) do
    args_table
    |> Enum.sort_by(fn {idx, _} -> idx end)
    |> Enum.map(fn {_, val} -> to_string(val) end)
  end

  defp decode_args_table(_), do: []

  defp parse_shell_opts(opts_table) do
    Enum.reduce(opts_table, [], fn
      {"timeout", timeout}, acc when is_number(timeout) ->
        [{:timeout, trunc(timeout)} | acc]

      _, acc ->
        acc
    end)
  end

  defp format_file_error(:enoent, path), do: "File not found: #{path}"
  defp format_file_error(:eacces, path), do: "Permission denied: #{path}"
  defp format_file_error(:eisdir, path), do: "Is a directory: #{path}"
  defp format_file_error(:enotdir, path), do: "Not a directory: #{path}"
  defp format_file_error(:enomem, _path), do: "Out of memory"
  defp format_file_error(reason, path), do: "File error (#{reason}): #{path}"

  defp format_security_error(:path_escapes_boundary, path) do
    "Security error: path escapes project boundary: #{path}"
  end

  defp format_security_error(:path_outside_boundary, path) do
    "Security error: path is outside project: #{path}"
  end

  defp format_security_error(:symlink_escapes_boundary, path) do
    "Security error: symlink points outside project: #{path}"
  end

  defp format_security_error(reason, path) do
    "Security error (#{reason}): #{path}"
  end
end
