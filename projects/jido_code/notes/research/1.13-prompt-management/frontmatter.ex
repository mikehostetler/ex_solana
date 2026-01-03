defmodule JidoCode.Prompt.Frontmatter do
  @moduledoc """
  Parse and validate YAML frontmatter from markdown prompts.
  
  Frontmatter is the YAML block at the beginning of a markdown file,
  delimited by `---` lines. This module handles parsing the frontmatter
  and validating it against the prompt schema.
  
  ## Frontmatter Schema
  
  Required fields:
  - `id` - Unique identifier (slug-safe string)
  - `name` - Human-readable name
  - `type` - One of: system, user, assistant, meta, fragment, tool, validation
  
  Optional fields:
  - `slug` - URL-safe identifier (defaults to id)
  - `description` - Description of the prompt
  - `version` - Semantic version (defaults to "1.0.0")
  - `categories` - Map of category dimensions
  - `variables` - List of variable definitions
  - `target` - Target model/language configuration
  - `tags` - List of tags for search
  - `created_at` - ISO 8601 datetime
  - `modified_at` - ISO 8601 datetime
  - `author` - Author name/ID
  """

  @frontmatter_regex ~r/\A---\r?\n(.+?)\r?\n---\r?\n(.*)\z/s

  @required_fields [:id, :name, :type]

  @valid_types ~w(system user assistant meta fragment tool validation)

  @doc """
  Parse markdown with frontmatter into {frontmatter_map, content}.
  
  ## Example
  
      iex> md = \"\"\"
      ...> ---
      ...> id: test
      ...> name: Test
      ...> type: system
      ...> ---
      ...> Content here
      ...> \"\"\"
      iex> {:ok, fm, content} = JidoCode.Prompt.Frontmatter.parse(md)
      iex> fm.id
      "test"
      iex> content
      "Content here"
  """
  @spec parse(String.t()) :: {:ok, map(), String.t()} | {:error, term()}
  def parse(markdown) do
    case Regex.run(@frontmatter_regex, markdown) do
      [_, yaml, content] ->
        with {:ok, frontmatter} <- parse_yaml(yaml),
             :ok <- validate_frontmatter(frontmatter) do
          {:ok, normalize_frontmatter(frontmatter), String.trim(content)}
        end

      nil ->
        {:error, :no_frontmatter}
    end
  end

  @doc """
  Validate frontmatter map without parsing.
  """
  @spec validate(map()) :: :ok | {:error, term()}
  def validate(frontmatter) do
    validate_frontmatter(frontmatter)
  end

  @doc """
  Check if a string has valid frontmatter structure.
  """
  @spec has_frontmatter?(String.t()) :: boolean()
  def has_frontmatter?(markdown) do
    Regex.match?(@frontmatter_regex, markdown)
  end

  @doc """
  Extract just the content without frontmatter.
  """
  @spec strip_frontmatter(String.t()) :: String.t()
  def strip_frontmatter(markdown) do
    case Regex.run(@frontmatter_regex, markdown) do
      [_, _yaml, content] -> String.trim(content)
      nil -> markdown
    end
  end

  @doc """
  Generate frontmatter YAML from a map.
  """
  @spec to_yaml(map()) :: String.t()
  def to_yaml(frontmatter) do
    frontmatter
    |> stringify_keys()
    |> format_yaml(0)
  end

  # Private functions

  defp parse_yaml(yaml_string) do
    # Use YamlElixir if available, otherwise simple parser
    if Code.ensure_loaded?(YamlElixir) do
      YamlElixir.read_from_string(yaml_string)
    else
      simple_yaml_parse(yaml_string)
    end
  end

  # Simple YAML parser for basic frontmatter (when YamlElixir not available)
  defp simple_yaml_parse(yaml_string) do
    try do
      result =
        yaml_string
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) == ""))
        |> parse_yaml_lines(%{}, [])

      {:ok, result}
    rescue
      e -> {:error, {:yaml_parse_error, Exception.message(e)}}
    end
  end

  defp parse_yaml_lines([], acc, []), do: acc

  defp parse_yaml_lines([line | rest], acc, context) do
    trimmed = String.trim(line)
    indent = count_indent(line)

    cond do
      # Skip empty lines and comments
      trimmed == "" or String.starts_with?(trimmed, "#") ->
        parse_yaml_lines(rest, acc, context)

      # List item
      String.starts_with?(trimmed, "- ") ->
        value = String.trim_leading(trimmed, "- ")
        parse_yaml_lines(rest, acc, [{:list_item, value} | context])

      # Key-value pair
      String.contains?(trimmed, ":") ->
        [key | value_parts] = String.split(trimmed, ":", parts: 2)
        key = String.trim(key)
        value = value_parts |> Enum.join(":") |> String.trim() |> parse_yaml_value()

        if value == "" do
          # This key has nested content
          {nested, remaining} = collect_nested(rest, indent)
          nested_value = parse_yaml_lines(nested, %{}, [])
          parse_yaml_lines(remaining, Map.put(acc, key, nested_value), context)
        else
          parse_yaml_lines(rest, Map.put(acc, key, value), context)
        end

      true ->
        parse_yaml_lines(rest, acc, context)
    end
  end

  defp count_indent(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end

  defp collect_nested(lines, parent_indent) do
    {nested, remaining} =
      Enum.split_while(lines, fn line ->
        trimmed = String.trim(line)
        indent = count_indent(line)
        trimmed == "" or indent > parent_indent
      end)

    {nested, remaining}
  end

  defp parse_yaml_value(str) do
    cond do
      str == "" -> ""
      str == "true" -> true
      str == "false" -> false
      str == "null" or str == "~" -> nil
      String.starts_with?(str, "[") and String.ends_with?(str, "]") -> parse_yaml_list(str)
      String.starts_with?(str, "\"") and String.ends_with?(str, "\"") -> String.slice(str, 1..-2//1)
      String.starts_with?(str, "'") and String.ends_with?(str, "'") -> String.slice(str, 1..-2//1)
      match?({_, ""}, Integer.parse(str)) -> String.to_integer(str)
      match?({_, ""}, Float.parse(str)) -> String.to_float(str)
      true -> str
    end
  end

  defp parse_yaml_list(str) do
    str
    |> String.slice(1..-2//1)
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_yaml_value/1)
  end

  defp validate_frontmatter(fm) do
    cond do
      missing_required?(fm) ->
        {:error, {:missing_required, missing_fields(fm)}}

      invalid_type?(fm) ->
        {:error, {:invalid_type, fm["type"]}}

      invalid_id?(fm) ->
        {:error, {:invalid_id, fm["id"]}}

      true ->
        :ok
    end
  end

  defp missing_required?(fm) do
    Enum.any?(@required_fields, fn field ->
      key = to_string(field)
      !Map.has_key?(fm, key) or fm[key] == nil or fm[key] == ""
    end)
  end

  defp missing_fields(fm) do
    Enum.filter(@required_fields, fn field ->
      key = to_string(field)
      !Map.has_key?(fm, key) or fm[key] == nil or fm[key] == ""
    end)
  end

  defp invalid_type?(fm) do
    type = fm["type"]
    type != nil and type not in @valid_types
  end

  defp invalid_id?(fm) do
    id = fm["id"]
    # ID must be a valid slug (alphanumeric, hyphens, underscores)
    id != nil and not Regex.match?(~r/^[a-zA-Z0-9_-]+$/, id)
  end

  defp normalize_frontmatter(fm) do
    fm
    |> normalize_keys()
    |> normalize_categories()
    |> normalize_variables()
    |> normalize_target()
    |> normalize_tags()
    |> set_defaults()
  end

  defp normalize_keys(fm) do
    Map.new(fm, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp normalize_categories(%{categories: cats} = fm) when is_map(cats) do
    normalized =
      Map.new(cats, fn {k, v} ->
        key = if is_atom(k), do: k, else: String.to_atom(k)
        {key, normalize_category_value(v)}
      end)

    %{fm | categories: normalized}
  end

  defp normalize_categories(fm), do: Map.put(fm, :categories, %{})

  defp normalize_category_value(v) when is_list(v), do: v
  defp normalize_category_value(v) when is_binary(v), do: [v]
  defp normalize_category_value(v), do: v

  defp normalize_variables(%{variables: vars} = fm) when is_list(vars) do
    normalized =
      Enum.map(vars, fn var ->
        var = if is_map(var), do: normalize_keys(var), else: var

        %{
          name: var[:name] || var["name"],
          type: var[:type] || var["type"] || "string",
          required: var[:required] || var["required"] || false,
          default: var[:default] || var["default"],
          description: var[:description] || var["description"]
        }
      end)

    %{fm | variables: normalized}
  end

  defp normalize_variables(fm), do: Map.put(fm, :variables, [])

  defp normalize_target(%{target: target} = fm) when is_map(target) do
    normalized =
      Map.new(target, fn {k, v} ->
        key = if is_atom(k), do: k, else: String.to_atom(k)
        {key, v}
      end)

    %{fm | target: normalized}
  end

  defp normalize_target(fm), do: Map.put(fm, :target, %{})

  defp normalize_tags(%{tags: tags} = fm) when is_list(tags), do: fm
  defp normalize_tags(%{tags: tag} = fm) when is_binary(tag), do: %{fm | tags: [tag]}
  defp normalize_tags(fm), do: Map.put(fm, :tags, [])

  defp set_defaults(fm) do
    now = DateTime.utc_now()

    fm
    |> Map.put_new(:slug, fm[:id])
    |> Map.put_new(:version, "1.0.0")
    |> Map.put_new(:created_at, now)
    |> Map.put_new(:modified_at, now)
    |> Map.put_new(:author, "user")
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  defp format_yaml(map, indent) when is_map(map) do
    prefix = String.duplicate("  ", indent)

    map
    |> Enum.map(fn {k, v} ->
      "#{prefix}#{k}: #{format_yaml_value(v, indent)}"
    end)
    |> Enum.join("\n")
  end

  defp format_yaml_value(value, _indent) when is_binary(value) do
    if String.contains?(value, "\n") or String.contains?(value, ":") do
      inspect(value)
    else
      value
    end
  end

  defp format_yaml_value(value, _indent) when is_boolean(value), do: to_string(value)
  defp format_yaml_value(value, _indent) when is_number(value), do: to_string(value)
  defp format_yaml_value(nil, _indent), do: "null"

  defp format_yaml_value(list, _indent) when is_list(list) do
    formatted = Enum.map_join(list, ", ", &format_yaml_value(&1, 0))
    "[#{formatted}]"
  end

  defp format_yaml_value(map, indent) when is_map(map) do
    "\n" <> format_yaml(map, indent + 1)
  end

  defp format_yaml_value(value, _indent), do: inspect(value)
end
