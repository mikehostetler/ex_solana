defmodule JidoSandbox.Sandbox do
  @moduledoc """
  Core sandbox struct containing VFS state and snapshots.

  This module handles all sandbox operations including file management,
  snapshots, and Lua evaluation.
  """

  alias JidoSandbox.Lua.Runtime
  alias JidoSandbox.VFS.InMemory

  @type t :: %__MODULE__{
          vfs: struct(),
          snapshots: %{String.t() => struct()},
          next_snapshot_id: non_neg_integer()
        }

  defstruct vfs: nil, snapshots: %{}, next_snapshot_id: 0

  @doc """
  Create a new sandbox with an empty VFS.

  ## Options

  Currently no options are supported.

  ## Examples

      iex> sandbox = JidoSandbox.Sandbox.new()
      iex> is_struct(sandbox, JidoSandbox.Sandbox)
      true

  """
  @spec new(keyword()) :: t()
  def new(_opts \\ []) do
    %__MODULE__{vfs: InMemory.new()}
  end

  @doc """
  Write content to a file in the sandbox.

  ## Examples

      iex> sandbox = JidoSandbox.Sandbox.new()
      iex> {:ok, sandbox} = JidoSandbox.Sandbox.write(sandbox, "/test.txt", "hello")
      iex> {:ok, "hello"} = JidoSandbox.Sandbox.read(sandbox, "/test.txt")

  """
  @spec write(t(), String.t(), iodata()) :: {:ok, t()} | {:error, term()}
  def write(%__MODULE__{} = sandbox, path, content) do
    case InMemory.write(sandbox.vfs, path, content) do
      {:ok, vfs} -> {:ok, %{sandbox | vfs: vfs}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Read content from a file in the sandbox.
  """
  @spec read(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{} = sandbox, path) do
    InMemory.read(sandbox.vfs, path)
  end

  @doc """
  List entries in a directory.
  """
  @spec list(t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list(%__MODULE__{} = sandbox, path) do
    InMemory.list(sandbox.vfs, path)
  end

  @doc """
  Delete a file or empty directory from the sandbox.
  """
  @spec delete(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def delete(%__MODULE__{} = sandbox, path) do
    case InMemory.delete(sandbox.vfs, path) do
      {:ok, vfs} -> {:ok, %{sandbox | vfs: vfs}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a directory in the sandbox.
  """
  @spec mkdir(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def mkdir(%__MODULE__{} = sandbox, path) do
    case InMemory.mkdir(sandbox.vfs, path) do
      {:ok, vfs} -> {:ok, %{sandbox | vfs: vfs}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a snapshot of the current VFS state.

  Returns `{:ok, snapshot_id, updated_sandbox}`.
  """
  @spec snapshot(t()) :: {:ok, String.t(), t()}
  def snapshot(%__MODULE__{} = sandbox) do
    id = "snap-#{sandbox.next_snapshot_id}"
    snapshots = Map.put(sandbox.snapshots, id, sandbox.vfs)
    {:ok, id, %{sandbox | snapshots: snapshots, next_snapshot_id: sandbox.next_snapshot_id + 1}}
  end

  @doc """
  Restore VFS to a previous snapshot.
  """
  @spec restore(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def restore(%__MODULE__{} = sandbox, id) do
    case Map.fetch(sandbox.snapshots, id) do
      {:ok, vfs} -> {:ok, %{sandbox | vfs: vfs}}
      :error -> {:error, :unknown_snapshot}
    end
  end

  @doc """
  Evaluate Lua code in the sandbox.

  The Lua environment has access to VFS operations via the `vfs` namespace:
  - `vfs.read(path)` - Read file contents
  - `vfs.write(path, content)` - Write file  
  - `vfs.list(path)` - List directory contents
  - `vfs.mkdir(path)` - Create directory
  - `vfs.delete(path)` - Delete file or empty directory

  Dangerous globals are removed for security (os, io, package, debug, etc.).

  ## Examples

      iex> sandbox = JidoSandbox.Sandbox.new()
      iex> {:ok, result, _sandbox} = JidoSandbox.Sandbox.eval_lua(sandbox, "return 1 + 1")
      iex> result
      2

  """
  @spec eval_lua(t(), String.t()) :: {:ok, term(), t()} | {:error, term(), t()}
  def eval_lua(%__MODULE__{} = sandbox, code) when is_binary(code) do
    case Runtime.eval(code, sandbox.vfs) do
      {:ok, result, vfs} ->
        {:ok, result, %{sandbox | vfs: vfs}}

      {:error, reason} ->
        {:error, reason, sandbox}
    end
  end
end
