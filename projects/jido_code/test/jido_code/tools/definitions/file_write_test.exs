defmodule JidoCode.Tools.Definitions.FileWriteTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.FileWrite
  alias JidoCode.Tools.Handlers.FileSystem.WriteFile
  alias JidoCode.Tools.{Param, Tool}

  describe "write_file/0" do
    test "returns a valid Tool struct" do
      tool = FileWrite.write_file()
      assert %Tool{} = tool
    end

    test "has correct name" do
      tool = FileWrite.write_file()
      assert tool.name == "write_file"
    end

    test "has descriptive description" do
      tool = FileWrite.write_file()
      assert tool.description =~ "Write content to a file"
      assert tool.description =~ "Existing files must be read first"
    end

    test "has correct handler" do
      tool = FileWrite.write_file()
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.WriteFile
    end

    test "has two parameters" do
      tool = FileWrite.write_file()
      assert length(tool.parameters) == 2
    end

    test "path parameter is required string" do
      tool = FileWrite.write_file()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert %Param{} = path_param
      assert path_param.type == :string
      assert path_param.required == true
      assert path_param.description =~ "Path"
    end

    test "content parameter is required string" do
      tool = FileWrite.write_file()
      content_param = Enum.find(tool.parameters, &(&1.name == "content"))

      assert %Param{} = content_param
      assert content_param.type == :string
      assert content_param.required == true
      assert content_param.description =~ "Content"
    end
  end

  describe "all/0" do
    test "returns list containing write_file tool" do
      tools = FileWrite.all()
      assert length(tools) == 1
      assert [tool] = tools
      assert tool.name == "write_file"
    end
  end

  describe "WriteFile.max_file_size/0" do
    test "returns 10MB in bytes" do
      # 10MB = 10 * 1024 * 1024 bytes
      assert WriteFile.max_file_size() == 10 * 1024 * 1024
    end
  end

  describe "LLM format conversion" do
    test "converts to valid OpenAI function format" do
      tool = FileWrite.write_file()
      llm_format = Tool.to_llm_function(tool)

      assert llm_format.type == "function"
      assert llm_format.function.name == "write_file"
      assert is_binary(llm_format.function.description)

      params = llm_format.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "content")
    end

    test "both path and content are in required list" do
      tool = FileWrite.write_file()
      llm_format = Tool.to_llm_function(tool)

      required = llm_format.function.parameters.required
      assert "path" in required
      assert "content" in required
    end

    test "all properties have correct types" do
      tool = FileWrite.write_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["path"][:type] == "string"
      assert props["content"][:type] == "string"
    end
  end

  describe "argument validation" do
    test "validates with path and content" do
      tool = FileWrite.write_file()
      assert :ok = Tool.validate_args(tool, %{"path" => "test.txt", "content" => "hello"})
    end

    test "validates with empty content" do
      tool = FileWrite.write_file()
      assert :ok = Tool.validate_args(tool, %{"path" => "test.txt", "content" => ""})
    end

    test "rejects missing path" do
      tool = FileWrite.write_file()
      assert {:error, msg} = Tool.validate_args(tool, %{"content" => "hello"})
      assert msg =~ "missing required parameter"
      assert msg =~ "path"
    end

    test "rejects missing content" do
      tool = FileWrite.write_file()
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => "test.txt"})
      assert msg =~ "missing required parameter"
      assert msg =~ "content"
    end

    test "rejects invalid path type" do
      tool = FileWrite.write_file()
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => 123, "content" => "hello"})
      assert msg =~ "must be a string"
    end

    test "rejects invalid content type" do
      tool = FileWrite.write_file()
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => "test.txt", "content" => 123})
      assert msg =~ "must be a string"
    end

    test "rejects unknown parameters" do
      tool = FileWrite.write_file()
      args = %{"path" => "test.txt", "content" => "hello", "unknown" => "value"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "unknown parameter"
    end
  end
end
