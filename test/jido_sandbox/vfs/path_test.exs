defmodule JidoSandbox.VFS.PathTest do
  use ExUnit.Case

  alias JidoSandbox.VFS.Path

  describe "normalize/1" do
    test "accepts valid absolute paths" do
      assert {:ok, "/foo"} = Path.normalize("/foo")
      assert {:ok, "/foo/bar"} = Path.normalize("/foo/bar")
      assert {:ok, "/foo/bar/baz.txt"} = Path.normalize("/foo/bar/baz.txt")
    end

    test "normalizes root path" do
      assert {:ok, "/"} = Path.normalize("/")
    end

    test "collapses multiple slashes" do
      assert {:ok, "/foo/bar"} = Path.normalize("/foo//bar")
      assert {:ok, "/foo/bar"} = Path.normalize("//foo///bar//")
    end

    test "removes trailing slashes" do
      assert {:ok, "/foo"} = Path.normalize("/foo/")
      assert {:ok, "/foo/bar"} = Path.normalize("/foo/bar/")
    end

    test "rejects relative paths" do
      assert {:error, :path_must_be_absolute} = Path.normalize("foo")
      assert {:error, :path_must_be_absolute} = Path.normalize("foo/bar")
      assert {:error, :path_must_be_absolute} = Path.normalize("./foo")
    end

    test "rejects path traversal" do
      assert {:error, :path_traversal_not_allowed} = Path.normalize("/foo/../bar")
      assert {:error, :path_traversal_not_allowed} = Path.normalize("/foo/..")
      assert {:error, :path_traversal_not_allowed} = Path.normalize("/..")
    end

    test "rejects non-string input" do
      assert {:error, :invalid_path} = Path.normalize(123)
      assert {:error, :invalid_path} = Path.normalize(nil)
    end
  end

  describe "parent/1" do
    test "returns parent directory" do
      assert "/" == Path.parent("/foo")
      assert "/foo" == Path.parent("/foo/bar")
      assert "/foo/bar" == Path.parent("/foo/bar/baz.txt")
    end

    test "root returns itself" do
      assert "/" == Path.parent("/")
    end
  end

  describe "basename/1" do
    test "returns filename" do
      assert "foo" == Path.basename("/foo")
      assert "bar" == Path.basename("/foo/bar")
      assert "baz.txt" == Path.basename("/foo/bar/baz.txt")
    end

    test "root returns empty string" do
      assert "" == Path.basename("/")
    end
  end

  describe "direct_child?/2" do
    test "identifies direct children" do
      assert Path.direct_child?("/foo", "/")
      assert Path.direct_child?("/foo/bar", "/foo")
      assert Path.direct_child?("/foo/bar/baz", "/foo/bar")
    end

    test "rejects non-direct children" do
      refute Path.direct_child?("/foo/bar/baz", "/foo")
      refute Path.direct_child?("/foo/bar", "/")
    end
  end
end
