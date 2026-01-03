defmodule JidoCode.Tools.Definitions.FileMultiEditTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.FileMultiEdit
  alias JidoCode.Tools.{Param, Tool}

  describe "multi_edit_file/0" do
    test "returns a valid Tool struct" do
      tool = FileMultiEdit.multi_edit_file()
      assert %Tool{} = tool
    end

    test "has correct name" do
      tool = FileMultiEdit.multi_edit_file()
      assert tool.name == "multi_edit_file"
    end

    test "has descriptive description" do
      tool = FileMultiEdit.multi_edit_file()
      assert tool.description =~ "multiple edits"
      assert tool.description =~ "atomically"
      assert tool.description =~ "all succeed or all fail"
    end

    test "has correct handler" do
      tool = FileMultiEdit.multi_edit_file()
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.MultiEdit
    end

    test "has two parameters" do
      tool = FileMultiEdit.multi_edit_file()
      assert length(tool.parameters) == 2
    end

    test "path parameter is required string" do
      tool = FileMultiEdit.multi_edit_file()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert %Param{} = path_param
      assert path_param.type == :string
      assert path_param.required == true
      assert path_param.description =~ "Path"
    end

    test "edits parameter is required array" do
      tool = FileMultiEdit.multi_edit_file()
      edits_param = Enum.find(tool.parameters, &(&1.name == "edits"))

      assert %Param{} = edits_param
      assert edits_param.type == :array
      assert edits_param.required == true
      assert edits_param.description =~ "Array of edit objects"
    end

    test "edits parameter has object items type" do
      tool = FileMultiEdit.multi_edit_file()
      edits_param = Enum.find(tool.parameters, &(&1.name == "edits"))

      assert edits_param.items == :object
    end

    test "edits description mentions required fields" do
      tool = FileMultiEdit.multi_edit_file()
      edits_param = Enum.find(tool.parameters, &(&1.name == "edits"))

      assert edits_param.description =~ "old_string"
      assert edits_param.description =~ "new_string"
    end
  end

  describe "all/0" do
    test "returns list containing multi_edit_file tool" do
      tools = FileMultiEdit.all()
      assert length(tools) == 1
      assert [tool] = tools
      assert tool.name == "multi_edit_file"
    end
  end

  describe "LLM format conversion" do
    test "converts to valid OpenAI function format" do
      tool = FileMultiEdit.multi_edit_file()
      llm_format = Tool.to_llm_function(tool)

      assert llm_format.type == "function"
      assert llm_format.function.name == "multi_edit_file"
      assert is_binary(llm_format.function.description)

      params = llm_format.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "edits")
    end

    test "path and edits are in required list" do
      tool = FileMultiEdit.multi_edit_file()
      llm_format = Tool.to_llm_function(tool)

      required = llm_format.function.parameters.required
      assert "path" in required
      assert "edits" in required
    end

    test "edits property has array type" do
      tool = FileMultiEdit.multi_edit_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["edits"][:type] == "array"
    end

    test "all properties have correct types" do
      tool = FileMultiEdit.multi_edit_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["path"][:type] == "string"
      assert props["edits"][:type] == "array"
    end
  end

  describe "argument validation" do
    test "validates with valid edits array" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "path" => "test.txt",
        "edits" => [
          %{"old_string" => "hello", "new_string" => "world"},
          %{"old_string" => "foo", "new_string" => "bar"}
        ]
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with single edit" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "path" => "test.txt",
        "edits" => [
          %{"old_string" => "hello", "new_string" => "world"}
        ]
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with empty new_string (deletion)" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "path" => "test.txt",
        "edits" => [
          %{"old_string" => "delete me", "new_string" => ""}
        ]
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "rejects missing path" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "edits" => [
          %{"old_string" => "hello", "new_string" => "world"}
        ]
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "path"
    end

    test "rejects missing edits" do
      tool = FileMultiEdit.multi_edit_file()
      args = %{"path" => "test.txt"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "edits"
    end

    test "rejects invalid path type" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "path" => 123,
        "edits" => [%{"old_string" => "hello", "new_string" => "world"}]
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects invalid edits type" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "path" => "test.txt",
        "edits" => "not an array"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be an array"
    end

    test "rejects unknown parameters" do
      tool = FileMultiEdit.multi_edit_file()

      args = %{
        "path" => "test.txt",
        "edits" => [%{"old_string" => "hello", "new_string" => "world"}],
        "unknown" => "value"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "unknown parameter"
    end
  end

  describe "FileSystem delegation" do
    alias JidoCode.Tools.Definitions.FileSystem

    test "FileSystem.multi_edit_file/0 delegates correctly" do
      tool = FileSystem.multi_edit_file()
      assert tool.name == "multi_edit_file"
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.MultiEdit
    end

    test "FileSystem.all/0 includes multi_edit_file" do
      tools = FileSystem.all()
      names = Enum.map(tools, & &1.name)
      assert "multi_edit_file" in names
    end
  end
end
