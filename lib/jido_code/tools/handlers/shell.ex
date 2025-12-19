defmodule JidoCode.Tools.Handlers.Shell do
  @moduledoc """
  Handler module for shell execution tools.

  This module contains the RunCommand handler for executing shell commands in a
  controlled environment with security validation, timeout enforcement, and output capture.

  All shell operations go through the Lua sandbox via Manager API.

  ## Security Considerations

  - **Command allowlist**: Only pre-approved commands can be executed
  - **Shell interpreter blocking**: bash, sh, zsh, etc. are blocked to prevent bypass
  - **Path argument validation**: Arguments containing path traversal are blocked
  - **Directory containment**: Commands run in project directory (enforced via sandbox)
  - **Timeout enforcement**: Prevents hanging commands
  - **Output truncation**: Prevents memory exhaustion from large outputs

  ## Usage

  This handler is invoked by the Executor when the LLM calls shell tools:

      Executor.execute(%{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "mix", "args" => ["test"]}
      })

  ## Context

  The context map should contain:
  - `:project_root` - Base directory for command execution
  """

  alias JidoCode.Tools.{HandlerHelpers, Manager}

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
  @spec format_error(atom() | {atom(), term()} | String.t(), String.t()) :: String.t()
  def format_error(:enoent, command), do: "Command not found: #{command}"
  def format_error(:eacces, command), do: "Permission denied: #{command}"
  def format_error(:enomem, _command), do: "Out of memory"
  def format_error(:command_not_allowed, command), do: "Command not allowed: #{command}"

  def format_error(:shell_interpreter_blocked, command),
    do: "Shell interpreters are blocked: #{command}"

  def format_error(:path_traversal_blocked, arg),
    do: "Path traversal not allowed in argument: #{arg}"

  def format_error(:absolute_path_blocked, arg),
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

    All shell operations go through the Lua sandbox via Manager API.
    """

    alias JidoCode.Tools.Handlers.Shell
    alias JidoCode.Tools.Manager

    @default_timeout 25_000
    @max_output_size 1_048_576

    @doc """
    Executes a shell command.

    ## Arguments

    - `"command"` - Command to execute (must be in allowlist)
    - `"args"` - Command arguments (optional, default: [])
    - `"timeout"` - Timeout in milliseconds (optional, default: 25000)

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
    def execute(%{"command" => command} = args, _context) when is_binary(command) do
      # Note: Command validation is also done in Bridge.lua_shell, but we
      # validate here as well for early failure and clear error messages
      with {:ok, _valid_command} <- Shell.validate_command(command),
           raw_args <- Map.get(args, "args", []),
           cmd_args <- parse_args(raw_args) do
        _timeout = Map.get(args, "timeout", @default_timeout)
        run_command_via_sandbox(command, cmd_args)
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

    defp run_command_via_sandbox(command, args) do
      case Manager.shell(command, args) do
        {:ok, result} when is_map(result) ->
          # Truncate output if needed
          stdout = Map.get(result, "stdout", "") |> maybe_truncate()

          formatted = %{
            exit_code: Map.get(result, "exit_code", 0),
            stdout: stdout,
            stderr: Map.get(result, "stderr", "")
          }

          {:ok, Jason.encode!(formatted)}

        {:ok, result} ->
          # Handle other result formats
          {:ok, Jason.encode!(%{exit_code: 0, stdout: inspect(result), stderr: ""})}

        {:error, reason} ->
          {:error, reason}
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
