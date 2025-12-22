defmodule JidoCode.Tools.Handlers.Shell do
  @moduledoc """
  Handler module for shell execution tools.

  This module contains the RunCommand handler for executing shell commands in a
  controlled environment with security validation, timeout enforcement, and output capture.

  ## Session Context

  Handlers use `HandlerHelpers.get_project_root/1` for session-aware working directory:

  1. `session_id` present → Uses `Session.Manager.project_root/1`
  2. `project_root` present → Uses provided project root (legacy)
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Security Considerations

  - **Command allowlist**: Only pre-approved commands can be executed
  - **Shell interpreter blocking**: bash, sh, zsh, etc. are blocked to prevent bypass
  - **Path argument validation**: Arguments containing path traversal are blocked
  - **Directory containment**: Commands run in session's project directory
  - **Timeout enforcement**: Prevents hanging commands
  - **Output truncation**: Prevents memory exhaustion from large outputs

  ## Usage

  This handler is invoked by the Executor when the LLM calls shell tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "mix", "args" => ["test"]}
      }, context: context)

  ## Context

  The context map should contain:
  - `:session_id` - Session ID for project root lookup (preferred)
  - `:project_root` - Base directory for command execution (legacy)
  """

  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Constants
  # ============================================================================

  @allowed_commands ~w(
    mix elixir iex
    git
    npm npx yarn pnpm node
    cargo rustc
    go
    python python3 pip pip3
    ls cat head tail grep find wc diff sort uniq
    test true false echo printf pwd
    mkdir rmdir cp mv ln touch rm
    date time sleep
    rebar3 erlc erl
    make cmake
    curl wget
  )

  @shell_interpreters ~w(bash sh zsh fish dash ksh csh tcsh ash)

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  @spec get_project_root(map()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  defdelegate validate_path(path, context), to: HandlerHelpers

  @doc false
  @spec format_error(atom() | {atom(), term()} | String.t(), String.t()) :: String.t()
  def format_error(:enoent, command), do: "Command not found: #{command}"
  def format_error(:eacces, command), do: "Permission denied: #{command}"
  def format_error(:enomem, _command), do: "Out of memory"
  def format_error(:command_not_allowed, command), do: "Command not allowed: #{command}"

  def format_error(:shell_interpreter_blocked, command),
    do: "Shell interpreters are blocked: #{command}"

  def format_error(:timeout, command),
    do: "Command timed out: #{command}"

  def format_error(:path_traversal_blocked, arg),
    do: "Path traversal not allowed in argument: #{arg}"

  def format_error(:absolute_path_blocked, arg),
    do: "Absolute paths outside project not allowed: #{arg}"

  def format_error({:path_traversal_blocked, arg}, _command),
    do: "Path traversal not allowed in argument: #{arg}"

  def format_error({:absolute_path_blocked, arg}, _command),
    do: "Absolute paths outside project not allowed: #{arg}"

  def format_error({kind, reason}, command),
    do: "Shell error executing #{command}: #{kind} - #{inspect(reason)}"

  def format_error(reason, command) when is_atom(reason), do: "Error (#{reason}): #{command}"
  def format_error(reason, _command) when is_binary(reason), do: reason
  def format_error(reason, command), do: "Error (#{inspect(reason)}): #{command}"

  @doc false
  @spec validate_command(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_command(command) do
    cond do
      command in @shell_interpreters ->
        {:error, :shell_interpreter_blocked}

      command in @allowed_commands ->
        {:ok, command}

      true ->
        {:error, :command_not_allowed}
    end
  end

  @doc false
  @spec allowed_commands() :: [String.t()]
  def allowed_commands, do: @allowed_commands

  @doc false
  @spec shell_interpreters() :: [String.t()]
  def shell_interpreters, do: @shell_interpreters

  # ============================================================================
  # RunCommand Handler
  # ============================================================================

  defmodule RunCommand do
    @moduledoc """
    Handler for the run_command tool.

    Executes shell commands in the project directory with security validation,
    timeout enforcement, and output size limits.

    Uses session-aware project root via `HandlerHelpers.get_project_root/1`.
    """

    alias JidoCode.Tools.Handlers.Shell

    @default_timeout 25_000
    @max_output_size 1_048_576

    @doc """
    Executes a shell command.

    ## Arguments

    - `"command"` - Command to execute (must be in allowlist)
    - `"args"` - Command arguments (optional, default: [])
    - `"timeout"` - Timeout in milliseconds (optional, default: 25000)

    ## Context

    - `:session_id` - Session ID for project root lookup (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, json}` - JSON with exit_code, stdout (stderr merged into stdout)
    - `{:error, reason}` - Error message

    ## Security

    - Command must be in the allowed commands list
    - Shell interpreters (bash, sh, etc.) are blocked
    - Arguments with path traversal patterns are blocked
    - Absolute paths outside project root are blocked
    - Output is truncated at 1MB to prevent memory exhaustion
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"command" => command} = args, context) when is_binary(command) do
      with {:ok, _valid_command} <- Shell.validate_command(command),
           {:ok, project_root} <- Shell.get_project_root(context),
           raw_args <- Map.get(args, "args", []),
           cmd_args <- parse_args(raw_args),
           :ok <- validate_path_args(cmd_args, project_root) do
        timeout = Map.get(args, "timeout", @default_timeout)
        run_command(command, cmd_args, project_root, timeout)
      else
        {:error, reason} when is_atom(reason) ->
          {:error, Shell.format_error(reason, command)}

        {:error, reason} ->
          {:error, Shell.format_error(reason, command)}
      end
    end

    def execute(_args, _context) do
      {:error, "run_command requires a command argument"}
    end

    defp parse_args(args) when is_list(args) do
      Enum.map(args, &to_string/1)
    end

    defp parse_args(_args), do: []

    # Validate path-like arguments against project boundary
    defp validate_path_args(args, project_root) do
      Enum.reduce_while(args, :ok, fn arg, _acc ->
        case validate_single_arg(arg, project_root) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end

    # Special system paths that are always allowed
    @allowed_system_paths ~w(/dev/null /dev/stdin /dev/stdout /dev/stderr /dev/zero /dev/random /dev/urandom)

    # Check for path traversal patterns including URL-encoded variants
    defp contains_path_traversal?(arg) do
      lower = String.downcase(arg)

      String.contains?(arg, "../") or
        String.contains?(lower, "%2e%2e%2f") or
        String.contains?(lower, "%2e%2e/") or
        String.contains?(lower, "..%2f") or
        String.contains?(lower, "%2e%2e%5c") or
        String.contains?(lower, "..%5c")
    end

    defp validate_single_arg(arg, project_root) do
      cond do
        # Check for path traversal patterns (literal and URL-encoded)
        contains_path_traversal?(arg) ->
          {:error, {:path_traversal_blocked, arg}}

        # Allow special system paths
        arg in @allowed_system_paths ->
          :ok

        # Check absolute paths - must be within project
        String.starts_with?(arg, "/") ->
          expanded = Path.expand(arg)

          if String.starts_with?(expanded, project_root) do
            :ok
          else
            {:error, {:absolute_path_blocked, arg}}
          end

        # Relative paths and non-path args are OK
        true ->
          :ok
      end
    end

    defp run_command(command, args, project_root, timeout) do
      # Use Task.async with yield/shutdown to enforce timeout
      task =
        Task.async(fn ->
          try do
            System.cmd(command, args,
              cd: project_root,
              stderr_to_stdout: true,
              env: []
            )
          rescue
            e in ErlangError -> {:error, e.original}
          catch
            :exit, reason -> {:error, {:exit, reason}}
          end
        end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:error, :enoent}} ->
          {:error, Shell.format_error(:enoent, command)}

        {:ok, {:error, :eacces}} ->
          {:error, Shell.format_error(:eacces, command)}

        {:ok, {:error, {:exit, reason}}} ->
          {:error, Shell.format_error({:exit, reason}, command)}

        {:ok, {:error, reason}} ->
          {:error, Shell.format_error({:system_error, reason}, command)}

        {:ok, {output, exit_code}} ->
          stdout = maybe_truncate(output)

          formatted = %{
            exit_code: exit_code,
            stdout: stdout,
            stderr: ""
          }

          {:ok, Jason.encode!(formatted)}

        nil ->
          # Timeout - task was killed
          {:error, Shell.format_error(:timeout, command)}
      end
    end

    @spec maybe_truncate(String.t()) :: String.t()
    defp maybe_truncate(output) when is_binary(output) and byte_size(output) > @max_output_size do
      truncated = binary_part(output, 0, @max_output_size)
      truncated <> "\n\n[Output truncated at 1MB]"
    end

    defp maybe_truncate(output) when is_binary(output), do: output
    defp maybe_truncate(_), do: ""
  end
end
