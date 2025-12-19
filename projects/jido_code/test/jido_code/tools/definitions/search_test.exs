defmodule JidoCode.Tools.Definitions.SearchTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}

  alias JidoCode.Tools.Definitions.Search, as: Definitions

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Clear and set up registry for each test
    Registry.clear()

    # Register all search tools
    for tool <- Definitions.all() do
      :ok = Registry.register(tool)
    end

    {:ok, project_root: tmp_dir}
  end

  describe "all/0" do
    test "returns both search tools" do
      tools = Definitions.all()
      assert length(tools) == 2

      names = Enum.map(tools, & &1.name)
      assert "grep" in names
      assert "find_files" in names
    end
  end

  describe "tool definitions" do
    test "grep has correct schema" do
      tool = Definitions.grep()
      assert tool.name == "grep"
      assert tool.description =~ "Search"
      assert length(tool.parameters) == 4

      pattern_param = Enum.find(tool.parameters, &(&1.name == "pattern"))
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      recursive_param = Enum.find(tool.parameters, &(&1.name == "recursive"))
      max_param = Enum.find(tool.parameters, &(&1.name == "max_results"))

      assert pattern_param.required == true
      assert path_param.required == true
      assert recursive_param.required == false
      assert max_param.required == false
    end

    test "find_files has correct schema" do
      tool = Definitions.find_files()
      assert tool.name == "find_files"
      assert tool.description =~ "Find"
      assert length(tool.parameters) == 3

      pattern_param = Enum.find(tool.parameters, &(&1.name == "pattern"))
      path_param = Enum.find(tool.parameters, &(&1.name == "path"))

      assert pattern_param.required == true
      assert path_param.required == false
    end
  end

  describe "executor integration" do
    test "grep tool works via executor", %{project_root: project_root} do
      File.write!(Path.join(project_root, "test.ex"), "defmodule Test do\nend")

      tool_call = %{
        id: "call_123",
        name: "grep",
        arguments: %{"pattern" => "defmodule", "path" => ""}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      matches = Jason.decode!(result.content)
      assert length(matches) == 1
      assert hd(matches)["file"] == "test.ex"
    end

    test "find_files tool works via executor", %{project_root: project_root} do
      File.mkdir_p!(Path.join(project_root, "lib"))
      File.write!(Path.join(project_root, "lib/main.ex"), "")
      File.write!(Path.join(project_root, "lib/helper.ex"), "")

      tool_call = %{
        id: "call_123",
        name: "find_files",
        arguments: %{"pattern" => "*.ex"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      files = Jason.decode!(result.content)
      assert length(files) == 2
    end

    test "executor validates arguments", %{project_root: project_root} do
      # Missing required argument
      tool_call = %{
        id: "call_123",
        name: "grep",
        arguments: %{"pattern" => "test"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "results can be converted to LLM messages", %{project_root: project_root} do
      File.write!(Path.join(project_root, "test.ex"), "hello")

      tool_call = %{
        id: "call_abc",
        name: "grep",
        arguments: %{"pattern" => "hello", "path" => ""}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert is_binary(message.content)
    end
  end

  describe "batch execution" do
    test "executes multiple search operations", %{project_root: project_root} do
      File.write!(Path.join(project_root, "a.ex"), "def foo")
      File.write!(Path.join(project_root, "b.ex"), "def bar")

      tool_calls = [
        %{
          id: "call_1",
          name: "grep",
          arguments: %{"pattern" => "def foo", "path" => ""}
        },
        %{
          id: "call_2",
          name: "find_files",
          arguments: %{"pattern" => "*.ex"}
        }
      ]

      context = %{project_root: project_root}
      {:ok, results} = Executor.execute_batch(tool_calls, context: context)

      assert length(results) == 2
      assert Enum.all?(results, &(&1.status == :ok))
    end
  end
end
