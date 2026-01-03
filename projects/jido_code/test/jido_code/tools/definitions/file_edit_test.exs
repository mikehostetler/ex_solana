defmodule JidoCode.Tools.Definitions.FileEditTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.FileEdit
  alias JidoCode.Tools.{Param, Tool}

  describe "edit_file/0" do
    test "returns a valid Tool struct" do
      tool = FileEdit.edit_file()
      assert %Tool{} = tool
    end

    test "has correct name" do
      tool = FileEdit.edit_file()
      assert tool.name == "edit_file"
    end

    test "has descriptive description" do
      tool = FileEdit.edit_file()
      assert tool.description =~ "Edit a file"
      assert tool.description =~ "old_string"
      assert tool.description =~ "new_string"
      assert tool.description =~ "unique"
    end

    test "has correct handler" do
      tool = FileEdit.edit_file()
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.EditFile
    end

    test "has four parameters" do
      tool = FileEdit.edit_file()
      assert length(tool.parameters) == 4
    end

    test "path parameter is required string" do
      tool = FileEdit.edit_file()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert %Param{} = path_param
      assert path_param.type == :string
      assert path_param.required == true
      assert path_param.description =~ "Path"
    end

    test "old_string parameter is required string" do
      tool = FileEdit.edit_file()
      old_string_param = Enum.find(tool.parameters, &(&1.name == "old_string"))

      assert %Param{} = old_string_param
      assert old_string_param.type == :string
      assert old_string_param.required == true
      assert old_string_param.description =~ "Exact text to find"
    end

    test "new_string parameter is required string" do
      tool = FileEdit.edit_file()
      new_string_param = Enum.find(tool.parameters, &(&1.name == "new_string"))

      assert %Param{} = new_string_param
      assert new_string_param.type == :string
      assert new_string_param.required == true
      assert new_string_param.description =~ "Replacement"
    end

    test "replace_all parameter is optional boolean with default false" do
      tool = FileEdit.edit_file()
      replace_all_param = Enum.find(tool.parameters, &(&1.name == "replace_all"))

      assert %Param{} = replace_all_param
      assert replace_all_param.type == :boolean
      assert replace_all_param.required == false
      assert replace_all_param.default == false
    end
  end

  describe "all/0" do
    test "returns list containing edit_file tool" do
      tools = FileEdit.all()
      assert length(tools) == 1
      assert [tool] = tools
      assert tool.name == "edit_file"
    end
  end

  describe "LLM format conversion" do
    test "converts to valid OpenAI function format" do
      tool = FileEdit.edit_file()
      llm_format = Tool.to_llm_function(tool)

      assert llm_format.type == "function"
      assert llm_format.function.name == "edit_file"
      assert is_binary(llm_format.function.description)

      params = llm_format.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "old_string")
      assert Map.has_key?(params.properties, "new_string")
      assert Map.has_key?(params.properties, "replace_all")
    end

    test "path, old_string, and new_string are in required list" do
      tool = FileEdit.edit_file()
      llm_format = Tool.to_llm_function(tool)

      required = llm_format.function.parameters.required
      assert "path" in required
      assert "old_string" in required
      assert "new_string" in required
      refute "replace_all" in required
    end

    test "replace_all has default value in JSON schema" do
      tool = FileEdit.edit_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["replace_all"][:default] == false
    end

    test "all properties have correct types" do
      tool = FileEdit.edit_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["path"][:type] == "string"
      assert props["old_string"][:type] == "string"
      assert props["new_string"][:type] == "string"
      assert props["replace_all"][:type] == "boolean"
    end
  end

  describe "argument validation" do
    test "validates with required parameters only" do
      tool = FileEdit.edit_file()

      args = %{
        "path" => "test.txt",
        "old_string" => "hello",
        "new_string" => "world"
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with all parameters" do
      tool = FileEdit.edit_file()

      args = %{
        "path" => "test.txt",
        "old_string" => "hello",
        "new_string" => "world",
        "replace_all" => true
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with empty new_string (deletion)" do
      tool = FileEdit.edit_file()

      args = %{
        "path" => "test.txt",
        "old_string" => "delete me",
        "new_string" => ""
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "rejects missing path" do
      tool = FileEdit.edit_file()
      args = %{"old_string" => "hello", "new_string" => "world"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "path"
    end

    test "rejects missing old_string" do
      tool = FileEdit.edit_file()
      args = %{"path" => "test.txt", "new_string" => "world"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "old_string"
    end

    test "rejects missing new_string" do
      tool = FileEdit.edit_file()
      args = %{"path" => "test.txt", "old_string" => "hello"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "new_string"
    end

    test "rejects invalid path type" do
      tool = FileEdit.edit_file()
      args = %{"path" => 123, "old_string" => "hello", "new_string" => "world"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects invalid old_string type" do
      tool = FileEdit.edit_file()
      args = %{"path" => "test.txt", "old_string" => 123, "new_string" => "world"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects invalid new_string type" do
      tool = FileEdit.edit_file()
      args = %{"path" => "test.txt", "old_string" => "hello", "new_string" => 123}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects invalid replace_all type" do
      tool = FileEdit.edit_file()

      args = %{
        "path" => "test.txt",
        "old_string" => "hello",
        "new_string" => "world",
        "replace_all" => "yes"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a boolean"
    end

    test "rejects unknown parameters" do
      tool = FileEdit.edit_file()

      args = %{
        "path" => "test.txt",
        "old_string" => "hello",
        "new_string" => "world",
        "unknown" => "value"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "unknown parameter"
    end
  end
end
