defmodule JidoSandbox.SchemasTest do
  use ExUnit.Case

  alias JidoSandbox.Schemas

  describe "validate_path/1" do
    test "accepts valid absolute paths" do
      assert {:ok, "/foo"} = Schemas.validate_path("/foo")
      assert {:ok, "/foo/bar"} = Schemas.validate_path("/foo/bar")
      assert {:ok, "/"} = Schemas.validate_path("/")
    end

    test "rejects relative paths" do
      assert {:error, _} = Schemas.validate_path("foo")
      assert {:error, _} = Schemas.validate_path("foo/bar")
    end

    test "rejects path traversal" do
      assert {:error, _} = Schemas.validate_path("/foo/../bar")
      assert {:error, _} = Schemas.validate_path("/..")
    end

    test "rejects empty paths" do
      assert {:error, _} = Schemas.validate_path("")
    end
  end

  describe "validate_write/1" do
    test "accepts valid write params" do
      params = %{"path" => "/test.txt", "content" => "hello"}
      assert {:ok, ^params} = Schemas.validate_write(params)
    end

    test "rejects missing path" do
      params = %{"content" => "hello"}
      assert {:error, _} = Schemas.validate_write(params)
    end

    test "rejects missing content" do
      params = %{"path" => "/test.txt"}
      assert {:error, _} = Schemas.validate_write(params)
    end

    test "rejects invalid path" do
      params = %{"path" => "relative.txt", "content" => "hello"}
      assert {:error, _} = Schemas.validate_write(params)
    end
  end

  describe "validate_read/1" do
    test "accepts valid read params" do
      params = %{"path" => "/test.txt"}
      assert {:ok, ^params} = Schemas.validate_read(params)
    end

    test "rejects missing path" do
      assert {:error, _} = Schemas.validate_read(%{})
    end
  end

  describe "validate_list/1" do
    test "accepts valid list params" do
      params = %{"path" => "/"}
      assert {:ok, ^params} = Schemas.validate_list(params)
    end
  end

  describe "validate_delete/1" do
    test "accepts valid delete params" do
      params = %{"path" => "/test.txt"}
      assert {:ok, ^params} = Schemas.validate_delete(params)
    end
  end

  describe "validate_mkdir/1" do
    test "accepts valid mkdir params" do
      params = %{"path" => "/newdir"}
      assert {:ok, ^params} = Schemas.validate_mkdir(params)
    end
  end

  describe "validate_eval_lua/1" do
    test "accepts valid eval_lua params" do
      params = %{"code" => "return 1 + 1"}
      assert {:ok, ^params} = Schemas.validate_eval_lua(params)
    end

    test "rejects empty code" do
      params = %{"code" => ""}
      assert {:error, _} = Schemas.validate_eval_lua(params)
    end

    test "rejects missing code" do
      assert {:error, _} = Schemas.validate_eval_lua(%{})
    end
  end
end
