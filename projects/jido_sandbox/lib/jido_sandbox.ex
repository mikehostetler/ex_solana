defmodule JidoSandbox do
  @moduledoc """
  Public entrypoint for sandbox operations.

  Jido Sandbox provides a lightweight, pure-BEAM sandbox for LLM tool calls.
  It implements an in-memory virtual filesystem (VFS) and sandboxed Lua execution.

  ## Key Constraints

  - No real filesystem access - all files are virtual
  - No networking - no HTTP, sockets, or external connections
  - No shell/process execution - no System.cmd, ports, or NIFs
  - Lua-only scripting - sandboxed Lua with VFS bindings only
  - All paths are virtual and absolute - must start with `/`

  ## Example

      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/hello.txt", "Hello!")
      {:ok, content} = JidoSandbox.read(sandbox, "/hello.txt")

  """

  alias JidoSandbox.Sandbox

  @type t :: Sandbox.t()

  @doc """
  Create a new sandbox.

  ## Examples

      iex> sandbox = JidoSandbox.new()
      iex> is_struct(sandbox, JidoSandbox.Sandbox)
      true

  """
  @spec new(keyword()) :: t()
  defdelegate new(opts \\ []), to: Sandbox

  @doc """
  Write content to a file in the sandbox.

  ## Examples

      iex> sandbox = JidoSandbox.new()
      iex> {:ok, sandbox} = JidoSandbox.write(sandbox, "/test.txt", "content")
      iex> {:ok, "content"} = JidoSandbox.read(sandbox, "/test.txt")

  """
  @spec write(t(), String.t(), iodata()) :: {:ok, t()} | {:error, term()}
  defdelegate write(sandbox, path, content), to: Sandbox

  @doc """
  Read content from a file in the sandbox.
  """
  @spec read(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  defdelegate read(sandbox, path), to: Sandbox

  @doc """
  List entries in a directory.
  """
  @spec list(t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defdelegate list(sandbox, path), to: Sandbox

  @doc """
  Delete a file from the sandbox.
  """
  @spec delete(t(), String.t()) :: {:ok, t()} | {:error, term()}
  defdelegate delete(sandbox, path), to: Sandbox

  @doc """
  Create a directory in the sandbox.
  """
  @spec mkdir(t(), String.t()) :: {:ok, t()} | {:error, term()}
  defdelegate mkdir(sandbox, path), to: Sandbox

  @doc """
  Create a snapshot of the current VFS state.

  Returns the snapshot ID that can be used with `restore/2`.
  """
  @spec snapshot(t()) :: {:ok, String.t(), t()}
  defdelegate snapshot(sandbox), to: Sandbox

  @doc """
  Restore VFS to a previous snapshot.
  """
  @spec restore(t(), String.t()) :: {:ok, t()} | {:error, term()}
  defdelegate restore(sandbox, snapshot_id), to: Sandbox

  @doc """
  Evaluate Lua code in the sandbox.

  Returns `{:ok, result, updated_sandbox}` on success.
  Returns `{:error, reason, sandbox}` on failure.
  """
  @spec eval_lua(t(), String.t()) :: {:ok, term(), t()} | {:error, term(), t()}
  defdelegate eval_lua(sandbox, code), to: Sandbox
end
