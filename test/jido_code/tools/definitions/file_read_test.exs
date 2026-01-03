defmodule JidoCode.Tools.Definitions.FileReadTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.FileRead
  alias JidoCode.Tools.{Param, Tool}

  describe "default_limit/0" do
    test "returns 2000" do
      assert FileRead.default_limit() == 2000
    end
  end

  describe "read_file/0" do
    test "returns a valid Tool struct" do
      tool = FileRead.read_file()
      assert %Tool{} = tool
    end

    test "has correct name" do
      tool = FileRead.read_file()
      assert tool.name == "read_file"
    end

    test "has descriptive description" do
      tool = FileRead.read_file()
      assert tool.description =~ "Read file contents"
      assert tool.description =~ "line numbers"
      assert tool.description =~ "2000"
    end

    test "has correct handler" do
      tool = FileRead.read_file()
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.ReadFile
    end

    test "has three parameters" do
      tool = FileRead.read_file()
      assert length(tool.parameters) == 3
    end

    test "path parameter is required string" do
      tool = FileRead.read_file()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert %Param{} = path_param
      assert path_param.type == :string
      assert path_param.required == true
      assert path_param.description =~ "Path"
    end

    test "offset parameter is optional integer with default 1" do
      tool = FileRead.read_file()
      offset_param = Enum.find(tool.parameters, &(&1.name == "offset"))

      assert %Param{} = offset_param
      assert offset_param.type == :integer
      assert offset_param.required == false
      assert offset_param.default == 1
      assert offset_param.description =~ "1-indexed"
    end

    test "limit parameter is optional integer with default 2000" do
      tool = FileRead.read_file()
      limit_param = Enum.find(tool.parameters, &(&1.name == "limit"))

      assert %Param{} = limit_param
      assert limit_param.type == :integer
      assert limit_param.required == false
      assert limit_param.default == 2000
      assert limit_param.description =~ "Maximum"
    end
  end

  describe "all/0" do
    test "returns list containing read_file tool" do
      tools = FileRead.all()
      assert length(tools) == 1
      assert [tool] = tools
      assert tool.name == "read_file"
    end
  end

  describe "LLM format conversion" do
    test "converts to valid OpenAI function format" do
      tool = FileRead.read_file()
      llm_format = Tool.to_llm_function(tool)

      assert llm_format.type == "function"
      assert llm_format.function.name == "read_file"
      assert is_binary(llm_format.function.description)

      params = llm_format.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "offset")
      assert Map.has_key?(params.properties, "limit")
    end

    test "only path is in required list" do
      tool = FileRead.read_file()
      llm_format = Tool.to_llm_function(tool)

      required = llm_format.function.parameters.required
      assert required == ["path"]
    end

    test "offset and limit have defaults in JSON schema" do
      tool = FileRead.read_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["offset"][:default] == 1
      assert props["limit"][:default] == 2000
    end

    test "all properties have correct types" do
      tool = FileRead.read_file()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["path"][:type] == "string"
      assert props["offset"][:type] == "integer"
      assert props["limit"][:type] == "integer"
    end
  end

  describe "argument validation" do
    test "validates with only path" do
      tool = FileRead.read_file()
      assert :ok = Tool.validate_args(tool, %{"path" => "test.txt"})
    end

    test "validates with all parameters" do
      tool = FileRead.read_file()

      args = %{
        "path" => "test.txt",
        "offset" => 10,
        "limit" => 100
      }

      assert :ok = Tool.validate_args(tool, args)
    end

    test "rejects missing path" do
      tool = FileRead.read_file()
      assert {:error, msg} = Tool.validate_args(tool, %{})
      assert msg =~ "missing required parameter"
      assert msg =~ "path"
    end

    test "rejects invalid path type" do
      tool = FileRead.read_file()
      assert {:error, msg} = Tool.validate_args(tool, %{"path" => 123})
      assert msg =~ "must be a string"
    end

    test "rejects invalid offset type" do
      tool = FileRead.read_file()
      args = %{"path" => "test.txt", "offset" => "not an int"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be an integer"
    end

    test "rejects invalid limit type" do
      tool = FileRead.read_file()
      args = %{"path" => "test.txt", "limit" => "not an int"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be an integer"
    end

    test "rejects unknown parameters" do
      tool = FileRead.read_file()
      args = %{"path" => "test.txt", "unknown" => "value"}
      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "unknown parameter"
    end
  end
end
