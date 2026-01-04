defmodule JidoSandbox.VFS do
  @moduledoc """
  Behavior for Virtual Filesystem implementations.

  All VFS implementations must provide these callbacks for file and directory operations.
  All paths are expected to be absolute (starting with `/`) and normalized.
  """

  @type path :: String.t()
  @type t :: struct()

  @doc "Create a new VFS instance."
  @callback new() :: t()

  @doc "Write content to a file at the given path."
  @callback write(t(), path(), iodata()) :: {:ok, t()} | {:error, term()}

  @doc "Read content from a file at the given path."
  @callback read(t(), path()) :: {:ok, binary()} | {:error, term()}

  @doc "List entries in a directory at the given path."
  @callback list(t(), path()) :: {:ok, [String.t()]} | {:error, term()}

  @doc "Delete a file at the given path."
  @callback delete(t(), path()) :: {:ok, t()} | {:error, term()}

  @doc "Create a directory at the given path."
  @callback mkdir(t(), path()) :: {:ok, t()} | {:error, term()}
end
