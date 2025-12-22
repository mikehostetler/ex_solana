defmodule JidoCode.Livebook.Serializer do
  @moduledoc """
  Serializer for Elixir Livebook `.livemd` files.

  Converts a `%Notebook{}` struct back to the .livemd string format
  that Livebook can open and execute.

  ## Usage

      notebook = %Notebook{cells: [...]}
      livemd_content = Serializer.serialize(notebook)
      File.write!("notebook.livemd", livemd_content)
  """

  alias JidoCode.Livebook.{Cell, Notebook}

  @doc """
  Serializes a `%Notebook{}` struct to .livemd string format.

  ## Parameters

  - `notebook` - The `%Notebook{}` struct to serialize

  ## Returns

  A string containing the .livemd content.

  ## Examples

      iex> notebook = %Notebook{cells: [Cell.markdown("# Hello"), Cell.elixir("IO.puts(1)")]}
      iex> Serializer.serialize(notebook)
      "# Hello\\n\\n```elixir\\nIO.puts(1)\\n```"
  """
  @spec serialize(Notebook.t()) :: String.t()
  def serialize(%Notebook{cells: cells, metadata: metadata}) do
    header = serialize_header_metadata(metadata)
    body = serialize_cells(cells)

    if header == "" do
      body
    else
      header <> "\n\n" <> body
    end
  end

  # Serialize notebook-level metadata as header comment
  defp serialize_header_metadata(metadata) when map_size(metadata) == 0, do: ""

  defp serialize_header_metadata(metadata) do
    json = Jason.encode!(metadata)
    "<!-- livebook:#{json} -->"
  end

  # Serialize list of cells
  defp serialize_cells(cells) do
    cells
    |> Enum.map(&serialize_cell/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # Serialize a single cell
  defp serialize_cell(%Cell{type: :markdown, content: content}) do
    String.trim(content)
  end

  defp serialize_cell(%Cell{type: :elixir, content: content}) do
    "```elixir\n#{content}\n```"
  end

  defp serialize_cell(%Cell{type: :erlang, content: content}) do
    "```erlang\n#{content}\n```"
  end

  defp serialize_cell(%Cell{type: :heex, content: content}) do
    "```heex\n#{content}\n```"
  end

  defp serialize_cell(%Cell{type: :sql, content: content}) do
    "```sql\n#{content}\n```"
  end

  defp serialize_cell(%Cell{type: :metadata, metadata: metadata}) do
    json = Jason.encode!(metadata)
    "<!-- livebook:#{json} -->"
  end

  defp serialize_cell(%Cell{type: :smart, content: content, metadata: metadata}) do
    json = Jason.encode!(metadata)
    "<!-- livebook:#{json} -->\n\n```elixir\n#{content}\n```"
  end

  defp serialize_cell(%Cell{type: type, content: content}) do
    # Fallback for unknown types - treat as code
    "```#{type}\n#{content}\n```"
  end
end
