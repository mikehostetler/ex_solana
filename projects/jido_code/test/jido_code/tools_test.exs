defmodule JidoCode.ToolsTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools
  alias JidoCode.Tools.Registry

  setup do
    Registry.clear()
    :ok
  end

  describe "register_all/0" do
    test "registers all built-in tools" do
      assert :ok = Tools.register_all()

      tools = Registry.list()
      tool_names = Enum.map(tools, & &1.name)

      # File system tools
      assert "read_file" in tool_names
      assert "write_file" in tool_names
      assert "edit_file" in tool_names
      assert "list_directory" in tool_names
      assert "file_info" in tool_names
      assert "create_directory" in tool_names
      assert "delete_file" in tool_names

      # Search tools
      assert "grep" in tool_names
      assert "find_files" in tool_names

      # Shell tools
      assert "run_command" in tool_names

      # Livebook tools
      assert "livebook_edit" in tool_names

      # Web tools
      assert "web_fetch" in tool_names
      assert "web_search" in tool_names

      # Todo tools
      assert "todo_write" in tool_names

      # Task tools
      assert "spawn_task" in tool_names

      # Verify total count (7 filesystem + 2 search + 1 shell + 1 livebook + 2 web + 1 todo + 1 task = 15)
      assert length(tools) >= 15
    end

    test "is idempotent - can be called multiple times" do
      assert :ok = Tools.register_all()
      assert :ok = Tools.register_all()

      # Should still have same number of tools
      tools = Registry.list()
      assert length(tools) >= 15
    end
  end

  describe "delegated functions" do
    test "list_tools/0 delegates to Registry.list/0" do
      Tools.register_all()
      assert is_list(Tools.list_tools())
      assert length(Tools.list_tools()) >= 15
    end

    test "get_tool/1 delegates to Registry.get/1" do
      Tools.register_all()
      assert {:ok, tool} = Tools.get_tool("read_file")
      assert tool.name == "read_file"
    end

    test "to_llm_format/0 delegates to Registry.to_llm_format/0" do
      Tools.register_all()
      llm_tools = Tools.to_llm_format()
      assert is_list(llm_tools)
      assert length(llm_tools) >= 15

      # Each tool should have OpenAI function format
      [first | _] = llm_tools
      assert first.type == "function"
      assert Map.has_key?(first.function, :name)
      assert Map.has_key?(first.function, :description)
    end
  end
end
