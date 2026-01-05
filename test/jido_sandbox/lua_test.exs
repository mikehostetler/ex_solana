defmodule JidoSandbox.LuaTest do
  use ExUnit.Case

  describe "eval_lua/2" do
    test "evaluates simple expressions" do
      sandbox = JidoSandbox.new()
      {:ok, result, _sandbox} = JidoSandbox.eval_lua(sandbox, "return 1 + 1")
      assert result == 2
    end

    test "returns nil for no return value" do
      sandbox = JidoSandbox.new()
      {:ok, result, _sandbox} = JidoSandbox.eval_lua(sandbox, "local x = 1")
      assert result == nil
    end

    test "returns multiple values as list" do
      sandbox = JidoSandbox.new()
      {:ok, result, _sandbox} = JidoSandbox.eval_lua(sandbox, "return 1, 2, 3")
      assert result == [1, 2, 3]
    end

    test "returns string values" do
      sandbox = JidoSandbox.new()
      {:ok, result, _sandbox} = JidoSandbox.eval_lua(sandbox, "return 'hello'")
      assert result == "hello"
    end

    test "returns error for syntax errors" do
      sandbox = JidoSandbox.new()
      {:error, reason, ^sandbox} = JidoSandbox.eval_lua(sandbox, "return invalid syntax")
      assert is_binary(reason)
    end
  end

  describe "vfs.write and vfs.read from Lua" do
    test "writes and reads a file" do
      sandbox = JidoSandbox.new()

      {:ok, result, sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        vfs.write("/test.txt", "Hello from Lua!")
        return vfs.read("/test.txt")
        """)

      assert result == "Hello from Lua!"

      # Verify via Elixir API
      {:ok, content} = JidoSandbox.read(sandbox, "/test.txt")
      assert content == "Hello from Lua!"
    end

    test "Lua changes are visible in Elixir" do
      sandbox = JidoSandbox.new()

      {:ok, _, sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        vfs.write("/from_lua.txt", "created in lua")
        """)

      {:ok, content} = JidoSandbox.read(sandbox, "/from_lua.txt")
      assert content == "created in lua"
    end

    test "Elixir changes are visible in Lua" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/from_elixir.txt", "created in elixir")

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return vfs.read("/from_elixir.txt")
        """)

      assert result == "created in elixir"
    end
  end

  describe "vfs.mkdir from Lua" do
    test "creates a directory" do
      sandbox = JidoSandbox.new()

      {:ok, result, sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        vfs.mkdir("/mydir")
        vfs.write("/mydir/file.txt", "nested file")
        return vfs.read("/mydir/file.txt")
        """)

      assert result == "nested file"

      {:ok, entries} = JidoSandbox.list(sandbox, "/")
      assert "mydir/" in entries
    end
  end

  describe "vfs.list from Lua" do
    test "lists directory contents" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/a.txt", "a")
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/b.txt", "b")

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        local entries = vfs.list("/")
        return entries[1], entries[2]
        """)

      assert result == ["a.txt", "b.txt"]
    end
  end

  describe "vfs.delete from Lua" do
    test "deletes a file" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/to_delete.txt", "x")

      {:ok, _, sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        vfs.delete("/to_delete.txt")
        """)

      assert {:error, :file_not_found} = JidoSandbox.read(sandbox, "/to_delete.txt")
    end
  end

  describe "sandbox security" do
    test "os module is blocked" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return os
        """)

      assert result == nil
    end

    test "io module is blocked" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return io
        """)

      assert result == nil
    end

    test "package module is blocked" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return package
        """)

      assert result == nil
    end

    test "debug module is blocked" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return debug
        """)

      assert result == nil
    end

    test "loadfile is blocked" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return loadfile
        """)

      assert result == nil
    end

    test "dofile is blocked" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        return dofile
        """)

      assert result == nil
    end
  end

  describe "error handling" do
    test "vfs.read returns nil and error for missing file" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        local content, err = vfs.read("/missing.txt")
        return content, err
        """)

      assert result == [nil, "file_not_found"]
    end

    test "vfs.write returns nil and error for missing parent" do
      sandbox = JidoSandbox.new()

      {:ok, result, _sandbox} =
        JidoSandbox.eval_lua(sandbox, """
        local ok, err = vfs.write("/missing/file.txt", "x")
        return ok, err
        """)

      assert result == [nil, "parent_directory_not_found"]
    end
  end
end
