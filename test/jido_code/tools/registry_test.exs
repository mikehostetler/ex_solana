defmodule JidoCode.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Registry, Tool}

  # Mock handler for testing
  defmodule MockHandler do
    def execute(_params, _context), do: {:ok, "result"}
  end

  setup do
    # Clear registry before each test (safe - ignore if GenServer not available)
    try do
      Registry.clear()
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  describe "register/1" do
    test "registers a valid tool" do
      {:ok, tool} = create_tool("read_file", "Read a file")

      assert :ok = Registry.register(tool)
      assert {:ok, ^tool} = Registry.get("read_file")
    end

    test "returns error for duplicate registration" do
      {:ok, tool} = create_tool("read_file", "Read a file")

      assert :ok = Registry.register(tool)
      assert {:error, :already_registered} = Registry.register(tool)
    end

    test "returns error for invalid tool" do
      assert {:error, :invalid_tool} = Registry.register("not a tool")
      assert {:error, :invalid_tool} = Registry.register(%{name: "bad"})
    end

    test "registers multiple tools" do
      {:ok, tool1} = create_tool("read_file", "Read a file")
      {:ok, tool2} = create_tool("write_file", "Write a file")
      {:ok, tool3} = create_tool("list_files", "List files")

      assert :ok = Registry.register(tool1)
      assert :ok = Registry.register(tool2)
      assert :ok = Registry.register(tool3)

      assert Registry.count() == 3
    end
  end

  describe "unregister/1" do
    test "unregisters an existing tool" do
      {:ok, tool} = create_tool("read_file", "Read a file")
      :ok = Registry.register(tool)

      assert :ok = Registry.unregister("read_file")
      assert {:error, :not_found} = Registry.get("read_file")
    end

    test "returns error for non-existent tool" do
      assert {:error, :not_found} = Registry.unregister("unknown")
    end
  end

  describe "list/0" do
    test "returns empty list when no tools registered" do
      assert Registry.list() == []
    end

    test "returns all registered tools sorted by name" do
      {:ok, tool1} = create_tool("write_file", "Write a file")
      {:ok, tool2} = create_tool("read_file", "Read a file")
      {:ok, tool3} = create_tool("find_files", "Find files")

      :ok = Registry.register(tool1)
      :ok = Registry.register(tool2)
      :ok = Registry.register(tool3)

      tools = Registry.list()
      names = Enum.map(tools, & &1.name)

      assert names == ["find_files", "read_file", "write_file"]
    end
  end

  describe "get/1" do
    test "returns tool when it exists" do
      {:ok, tool} = create_tool("read_file", "Read a file")
      :ok = Registry.register(tool)

      assert {:ok, found} = Registry.get("read_file")
      assert found.name == "read_file"
      assert found.description == "Read a file"
    end

    test "returns error when tool not found" do
      assert {:error, :not_found} = Registry.get("unknown")
    end
  end

  describe "registered?/1" do
    test "returns true for registered tool" do
      {:ok, tool} = create_tool("read_file", "Read a file")
      :ok = Registry.register(tool)

      assert Registry.registered?("read_file") == true
    end

    test "returns false for unregistered tool" do
      assert Registry.registered?("unknown") == false
    end
  end

  describe "count/0" do
    test "returns 0 when empty" do
      assert Registry.count() == 0
    end

    test "returns correct count" do
      {:ok, tool1} = create_tool("tool1", "Tool 1")
      {:ok, tool2} = create_tool("tool2", "Tool 2")

      :ok = Registry.register(tool1)
      assert Registry.count() == 1

      :ok = Registry.register(tool2)
      assert Registry.count() == 2
    end
  end

  describe "clear/0" do
    test "removes all tools" do
      {:ok, tool1} = create_tool("tool1", "Tool 1")
      {:ok, tool2} = create_tool("tool2", "Tool 2")

      :ok = Registry.register(tool1)
      :ok = Registry.register(tool2)
      assert Registry.count() == 2

      :ok = Registry.clear()
      assert Registry.count() == 0
      assert Registry.list() == []
    end
  end

  describe "to_llm_format/0" do
    test "returns empty list when no tools" do
      assert Registry.to_llm_format() == []
    end

    test "returns LLM-compatible format for all tools" do
      {:ok, tool} =
        Tool.new(%{
          name: "read_file",
          description: "Read file contents",
          handler: MockHandler,
          parameters: [
            %{name: "path", type: :string, description: "File path", required: true}
          ]
        })

      :ok = Registry.register(tool)

      [func] = Registry.to_llm_format()

      assert func.type == "function"
      assert func.function.name == "read_file"
      assert func.function.description == "Read file contents"
      assert func.function.parameters.type == "object"
      assert func.function.parameters.properties["path"].type == "string"
      assert func.function.parameters.required == ["path"]
    end

    test "returns multiple tools in LLM format" do
      {:ok, tool1} = create_tool("read_file", "Read a file")
      {:ok, tool2} = create_tool("write_file", "Write a file")

      :ok = Registry.register(tool1)
      :ok = Registry.register(tool2)

      funcs = Registry.to_llm_format()

      assert length(funcs) == 2
      names = Enum.map(funcs, & &1.function.name)
      assert "read_file" in names
      assert "write_file" in names
    end
  end

  describe "to_text_description/0" do
    test "returns message when no tools" do
      assert Registry.to_text_description() == "No tools available."
    end

    test "returns formatted description" do
      {:ok, tool} =
        Tool.new(%{
          name: "read_file",
          description: "Read the contents of a file",
          handler: MockHandler,
          parameters: [
            %{name: "path", type: :string, description: "File path", required: true},
            %{name: "encoding", type: :string, description: "File encoding", required: false}
          ]
        })

      :ok = Registry.register(tool)

      desc = Registry.to_text_description()

      assert desc =~ "## read_file"
      assert desc =~ "Read the contents of a file"
      assert desc =~ "path: string (required)"
      assert desc =~ "encoding: string (optional)"
    end
  end

  # Helper to create a simple tool
  defp create_tool(name, description) do
    Tool.new(%{
      name: name,
      description: description,
      handler: MockHandler
    })
  end
end
