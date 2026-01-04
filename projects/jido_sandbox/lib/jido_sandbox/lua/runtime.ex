defmodule JidoSandbox.Lua.Runtime do
  @moduledoc """
  Sandboxed Lua runtime with VFS bindings.

  Provides a restricted Lua environment where:
  - VFS operations are available via the `vfs` namespace
  - Dangerous globals are removed (os, io, package, require, debug, etc.)
  """

  alias JidoSandbox.Lua.VfsApi
  alias JidoSandbox.VFS.InMemory

  @vfs_key [:_G, :__vfs__]

  @doc """
  Evaluate Lua code with VFS bindings.

  Returns `{:ok, result, updated_vfs}` on success.
  Returns `{:error, reason}` on failure.
  """
  @spec eval(String.t(), InMemory.t()) :: {:ok, term(), InMemory.t()} | {:error, term()}
  def eval(code, %InMemory{} = vfs) when is_binary(code) do
    try do
      lua = Lua.new()

      {encoded_vfs, lua} = Lua.encode!(lua, {:userdata, vfs})

      lua =
        lua
        |> Lua.load_api(VfsApi)
        |> sandbox!()
        |> Lua.set!(@vfs_key, encoded_vfs)

      {result, lua} = Lua.eval!(lua, code)

      {:userdata, updated_vfs} = Lua.get!(lua, @vfs_key)

      result_value =
        case result do
          [] -> nil
          [val] -> val
          vals -> vals
        end

      {:ok, result_value, updated_vfs}
    rescue
      e in Lua.RuntimeException ->
        {:error, Exception.message(e)}

      e in Lua.CompilerException ->
        {:error, Exception.message(e)}

      e ->
        {:error, Exception.message(e)}
    end
  end

  defp sandbox!(lua) do
    dangerous_globals = [
      :os,
      :io,
      :package,
      :debug,
      :loadfile,
      :dofile
    ]

    Enum.reduce(dangerous_globals, lua, fn global, acc ->
      Lua.set!(acc, [global], nil)
    end)
  end
end
