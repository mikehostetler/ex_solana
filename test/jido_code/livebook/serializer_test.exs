defmodule JidoCode.Livebook.SerializerTest do
  use ExUnit.Case, async: true

  alias JidoCode.Livebook.{Serializer, Notebook, Cell}

  describe "serialize/1" do
    test "serializes empty notebook" do
      notebook = Notebook.new()
      assert Serializer.serialize(notebook) == ""
    end

    test "serializes markdown cell" do
      notebook = Notebook.new([Cell.markdown("# Hello World")])
      result = Serializer.serialize(notebook)

      assert result == "# Hello World"
    end

    test "serializes elixir code cell" do
      notebook = Notebook.new([Cell.elixir("IO.puts(:hello)")])
      result = Serializer.serialize(notebook)

      assert result == "```elixir\nIO.puts(:hello)\n```"
    end

    test "serializes erlang code cell" do
      notebook = Notebook.new([Cell.erlang("-module(test).")])
      result = Serializer.serialize(notebook)

      assert result == "```erlang\n-module(test).\n```"
    end

    test "serializes mixed cells" do
      notebook =
        Notebook.new([
          Cell.markdown("# Title"),
          Cell.elixir("x = 1"),
          Cell.markdown("Some text"),
          Cell.elixir("y = 2")
        ])

      result = Serializer.serialize(notebook)

      assert result =~ "# Title"
      assert result =~ "```elixir\nx = 1\n```"
      assert result =~ "Some text"
      assert result =~ "```elixir\ny = 2\n```"
    end

    test "serializes notebook metadata" do
      notebook = %Notebook{
        cells: [Cell.markdown("# Hello")],
        metadata: %{"autosave_interval_s" => 30}
      }

      result = Serializer.serialize(notebook)

      assert result =~ "<!-- livebook:"
      assert result =~ "autosave_interval_s"
      assert result =~ "30"
    end

    test "serializes metadata cells" do
      notebook =
        Notebook.new([
          Cell.markdown("# Hello"),
          Cell.new(:metadata, "", %{"break_markdown" => true})
        ])

      result = Serializer.serialize(notebook)
      assert result =~ "<!-- livebook:"
      assert result =~ "break_markdown"
    end
  end

  describe "round-trip parse/serialize" do
    alias JidoCode.Livebook.Parser

    test "preserves simple notebook structure" do
      original = """
      # My Notebook

      ```elixir
      IO.puts("hello")
      ```

      Some markdown text.

      ```elixir
      x = 1 + 2
      ```
      """

      {:ok, notebook} = Parser.parse(original)
      serialized = Serializer.serialize(notebook)
      {:ok, reparsed} = Parser.parse(serialized)

      # Compare cell counts and types
      assert length(notebook.cells) == length(reparsed.cells)

      original_types = Enum.map(notebook.cells, & &1.type)
      reparsed_types = Enum.map(reparsed.cells, & &1.type)
      assert original_types == reparsed_types
    end

    test "preserves code content" do
      original = """
      ```elixir
      defmodule Test do
        def hello, do: :world
      end
      ```
      """

      {:ok, notebook} = Parser.parse(original)
      serialized = Serializer.serialize(notebook)
      {:ok, reparsed} = Parser.parse(serialized)

      original_code =
        notebook.cells |> Enum.find(&Cell.code_cell?/1) |> Map.get(:content)

      reparsed_code =
        reparsed.cells |> Enum.find(&Cell.code_cell?/1) |> Map.get(:content)

      assert String.trim(original_code) == String.trim(reparsed_code)
    end
  end
end
