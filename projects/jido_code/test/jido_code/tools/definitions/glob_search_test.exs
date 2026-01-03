defmodule JidoCode.Tools.Definitions.GlobSearchTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Definitions.GlobSearch
  alias JidoCode.Tools.{Param, Tool}

  describe "glob_search/0" do
    test "returns a valid Tool struct" do
      tool = GlobSearch.glob_search()
      assert %Tool{} = tool
    end

    test "has correct name" do
      tool = GlobSearch.glob_search()
      assert tool.name == "glob_search"
    end

    test "has descriptive description" do
      tool = GlobSearch.glob_search()
      assert tool.description =~ "Find files"
      assert tool.description =~ "glob pattern"
    end

    test "description mentions supported patterns" do
      tool = GlobSearch.glob_search()
      assert tool.description =~ "**"
      assert tool.description =~ "*"
    end

    test "has correct handler" do
      tool = GlobSearch.glob_search()
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.GlobSearch
    end

    test "has two parameters" do
      tool = GlobSearch.glob_search()
      assert length(tool.parameters) == 2
    end

    test "pattern parameter is required string" do
      tool = GlobSearch.glob_search()
      pattern_param = Enum.find(tool.parameters, &(&1.name == "pattern"))

      assert %Param{} = pattern_param
      assert pattern_param.type == :string
      assert pattern_param.required == true
      assert pattern_param.description =~ "Glob pattern"
    end

    test "pattern description includes examples" do
      tool = GlobSearch.glob_search()
      pattern_param = Enum.find(tool.parameters, &(&1.name == "pattern"))

      assert pattern_param.description =~ "**/*.ex"
    end

    test "path parameter is optional string" do
      tool = GlobSearch.glob_search()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert %Param{} = path_param
      assert path_param.type == :string
      assert path_param.required == false
    end

    test "path description mentions default" do
      tool = GlobSearch.glob_search()
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert path_param.description =~ "default"
    end
  end

  describe "all/0" do
    test "returns list containing glob_search tool" do
      tools = GlobSearch.all()
      assert length(tools) == 1
      assert [tool] = tools
      assert tool.name == "glob_search"
    end
  end

  describe "LLM format conversion" do
    test "converts to valid OpenAI function format" do
      tool = GlobSearch.glob_search()
      llm_format = Tool.to_llm_function(tool)

      assert llm_format.type == "function"
      assert llm_format.function.name == "glob_search"
      assert is_binary(llm_format.function.description)

      params = llm_format.function.parameters
      assert params.type == "object"
      assert Map.has_key?(params.properties, "pattern")
      assert Map.has_key?(params.properties, "path")
    end

    test "only pattern is in required list" do
      tool = GlobSearch.glob_search()
      llm_format = Tool.to_llm_function(tool)

      required = llm_format.function.parameters.required
      assert "pattern" in required
      refute "path" in required
    end

    test "all properties have correct types" do
      tool = GlobSearch.glob_search()
      llm_format = Tool.to_llm_function(tool)

      props = llm_format.function.parameters.properties
      assert props["pattern"][:type] == "string"
      assert props["path"][:type] == "string"
    end
  end

  describe "argument validation" do
    test "validates with pattern only" do
      tool = GlobSearch.glob_search()
      args = %{"pattern" => "**/*.ex"}
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with pattern and path" do
      tool = GlobSearch.glob_search()
      args = %{
        "pattern" => "**/*.ex",
        "path" => "lib"
      }
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with simple wildcard pattern" do
      tool = GlobSearch.glob_search()
      args = %{"pattern" => "*.ex"}
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with brace expansion pattern" do
      tool = GlobSearch.glob_search()
      args = %{"pattern" => "{lib,test}/**/*.ex"}
      assert :ok = Tool.validate_args(tool, args)
    end

    test "validates with multiple extension pattern" do
      tool = GlobSearch.glob_search()
      args = %{"pattern" => "**/*.{ex,exs}"}
      assert :ok = Tool.validate_args(tool, args)
    end

    test "rejects missing pattern" do
      tool = GlobSearch.glob_search()
      args = %{"path" => "lib"}

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "missing required parameter"
      assert msg =~ "pattern"
    end

    test "rejects invalid pattern type" do
      tool = GlobSearch.glob_search()
      args = %{"pattern" => 123}

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects invalid path type" do
      tool = GlobSearch.glob_search()
      args = %{
        "pattern" => "**/*.ex",
        "path" => 123
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "must be a string"
    end

    test "rejects unknown parameters" do
      tool = GlobSearch.glob_search()
      args = %{
        "pattern" => "**/*.ex",
        "unknown" => "value"
      }

      assert {:error, msg} = Tool.validate_args(tool, args)
      assert msg =~ "unknown parameter"
    end
  end

  describe "FileSystem delegation" do
    alias JidoCode.Tools.Definitions.FileSystem

    test "FileSystem.glob_search/0 delegates correctly" do
      tool = FileSystem.glob_search()
      assert tool.name == "glob_search"
      assert tool.handler == JidoCode.Tools.Handlers.FileSystem.GlobSearch
    end

    test "FileSystem.all/0 includes glob_search" do
      tools = FileSystem.all()
      names = Enum.map(tools, & &1.name)
      assert "glob_search" in names
    end

    test "FileSystem.all/0 has correct count after adding glob_search" do
      tools = FileSystem.all()
      # Should have: read_file, write_file, edit_file, multi_edit_file, list_dir,
      #              list_directory, glob_search, file_info, create_directory, delete_file
      assert length(tools) == 10
    end
  end
end
