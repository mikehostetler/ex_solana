defmodule JidoCode.Livebook.Parser do
  @moduledoc """
  Parser for Elixir Livebook `.livemd` files.

  Livebook notebooks are markdown files with embedded code cells. This module
  parses the structure into an in-memory representation for programmatic manipulation.

  ## Format

  Livebook files use markdown with special conventions:
  - Code cells: Fenced code blocks with language tags (```elixir, ```erlang)
  - Smart cells: HTML comments with JSON metadata (<!-- livebook:{...} -->)
  - Sections: Markdown headers (## Section Name)
  - Setup: Special `<!-- livebook:{"autosave_interval_s":30} -->` at file start

  ## Usage

      {:ok, notebook} = Parser.parse(livemd_content)
      # Returns %Notebook{} with parsed cells and metadata
  """

  alias JidoCode.Livebook.{Cell, Notebook}

  @code_fence_regex ~r/^```(\w+)\s*$/m
  @code_fence_end_regex ~r/^```\s*$/m
  @livebook_metadata_regex ~r/<!--\s*livebook:(\{[^}]+\})\s*-->/

  @doc """
  Parses a .livemd string into a `%Notebook{}` struct.

  ## Parameters

  - `content` - The raw .livemd file content as a string

  ## Returns

  - `{:ok, %Notebook{}}` - Successfully parsed notebook
  - `{:error, reason}` - Parse error with description

  ## Examples

      iex> Parser.parse("# My Notebook\\n\\n```elixir\\nIO.puts(\\"hello\\")\\n```")
      {:ok, %Notebook{cells: [%Cell{type: :markdown, content: "# My Notebook"}, %Cell{type: :elixir, content: "IO.puts(\\"hello\\")"}]}}
  """
  @spec parse(String.t()) :: {:ok, Notebook.t()} | {:error, String.t()}
  def parse(content) when is_binary(content) do
    {metadata, content_without_header} = extract_header_metadata(content)

    cells = parse_cells(content_without_header)

    {:ok,
     %Notebook{
       cells: cells,
       metadata: metadata
     }}
  rescue
    e ->
      {:error, "Failed to parse notebook: #{Exception.message(e)}"}
  end

  def parse(_), do: {:error, "Content must be a string"}

  @doc """
  Parses a .livemd string, raising on error.

  Same as `parse/1` but raises `ArgumentError` on parse failure.
  """
  @spec parse!(String.t()) :: Notebook.t()
  def parse!(content) do
    case parse(content) do
      {:ok, notebook} -> notebook
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # Extract top-level metadata from livebook header comment
  defp extract_header_metadata(content) do
    case Regex.run(@livebook_metadata_regex, content, return: :index) do
      [{start, len} | _] ->
        # Check if it's at the very beginning (possibly after whitespace)
        prefix = String.slice(content, 0, start)

        if String.trim(prefix) == "" do
          metadata_str = String.slice(content, start, len)
          json = extract_json_from_comment(metadata_str)
          metadata = parse_metadata_json(json)
          rest = String.slice(content, start + len, String.length(content))
          {metadata, String.trim_leading(rest)}
        else
          {%{}, content}
        end

      nil ->
        {%{}, content}
    end
  end

  defp extract_json_from_comment(comment) do
    case Regex.run(@livebook_metadata_regex, comment) do
      [_, json] -> json
      _ -> "{}"
    end
  end

  defp parse_metadata_json(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      {:error, _} -> %{}
    end
  end

  # Parse content into a list of cells
  defp parse_cells(content) do
    content
    |> split_into_segments()
    |> Enum.flat_map(&segment_to_cells/1)
    |> Enum.reject(&empty_cell?/1)
  end

  # Split content into segments (markdown vs code blocks)
  defp split_into_segments(content) do
    # Find all code fence positions
    lines = String.split(content, "\n")
    {segments, current, in_code, lang} = parse_lines(lines, [], [], false, nil)

    # Finalize last segment
    finalize_segments(segments, current, in_code, lang)
  end

  defp parse_lines([], segments, current, in_code, lang) do
    {segments, current, in_code, lang}
  end

  defp parse_lines([line | rest], segments, current, false, _lang) do
    case Regex.run(@code_fence_regex, line) do
      [_, language] ->
        # Start of code block - save current markdown segment
        markdown_segment = {:markdown, Enum.reverse(current)}
        parse_lines(rest, [markdown_segment | segments], [], true, String.to_atom(language))

      nil ->
        # Check for livebook metadata comment
        case Regex.run(@livebook_metadata_regex, line) do
          [_, json] ->
            # Metadata comment - save as metadata segment
            markdown_segment = {:markdown, Enum.reverse(current)}
            metadata_segment = {:metadata, json}
            parse_lines(rest, [metadata_segment, markdown_segment | segments], [], false, nil)

          nil ->
            # Regular markdown line
            parse_lines(rest, segments, [line | current], false, nil)
        end
    end
  end

  defp parse_lines([line | rest], segments, current, true, lang) do
    if Regex.match?(@code_fence_end_regex, line) do
      # End of code block
      code_segment = {:code, lang, Enum.reverse(current)}
      parse_lines(rest, [code_segment | segments], [], false, nil)
    else
      # Inside code block
      parse_lines(rest, segments, [line | current], true, lang)
    end
  end

  defp finalize_segments(segments, current, in_code, lang) do
    final_segment =
      if in_code do
        # Unclosed code block
        {:code, lang, Enum.reverse(current)}
      else
        {:markdown, Enum.reverse(current)}
      end

    [final_segment | segments]
    |> Enum.reverse()
  end

  # Convert a segment to one or more cells
  defp segment_to_cells({:markdown, lines}) do
    content = Enum.join(lines, "\n")
    [%Cell{type: :markdown, content: content, metadata: %{}}]
  end

  defp segment_to_cells({:code, lang, lines}) do
    content = Enum.join(lines, "\n")
    [%Cell{type: lang, content: content, metadata: %{}}]
  end

  defp segment_to_cells({:metadata, json}) do
    metadata = parse_metadata_json(json)
    [%Cell{type: :metadata, content: "", metadata: metadata}]
  end

  defp empty_cell?(%Cell{type: :markdown, content: content}) do
    String.trim(content) == ""
  end

  defp empty_cell?(%Cell{type: :metadata}), do: false
  defp empty_cell?(%Cell{}), do: false
end
