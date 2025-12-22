defmodule JidoCode.Livebook.ParserTest do
  use ExUnit.Case, async: true

  alias JidoCode.Livebook.{Cell, Notebook, Parser}

  describe "parse/1" do
    test "parses simple markdown" do
      content = "# Hello World\n\nThis is markdown."

      assert {:ok, notebook} = Parser.parse(content)
      assert length(notebook.cells) == 1
      assert hd(notebook.cells).type == :markdown
      assert hd(notebook.cells).content =~ "Hello World"
    end

    test "parses single elixir code cell" do
      content = """
      # Test Notebook

      ```elixir
      IO.puts("hello")
      ```
      """

      assert {:ok, notebook} = Parser.parse(content)
      assert length(notebook.cells) == 2

      [markdown_cell, code_cell] = notebook.cells
      assert markdown_cell.type == :markdown
      assert markdown_cell.content =~ "Test Notebook"

      assert code_cell.type == :elixir
      assert code_cell.content =~ "IO.puts"
    end

    test "parses multiple code cells" do
      content = """
      # Notebook

      ```elixir
      x = 1
      ```

      Some text

      ```elixir
      y = 2
      ```
      """

      assert {:ok, notebook} = Parser.parse(content)

      code_cells = Enum.filter(notebook.cells, &Cell.code_cell?/1)
      assert length(code_cells) == 2

      [first, second] = code_cells
      assert first.content =~ "x = 1"
      assert second.content =~ "y = 2"
    end

    test "parses erlang code cells" do
      content = """
      # Erlang

      ```erlang
      -module(test).
      ```
      """

      assert {:ok, notebook} = Parser.parse(content)

      erlang_cell = Enum.find(notebook.cells, &(&1.type == :erlang))
      assert erlang_cell
      assert erlang_cell.content =~ "-module(test)"
    end

    test "parses header metadata" do
      content = """
      <!-- livebook:{"autosave_interval_s":30} -->

      # Notebook
      """

      assert {:ok, notebook} = Parser.parse(content)
      assert notebook.metadata["autosave_interval_s"] == 30
    end

    test "parses inline metadata comments" do
      content = """
      # Notebook

      <!-- livebook:{"break_markdown":true} -->

      ```elixir
      IO.puts("test")
      ```
      """

      assert {:ok, notebook} = Parser.parse(content)

      metadata_cell = Enum.find(notebook.cells, &(&1.type == :metadata))
      assert metadata_cell
      assert metadata_cell.metadata["break_markdown"] == true
    end

    test "handles empty content" do
      assert {:ok, notebook} = Parser.parse("")
      assert notebook.cells == []
    end

    test "handles multiline code" do
      content = """
      ```elixir
      defmodule Test do
        def hello do
          :world
        end
      end
      ```
      """

      assert {:ok, notebook} = Parser.parse(content)

      code_cell = Enum.find(notebook.cells, &Cell.code_cell?/1)
      assert code_cell.content =~ "defmodule Test do"
      assert code_cell.content =~ "def hello do"
      assert code_cell.content =~ ":world"
    end

    test "returns error for non-string input" do
      assert {:error, "Content must be a string"} = Parser.parse(nil)
      assert {:error, "Content must be a string"} = Parser.parse(123)
    end
  end

  describe "parse!/1" do
    test "returns notebook on success" do
      notebook = Parser.parse!("# Hello")
      assert %Notebook{} = notebook
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Parser.parse!(nil)
      end
    end
  end
end
