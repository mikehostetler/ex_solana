defmodule JidoCode.Tools.Definitions.Shell do
  @moduledoc """
  Tool definitions for shell execution operations.

  This module defines tools for executing shell commands that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `run_command` - Execute a shell command with arguments

  ## Security

  The run_command tool enforces several security measures:
  - **Command allowlist**: Only pre-approved commands can be executed
  - **Shell interpreter blocking**: bash, sh, zsh, etc. are blocked
  - **Path argument validation**: Path traversal and absolute paths are blocked
  - **Output truncation**: Output limited to 1MB to prevent memory exhaustion

  ## Usage

      # Register all shell tools
      for tool <- Shell.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      run_cmd_tool = Shell.run_command()
      :ok = Registry.register(run_cmd_tool)
  """

  alias JidoCode.Tools.Handlers.Shell, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all shell tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      run_command()
    ]
  end

  @doc """
  Returns the run_command tool definition.

  Executes a shell command in the project directory with security validation,
  timeout enforcement, and output size limits.

  ## Parameters

  - `command` (required, string) - Command to execute (must be in allowlist)
  - `args` (optional, array) - Command arguments
  - `timeout` (optional, integer) - Timeout in milliseconds (default: 25000)

  ## Security

  Commands must be in the allowed list: mix, git, npm, ls, cat, grep, etc.
  Shell interpreters (bash, sh, zsh) are blocked to prevent command injection.
  Arguments with path traversal patterns (..) or absolute paths outside
  the project root are rejected.

  ## Output

  Returns JSON with exit_code and stdout. Note: stderr is merged into stdout
  for simplicity. Output is truncated at 1MB.
  """
  @spec run_command() :: Tool.t()
  def run_command do
    Tool.new!(%{
      name: "run_command",
      description:
        "Execute a shell command in the project directory. Returns exit code and output (stderr merged into stdout). " <>
          "Only allowed commands can be executed (mix, git, npm, ls, cat, grep, etc.). " <>
          "Shell interpreters (bash, sh) are blocked. Path traversal in arguments is blocked. " <>
          "Commands timeout after 25 seconds by default. Output is truncated at 1MB.",
      handler: Handlers.RunCommand,
      parameters: [
        %{
          name: "command",
          type: :string,
          description:
            "Command to execute (must be in allowlist: mix, git, npm, ls, cat, grep, find, etc.)",
          required: true
        },
        %{
          name: "args",
          type: :array,
          description:
            "Command arguments as array (e.g., ['test', '--trace']). Path traversal (..) is blocked.",
          required: false
        },
        %{
          name: "timeout",
          type: :integer,
          description: "Timeout in milliseconds (default: 25000, i.e., 25 seconds)",
          required: false
        }
      ]
    })
  end
end
