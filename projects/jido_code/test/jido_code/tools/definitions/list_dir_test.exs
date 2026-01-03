defmodule JidoCode.Tools.Definitions.ListDirTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.ListDir
  alias JidoCode.Tools.{Param, Tool}

  describe "list_dir/0" do
    test "returns a valid Tool struct" do
      tool = ListDir.list_dir()
      assert %Tool{} = tool
    end

    test "has correct name" do
      tool = ListDir.list_dir()
      assert tool.name == "list_dir"
    end

    test "has descriptive description" do
      tool = ListDir.list_dir()
      assert tool.description =~ "List directory"
      assert tool.description =~ "type"
    end

    test "has correct handler" do
      tool = ListDir.list_dir()
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.ListDir
    end

    test "has two parameters" do
      tool = ListDir.list_dir()
      assert length(tool.parameters) == 2
    end

    test "path parameter is required string" do
      tool = ListDir.list_dir()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert %Param{} = path_param
      assert path_param.type == :string
      assert path_param.required == true
      assert path_param.description =~ "Path"
    end

    test "ignore_patterns parameter is optional array" do
      tool = ListDir.list_dir()
      patterns_param = Enum.find(tool.parameters, &(&1.name == "ignore_patterns"))

      assert %Param{} = patterns_param
      assert patterns_param.type == :array
      assert patterns_param.required == false
    end

    test "ignore_patterns has string items type" do
      tool = ListDir.list_dir()
      patterns_param = Enum.find(tool.parameters, &(&1.name == "ignore_patterns"))

      assert patterns_param.items == :string
    end

    test "ignore_patterns description mentions glob patterns" do
      tool = ListDir.list_dir()
      patterns_param = Enum.find(tool.parameters, &(&1.name == "ignore_patterns"))

      assert patterns_param.description =~ "Glob patterns"
    end
  end

  describe "all/0" do
    test "returns list containing list_dir tool" do
      tools = ListDir.all()
      assert length(tools) == 1
      assert [tool] = tools
      assert tool.name == "list_dir"
    end
  end

  describe "LLM format conversion" do
    test "converts to valid OpenAI function format" do
      tool = ListDir.list_dir()
      llm_format = Tool.to_llm_function(tool)

      assert llm_format.type == "function"
      assert llm_format.function.name == "list_dir"
      assert is_binary(llm_format.function.description)

      params = llm_format.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "path")
      assert Map.has_key?(params.properties, "ignore_patterns")
    end

    test "only path is in required list" do
      tool = ListDir.list_dir()
      llm_format = Tool.to_llm_function(tool)

      required = llm_format.function.parameters.required
      assert "path" in required
      refute "ignore_patterns" in required
    end

    test "ignore_patterns property has array type" do
      tool = ListDir.list_dir()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["ignore_patterns"][:type] == "array"
    end

    test "all properties have correct types" do
      tool = ListDir.list_dir()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["path"][:type] == "string"
      assert props["ignore_patterns"][:type] == "array"
    end
  end

  describe "argument validation" do
    test "validates with path only" do
      tool = ListDir.list_dir()
      args = %{"path" => "lib"}
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with path and ignore_patterns" do
      tool = ListDir.list_dir()
      args = %{
        "path" => "lib",
        "ignore_patterns" => ["*.log", "node_modules"]
      }
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with empty ignore_patterns array" do
      tool = ListDir.list_dir()
      args = %{
        "path" => "lib",
        "ignore_patterns" => []
      }
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with single ignore pattern" do
      tool = ListDir.list_dir()
      args = %{
        "path" => ".",
        "ignore_patterns" => ["*.test.js"]
      }
      assert :ok = Tool.validate_args(tool, args)
    end

    test "rejects missing path" do
      tool = ListDir.list_dir()
      args = %{"ignore_patterns" => ["*.log"]}

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "path"
    end

    test "rejects invalid path type" do
      tool = ListDir.list_dir()
      args = %{"path" => 123}

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects invalid ignore_patterns type" do
      tool = ListDir.list_dir()
      args = %{
        "path" => "lib",
        "ignore_patterns" => "not an array"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be an array"
    end

    test "rejects unknown parameters" do
      tool = ListDir.list_dir()
      args = %{
        "path" => "lib",
        "unknown" => "value"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "unknown parameter"
    end
  end

  describe "FileSystem delegation" do
    alias JidoCode.Tools.Definitions.FileSystem

    test "FileSystem.list_dir/0 delegates correctly" do
      tool = FileSystem.list_dir()
      assert tool.name == "list_dir"
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.ListDir
    end

    test "FileSystem.all/0 includes list_dir" do
      tools = FileSystem.all()
      names = Enum.map(tools, & &1.name)
      assert "list_dir" in names
    end

    test "FileSystem.all/0 has correct count after adding list_dir" do
      tools = FileSystem.all()
      # Should have: read_file, write_file, edit_file, multi_edit_file, list_dir,
      #              list_directory, glob_search, file_info, create_directory, delete_file
      assert length(tools) == 10
    end
  end
end
