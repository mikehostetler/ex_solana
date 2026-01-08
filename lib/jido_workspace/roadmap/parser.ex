defmodule JidoWorkspace.Roadmap.Parser do
  @moduledoc """
  Parses roadmap markdown files, extracting YAML front-matter and tasks.
  """

  alias JidoWorkspace.Roadmap.Task
  alias JidoWorkspace.Roadmap.File, as: RoadmapFile

  @doc """
  Parses a markdown file, returning a Roadmap.File struct with metadata and tasks.
  """
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} ->
        {meta, body_lines} = parse_content(content)
        tasks = extract_tasks(body_lines, path)

        {:ok,
         %RoadmapFile{
           path: path,
           meta: meta,
           body_lines: body_lines,
           tasks: tasks
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses file content, separating YAML front-matter from body.
  """
  def parse_content(content) do
    lines = String.split(content, "\n")

    case lines do
      ["---" | rest] ->
        parse_with_frontmatter(rest)

      _ ->
        {%{}, lines}
    end
  end

  @doc """
  Extracts tasks from body lines, tracking section hierarchy.
  """
  def extract_tasks(lines, file_path) do
    {tasks, _section} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {line, idx}, {tasks, current_section} ->
        cond do
          section = parse_section_header(line) ->
            depth = section_depth(line)
            new_section = update_section(current_section, depth, section)
            {tasks, new_section}

          Task.task_line?(line) ->
            case Task.parse(line, idx, file_path, section: current_section) do
              nil -> {tasks, current_section}
              task -> {[task | tasks], current_section}
            end

          true ->
            {tasks, current_section}
        end
      end)

    Enum.reverse(tasks)
  end

  @doc """
  Parse a section header from a markdown line.
  Returns the section title or nil.
  """
  def parse_section_header(line) do
    cond do
      match = Regex.run(~r/^#+\s+\*\*(.+)\*\*/, line) ->
        [_, title] = match
        String.trim(title)

      match = Regex.run(~r/^(#+)\s+(.+)$/, line) ->
        [_, _hashes, title] = match
        clean = title |> String.replace(~r/\*\*(.+)\*\*/, "\\1") |> String.trim()
        if String.length(clean) > 0, do: clean, else: nil

      true ->
        nil
    end
  end

  defp section_depth(line) do
    case Regex.run(~r/^(#+)/, line) do
      [_, hashes] -> String.length(hashes)
      _ -> 0
    end
  end

  defp update_section(current, depth, name) do
    Enum.take(current, depth - 1) ++ [name]
  end

  @doc """
  Gets only the front-matter metadata without parsing the full body.
  Useful for performance when you only need metadata.
  """
  def parse_frontmatter_only(path) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        case lines do
          ["---" | rest] ->
            {meta, _} = parse_with_frontmatter(rest)
            {:ok, meta}

          _ ->
            {:ok, %{}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private function to parse content with YAML front-matter
  defp parse_with_frontmatter(lines) do
    case Enum.find_index(lines, &(&1 == "---")) do
      nil ->
        # No closing ---, treat everything as front-matter
        yaml_content = Enum.join(lines, "\n")
        meta = parse_yaml(yaml_content)
        {meta, []}

      end_index ->
        yaml_lines = Enum.take(lines, end_index)
        body_lines = Enum.drop(lines, end_index + 1)

        yaml_content = Enum.join(yaml_lines, "\n")
        meta = parse_yaml(yaml_content)

        {meta, body_lines}
    end
  end

  # Private function to parse YAML content
  defp parse_yaml(""), do: %{}

  defp parse_yaml(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, meta} when is_map(meta) ->
        # Convert string keys to atoms for easier access
        Map.new(meta, fn {k, v} -> {String.to_atom(k), v} end)

      {:ok, _} ->
        %{}

      {:error, _} ->
        %{}
    end
  end
end
