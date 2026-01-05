defmodule JidoSandboxTest do
  use ExUnit.Case

  describe "new/0" do
    test "creates a new sandbox" do
      sandbox = JidoSandbox.new()
      assert is_struct(sandbox, JidoSandbox.Sandbox)
    end

    test "sandbox has empty VFS" do
      sandbox = JidoSandbox.new()
      assert is_struct(sandbox.vfs, JidoSandbox.VFS.InMemory)
    end
  end

  describe "write/3 and read/2" do
    test "write and read roundtrip" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/hello.txt", "Hello, World!")
      {:ok, content} = JidoSandbox.read(sandbox, "/hello.txt")
      assert content == "Hello, World!"
    end

    test "write accepts iodata" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/test.txt", ["a", "b", "c"])
      {:ok, content} = JidoSandbox.read(sandbox, "/test.txt")
      assert content == "abc"
    end

    test "read non-existent file returns error" do
      sandbox = JidoSandbox.new()
      assert {:error, :file_not_found} = JidoSandbox.read(sandbox, "/missing.txt")
    end

    test "write to non-existent directory returns error" do
      sandbox = JidoSandbox.new()
      assert {:error, :parent_directory_not_found} = JidoSandbox.write(sandbox, "/foo/bar.txt", "x")
    end
  end

  describe "mkdir/2" do
    test "creates a directory" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.mkdir(sandbox, "/mydir")
      {:ok, entries} = JidoSandbox.list(sandbox, "/")
      assert "mydir/" in entries
    end

    test "allows writing to created directory" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.mkdir(sandbox, "/mydir")
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/mydir/file.txt", "content")
      {:ok, content} = JidoSandbox.read(sandbox, "/mydir/file.txt")
      assert content == "content"
    end
  end

  describe "list/2" do
    test "lists files in root" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/a.txt", "a")
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/b.txt", "b")
      {:ok, entries} = JidoSandbox.list(sandbox, "/")
      assert entries == ["a.txt", "b.txt"]
    end

    test "lists files and directories" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/file.txt", "x")
      {:ok, sandbox} = JidoSandbox.mkdir(sandbox, "/dir")
      {:ok, entries} = JidoSandbox.list(sandbox, "/")
      assert entries == ["dir/", "file.txt"]
    end
  end

  describe "delete/2" do
    test "deletes a file" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/test.txt", "x")
      {:ok, sandbox} = JidoSandbox.delete(sandbox, "/test.txt")
      assert {:error, :file_not_found} = JidoSandbox.read(sandbox, "/test.txt")
    end

    test "deletes empty directory" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.mkdir(sandbox, "/empty")
      {:ok, sandbox} = JidoSandbox.delete(sandbox, "/empty")
      {:ok, entries} = JidoSandbox.list(sandbox, "/")
      refute "empty/" in entries
    end
  end

  describe "snapshot/1 and restore/2" do
    test "creates a snapshot and returns an ID" do
      sandbox = JidoSandbox.new()
      {:ok, snapshot_id, new_sandbox} = JidoSandbox.snapshot(sandbox)

      assert is_binary(snapshot_id)
      assert String.starts_with?(snapshot_id, "snap-")
      assert new_sandbox.next_snapshot_id == 1
    end

    test "increments snapshot ID" do
      sandbox = JidoSandbox.new()
      {:ok, "snap-0", sandbox} = JidoSandbox.snapshot(sandbox)
      {:ok, "snap-1", sandbox} = JidoSandbox.snapshot(sandbox)
      {:ok, "snap-2", _sandbox} = JidoSandbox.snapshot(sandbox)
    end

    test "restore brings back previous state" do
      sandbox = JidoSandbox.new()
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/original.txt", "original")
      {:ok, snapshot_id, sandbox} = JidoSandbox.snapshot(sandbox)

      # Modify the state
      {:ok, sandbox} = JidoSandbox.write(sandbox, "/new.txt", "new")
      {:ok, sandbox} = JidoSandbox.delete(sandbox, "/original.txt")

      # Verify new state
      assert {:error, :file_not_found} = JidoSandbox.read(sandbox, "/original.txt")
      {:ok, "new"} = JidoSandbox.read(sandbox, "/new.txt")

      # Restore
      {:ok, sandbox} = JidoSandbox.restore(sandbox, snapshot_id)

      # Verify restored state
      {:ok, "original"} = JidoSandbox.read(sandbox, "/original.txt")
      assert {:error, :file_not_found} = JidoSandbox.read(sandbox, "/new.txt")
    end

    test "returns error for unknown snapshot" do
      sandbox = JidoSandbox.new()
      assert {:error, :unknown_snapshot} = JidoSandbox.restore(sandbox, "snap-999")
    end
  end

  describe "eval_lua/2" do
    test "evaluates Lua code and returns result" do
      sandbox = JidoSandbox.new()
      assert {:ok, 1, _sandbox} = JidoSandbox.eval_lua(sandbox, "return 1")
    end
  end
end
