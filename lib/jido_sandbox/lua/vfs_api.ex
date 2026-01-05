defmodule JidoSandbox.Lua.VfsApi do
  @moduledoc """
  Lua API for VFS operations.

  Exposes VFS functions to Lua under the `vfs` namespace:
  - `vfs.read(path)` - Read file contents
  - `vfs.write(path, content)` - Write file contents
  - `vfs.list(path)` - List directory contents
  - `vfs.mkdir(path)` - Create directory
  - `vfs.delete(path)` - Delete file or empty directory

  The VFS state must be stored in `_G.__vfs__` before using these functions.
  """

  use Lua.API, scope: "vfs"

  alias JidoSandbox.VFS.InMemory

  @vfs_key [:_G, :__vfs__]

  @doc """
  Read a file from the VFS.

  Returns the file contents as a string, or nil and an error message on failure.
  """
  deflua read(path), state do
    {:userdata, vfs} = Lua.get!(state, @vfs_key)
    path = to_string(path)

    case InMemory.read(vfs, path) do
      {:ok, content} ->
        {[content], state}

      {:error, reason} ->
        {[nil, to_string(reason)], state}
    end
  end

  @doc """
  Write content to a file in the VFS.

  Returns true on success, or nil and an error message on failure.
  """
  deflua write(path, content), state do
    {:userdata, vfs} = Lua.get!(state, @vfs_key)
    path = to_string(path)
    content = to_string(content)

    case InMemory.write(vfs, path, content) do
      {:ok, new_vfs} ->
        {encoded, state} = Lua.encode!(state, {:userdata, new_vfs})
        state = Lua.set!(state, @vfs_key, encoded)
        {[true], state}

      {:error, reason} ->
        {[nil, to_string(reason)], state}
    end
  end

  @doc """
  List directory contents.

  Returns a table of entries, or nil and an error message on failure.
  """
  deflua list(path), state do
    {:userdata, vfs} = Lua.get!(state, @vfs_key)
    path = to_string(path)

    case InMemory.list(vfs, path) do
      {:ok, entries} ->
        {table, state} = Lua.encode!(state, entries)
        {[table], state}

      {:error, reason} ->
        {[nil, to_string(reason)], state}
    end
  end

  @doc """
  Create a directory.

  Returns true on success, or nil and an error message on failure.
  """
  deflua mkdir(path), state do
    {:userdata, vfs} = Lua.get!(state, @vfs_key)
    path = to_string(path)

    case InMemory.mkdir(vfs, path) do
      {:ok, new_vfs} ->
        {encoded, state} = Lua.encode!(state, {:userdata, new_vfs})
        state = Lua.set!(state, @vfs_key, encoded)
        {[true], state}

      {:error, reason} ->
        {[nil, to_string(reason)], state}
    end
  end

  @doc """
  Delete a file or empty directory.

  Returns true on success, or nil and an error message on failure.
  """
  deflua delete(path), state do
    {:userdata, vfs} = Lua.get!(state, @vfs_key)
    path = to_string(path)

    case InMemory.delete(vfs, path) do
      {:ok, new_vfs} ->
        {encoded, state} = Lua.encode!(state, {:userdata, new_vfs})
        state = Lua.set!(state, @vfs_key, encoded)
        {[true], state}

      {:error, reason} ->
        {[nil, to_string(reason)], state}
    end
  end
end
