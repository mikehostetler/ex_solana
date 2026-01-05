defmodule JidoSandbox.VFS.InMemoryTest do
  use ExUnit.Case

  alias JidoSandbox.VFS.InMemory

  describe "new/0" do
    test "creates empty VFS with root directory" do
      vfs = InMemory.new()
      assert vfs.files == %{}
      assert MapSet.member?(vfs.dirs, "/")
    end
  end

  describe "write/3 and read/2" do
    test "write and read a file" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.write(vfs, "/hello.txt", "Hello, World!")
      {:ok, content} = InMemory.read(vfs, "/hello.txt")
      assert content == "Hello, World!"
    end

    test "write accepts iodata" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.write(vfs, "/test.txt", ["Hello", ", ", "World!"])
      {:ok, content} = InMemory.read(vfs, "/test.txt")
      assert content == "Hello, World!"
    end

    test "write overwrites existing file" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.write(vfs, "/test.txt", "first")
      {:ok, vfs} = InMemory.write(vfs, "/test.txt", "second")
      {:ok, content} = InMemory.read(vfs, "/test.txt")
      assert content == "second"
    end

    test "read non-existent file returns error" do
      vfs = InMemory.new()
      assert {:error, :file_not_found} = InMemory.read(vfs, "/missing.txt")
    end

    test "write to non-existent parent returns error" do
      vfs = InMemory.new()
      assert {:error, :parent_directory_not_found} = InMemory.write(vfs, "/missing/file.txt", "x")
    end

    test "write rejects invalid paths" do
      vfs = InMemory.new()
      assert {:error, :path_must_be_absolute} = InMemory.write(vfs, "relative.txt", "x")
      assert {:error, :path_traversal_not_allowed} = InMemory.write(vfs, "/../etc/passwd", "x")
    end
  end

  describe "mkdir/2" do
    test "creates a directory" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/foo")
      assert MapSet.member?(vfs.dirs, "/foo")
    end

    test "creates nested directory when parent exists" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/foo")
      {:ok, vfs} = InMemory.mkdir(vfs, "/foo/bar")
      assert MapSet.member?(vfs.dirs, "/foo/bar")
    end

    test "fails when parent doesn't exist" do
      vfs = InMemory.new()
      assert {:error, :parent_directory_not_found} = InMemory.mkdir(vfs, "/foo/bar")
    end

    test "fails when directory already exists" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/foo")
      assert {:error, :directory_exists} = InMemory.mkdir(vfs, "/foo")
    end
  end

  describe "list/2" do
    test "lists files in root" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.write(vfs, "/a.txt", "a")
      {:ok, vfs} = InMemory.write(vfs, "/b.txt", "b")
      {:ok, entries} = InMemory.list(vfs, "/")
      assert entries == ["a.txt", "b.txt"]
    end

    test "lists files and subdirectories" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/subdir")
      {:ok, vfs} = InMemory.write(vfs, "/file.txt", "x")
      {:ok, entries} = InMemory.list(vfs, "/")
      assert entries == ["file.txt", "subdir/"]
    end

    test "lists files in subdirectory" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/subdir")
      {:ok, vfs} = InMemory.write(vfs, "/subdir/file.txt", "x")
      {:ok, entries} = InMemory.list(vfs, "/subdir")
      assert entries == ["file.txt"]
    end

    test "returns error for non-existent directory" do
      vfs = InMemory.new()
      assert {:error, :directory_not_found} = InMemory.list(vfs, "/missing")
    end

    test "empty directory returns empty list" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/empty")
      {:ok, entries} = InMemory.list(vfs, "/empty")
      assert entries == []
    end
  end

  describe "delete/2" do
    test "deletes a file" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.write(vfs, "/test.txt", "x")
      {:ok, vfs} = InMemory.delete(vfs, "/test.txt")
      assert {:error, :file_not_found} = InMemory.read(vfs, "/test.txt")
    end

    test "deletes an empty directory" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/empty")
      {:ok, vfs} = InMemory.delete(vfs, "/empty")
      refute MapSet.member?(vfs.dirs, "/empty")
    end

    test "fails to delete non-empty directory" do
      vfs = InMemory.new()
      {:ok, vfs} = InMemory.mkdir(vfs, "/dir")
      {:ok, vfs} = InMemory.write(vfs, "/dir/file.txt", "x")
      assert {:error, :directory_not_empty} = InMemory.delete(vfs, "/dir")
    end

    test "fails to delete root" do
      vfs = InMemory.new()
      assert {:error, :cannot_delete_root} = InMemory.delete(vfs, "/")
    end

    test "fails to delete non-existent path" do
      vfs = InMemory.new()
      assert {:error, :not_found} = InMemory.delete(vfs, "/missing")
    end
  end
end
