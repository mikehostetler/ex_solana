defmodule JidoCode.Tools.Definitions.FileSystemTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}

  alias JidoCode.Tools.Definitions.FileSystem, as: Definitions

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Ensure application is started (Manager and registries)
    Application.ensure_all_started(:jido_code)

    # Clear registry for each test (persistent_term requires explicit clear)
    Registry.clear()

    # Register all file system tools
    for tool <- Definitions.all() do
      :ok = Registry.register(tool)
    end

    {:ok, project_root: tmp_dir}
  end

  describe "all/0" do
    test "returns all 10 file system tools" do
      tools = Definitions.all()
      assert length(tools) == 10

      names = Enum.map(tools, & &1.name)
      assert "read_file" in names
      assert "write_file" in names
      assert "edit_file" in names
      assert "multi_edit_file" in names
      assert "list_dir" in names
      assert "list_directory" in names
      assert "glob_search" in names
      assert "file_info" in names
      assert "create_directory" in names
      assert "delete_file" in names
    end
  end

  describe "tool definitions" do
    test "read_file has correct schema with offset and limit" do
      tool = Definitions.read_file()
      assert tool.name == "read_file"
      assert tool.description =~ "Read"
      assert length(tool.parameters) == 3

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      assert path_param.type == :string
      assert path_param.required == true

      offset_param = Enum.find(tool.parameters, &(&1.name == "offset"))
      assert offset_param.type == :integer
      assert offset_param.required == false
      assert offset_param.default == 1

      limit_param = Enum.find(tool.parameters, &(&1.name == "limit"))
      assert limit_param.type == :integer
      assert limit_param.required == false
      assert limit_param.default == 2000
    end

    test "write_file has correct schema" do
      tool = Definitions.write_file()
      assert tool.name == "write_file"
      assert length(tool.parameters) == 2

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      content_param = Enum.find(tool.parameters, &(&1.name == "content"))
      assert path_param.required == true
      assert content_param.required == true
    end

    test "list_directory has optional recursive param" do
      tool = Definitions.list_directory()
      assert tool.name == "list_directory"

      recursive_param = Enum.find(tool.parameters, &(&1.name == "recursive"))
      assert recursive_param.type == :boolean
      assert recursive_param.required == false
    end

    test "delete_file requires confirm param" do
      tool = Definitions.delete_file()
      confirm_param = Enum.find(tool.parameters, &(&1.name == "confirm"))
      assert confirm_param.type == :boolean
      assert confirm_param.required == true
    end
  end

  describe "executor integration" do
    test "read_file tool works via executor", %{project_root: project_root} do
      File.write!(Path.join(project_root, "test.txt"), "Hello, World!")

      tool_call = %{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "test.txt"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok
      assert result.content == "Hello, World!"
    end

    test "write_file tool works via executor", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "write_file",
        arguments: %{"path" => "new.txt", "content" => "New content"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok
      assert result.content =~ "written successfully"

      assert File.read!(Path.join(project_root, "new.txt")) == "New content"
    end

    test "list_directory tool works via executor", %{project_root: project_root} do
      File.write!(Path.join(project_root, "a.txt"), "")
      File.mkdir_p!(Path.join(project_root, "subdir"))

      tool_call = %{
        id: "call_123",
        name: "list_directory",
        arguments: %{"path" => ""}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      entries = Jason.decode!(result.content)
      names = Enum.map(entries, & &1["name"])
      assert "a.txt" in names
      assert "subdir" in names
    end

    test "file_info tool works via executor", %{project_root: project_root} do
      File.write!(Path.join(project_root, "info.txt"), "12345")

      tool_call = %{
        id: "call_123",
        name: "file_info",
        arguments: %{"path" => "info.txt"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      info = Jason.decode!(result.content)
      assert info["size"] == 5
      assert info["type"] == "regular"
    end

    test "create_directory tool works via executor", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "create_directory",
        arguments: %{"path" => "new_dir"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      assert File.dir?(Path.join(project_root, "new_dir"))
    end

    test "delete_file tool works via executor", %{project_root: project_root} do
      file_path = Path.join(project_root, "to_delete.txt")
      File.write!(file_path, "delete me")

      tool_call = %{
        id: "call_123",
        name: "delete_file",
        arguments: %{"path" => "to_delete.txt", "confirm" => true}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      refute File.exists?(file_path)
    end

    test "executor validates arguments", %{project_root: project_root} do
      # Missing required argument
      tool_call = %{
        id: "call_123",
        name: "read_file",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "executor rejects unknown parameters", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "test.txt", "unknown" => "param"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "unknown parameter"
    end

    test "results can be converted to LLM messages", %{project_root: project_root} do
      File.write!(Path.join(project_root, "test.txt"), "content")

      tool_call = %{
        id: "call_abc",
        name: "read_file",
        arguments: %{"path" => "test.txt"}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert message.content == "content"
    end
  end

  describe "batch execution" do
    test "executes multiple file operations", %{project_root: project_root} do
      tool_calls = [
        %{
          id: "call_1",
          name: "write_file",
          arguments: %{"path" => "file1.txt", "content" => "Content 1"}
        },
        %{
          id: "call_2",
          name: "write_file",
          arguments: %{"path" => "file2.txt", "content" => "Content 2"}
        }
      ]

      context = %{project_root: project_root}
      {:ok, results} = Executor.execute_batch(tool_calls, context: context)

      assert length(results) == 2
      assert Enum.all?(results, &(&1.status == :ok))

      assert File.read!(Path.join(project_root, "file1.txt")) == "Content 1"
      assert File.read!(Path.join(project_root, "file2.txt")) == "Content 2"
    end
  end
end
