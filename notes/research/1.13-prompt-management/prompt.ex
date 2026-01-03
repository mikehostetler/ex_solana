defmodule JidoCode.Prompt do
  @moduledoc """
  Core prompt structure with frontmatter support.
  
  Prompts are defined as markdown files with YAML frontmatter that maps
  directly to the Jido prompt ontology. They can be stored in the
  triplestore and recalled via TUI commands.
  
  ## Example
  
      ---
      id: my-review-prompt
      name: My Code Review
      type: system
      categories:
        domain: [code-review, elixir]
        task: evaluation
      variables:
        - name: code
          type: string
          required: true
      ---
      
      # Review Instructions
      
      Review this code: {{code}}
  """

  alias JidoCode.Prompt.Frontmatter

  @type prompt_type :: :system | :user | :assistant | :meta | :fragment | :tool | :validation

  @type variable :: %{
          name: String.t(),
          type: String.t(),
          required: boolean(),
          default: String.t() | nil,
          description: String.t() | nil
        }

  @type categories :: %{
          optional(:domain) => String.t() | [String.t()],
          optional(:task) => String.t(),
          optional(:technique) => String.t(),
          optional(:complexity) => String.t(),
          optional(:audience) => String.t()
        }

  @type target :: %{
          optional(:language) => String.t(),
          optional(:framework) => String.t() | [String.t()],
          optional(:model) => String.t(),
          optional(:model_family) => String.t(),
          optional(:min_context) => integer()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: prompt_type(),
          slug: String.t() | nil,
          description: String.t() | nil,
          content: String.t(),
          version: String.t(),
          categories: categories(),
          variables: [variable()],
          target: target(),
          tags: [String.t()],
          created_at: DateTime.t() | nil,
          modified_at: DateTime.t() | nil,
          author: String.t() | nil,
          uri: String.t() | nil
        }

  defstruct [
    :id,
    :name,
    :type,
    :slug,
    :description,
    :content,
    :version,
    :categories,
    :variables,
    :target,
    :tags,
    :created_at,
    :modified_at,
    :author,
    :uri
  ]

  @doc """
  Parse a markdown string with frontmatter into a Prompt struct.
  
  ## Example
  
      iex> markdown = \"\"\"
      ...> ---
      ...> id: test
      ...> name: Test Prompt
      ...> type: system
      ...> ---
      ...> Hello {{name}}!
      ...> \"\"\"
      iex> {:ok, prompt} = JidoCode.Prompt.from_markdown(markdown)
      iex> prompt.id
      "test"
  """
  @spec from_markdown(String.t()) :: {:ok, t()} | {:error, term()}
  def from_markdown(markdown) do
    with {:ok, frontmatter, content} <- Frontmatter.parse(markdown),
         {:ok, prompt} <- build_from_frontmatter(frontmatter, content) do
      {:ok, prompt}
    end
  end

  @doc """
  Parse markdown with frontmatter, raising on error.
  """
  @spec from_markdown!(String.t()) :: t()
  def from_markdown!(markdown) do
    case from_markdown(markdown) do
      {:ok, prompt} -> prompt
      {:error, reason} -> raise ArgumentError, "Invalid prompt: #{inspect(reason)}"
    end
  end

  @doc """
  Serialize a Prompt struct to markdown with frontmatter.
  """
  @spec to_markdown(t()) :: String.t()
  def to_markdown(%__MODULE__{} = prompt) do
    frontmatter = build_frontmatter(prompt)

    yaml =
      frontmatter
      |> stringify_keys()
      |> Enum.map(fn {k, v} -> "#{k}: #{format_yaml_value(v)}" end)
      |> Enum.join("\n")

    """
    ---
    #{yaml}
    ---

    #{prompt.content}
    """
  end

  @doc """
  Interpolate variables into prompt content.
  
  Supports multiple template syntaxes:
  - `{{variable}}` - Handlebars style
  - `${variable}` - Shell style  
  - `<variable>` - XML style (for simple cases)
  
  ## Example
  
      iex> prompt = %JidoCode.Prompt{
      ...>   content: "Hello {{name}}!",
      ...>   variables: [%{name: "name", type: "string", required: true}]
      ...> }
      iex> {:ok, content} = JidoCode.Prompt.interpolate(prompt, %{"name" => "World"})
      iex> content
      "Hello World!"
  """
  @spec interpolate(t(), map()) :: {:ok, String.t()} | {:error, term()}
  def interpolate(%__MODULE__{} = prompt, variables) do
    with :ok <- validate_required_variables(prompt, variables) do
      content = interpolate_variables(prompt.content, variables, prompt.variables)
      {:ok, content}
    end
  end

  @doc """
  Check if a prompt has all required variables satisfied.
  """
  @spec variables_satisfied?(t(), map()) :: boolean()
  def variables_satisfied?(%__MODULE__{} = prompt, provided) do
    prompt.variables
    |> Enum.filter(& &1.required)
    |> Enum.all?(fn var -> Map.has_key?(provided, var.name) end)
  end

  @doc """
  Get list of required variable names.
  """
  @spec required_variables(t()) :: [String.t()]
  def required_variables(%__MODULE__{} = prompt) do
    prompt.variables
    |> Enum.filter(& &1.required)
    |> Enum.map(& &1.name)
  end

  @doc """
  Get list of optional variable names with their defaults.
  """
  @spec optional_variables(t()) :: [{String.t(), String.t() | nil}]
  def optional_variables(%__MODULE__{} = prompt) do
    prompt.variables
    |> Enum.reject(& &1.required)
    |> Enum.map(&{&1.name, &1[:default]})
  end

  @doc """
  Create a new prompt with default values.
  """
  @spec new(map()) :: t()
  def new(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: attrs[:id] || generate_id(),
      name: attrs[:name] || "Untitled Prompt",
      type: attrs[:type] || :system,
      slug: attrs[:slug] || attrs[:id],
      description: attrs[:description],
      content: attrs[:content] || "",
      version: attrs[:version] || "1.0.0",
      categories: attrs[:categories] || %{},
      variables: attrs[:variables] || [],
      target: attrs[:target] || %{},
      tags: attrs[:tags] || [],
      created_at: attrs[:created_at] || now,
      modified_at: attrs[:modified_at] || now,
      author: attrs[:author] || "user",
      uri: attrs[:uri]
    }
  end

  # Private functions

  defp build_from_frontmatter(fm, content) do
    prompt = %__MODULE__{
      id: fm[:id],
      name: fm[:name],
      type: parse_type(fm[:type]),
      slug: fm[:slug] || fm[:id],
      description: fm[:description],
      content: content,
      version: fm[:version] || "1.0.0",
      categories: fm[:categories] || %{},
      variables: fm[:variables] || [],
      target: fm[:target] || %{},
      tags: fm[:tags] || [],
      created_at: parse_datetime(fm[:created_at]),
      modified_at: parse_datetime(fm[:modified_at]),
      author: fm[:author]
    }

    {:ok, prompt}
  end

  defp parse_type("system"), do: :system
  defp parse_type("user"), do: :user
  defp parse_type("assistant"), do: :assistant
  defp parse_type("meta"), do: :meta
  defp parse_type("fragment"), do: :fragment
  defp parse_type("tool"), do: :tool
  defp parse_type("validation"), do: :validation
  defp parse_type(atom) when is_atom(atom), do: atom
  defp parse_type(_), do: :system

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp build_frontmatter(prompt) do
    base = %{
      id: prompt.id,
      name: prompt.name,
      type: to_string(prompt.type)
    }

    base
    |> maybe_add(:slug, prompt.slug, prompt.slug != prompt.id)
    |> maybe_add(:description, prompt.description, prompt.description != nil)
    |> maybe_add(:version, prompt.version, prompt.version != "1.0.0")
    |> maybe_add(:categories, prompt.categories, prompt.categories != %{})
    |> maybe_add(:variables, format_variables(prompt.variables), prompt.variables != [])
    |> maybe_add(:target, prompt.target, prompt.target != %{})
    |> maybe_add(:tags, prompt.tags, prompt.tags != [])
    |> maybe_add(:author, prompt.author, prompt.author != nil)
  end

  defp maybe_add(map, _key, _value, false), do: map
  defp maybe_add(map, key, value, true), do: Map.put(map, key, value)

  defp format_variables(vars) do
    Enum.map(vars, fn var ->
      %{
        "name" => var.name,
        "type" => var.type,
        "required" => var.required
      }
      |> maybe_add("default", var[:default], var[:default] != nil)
      |> maybe_add("description", var[:description], var[:description] != nil)
    end)
  end

  defp validate_required_variables(prompt, provided) do
    missing =
      prompt.variables
      |> Enum.filter(& &1.required)
      |> Enum.reject(fn var -> Map.has_key?(provided, var.name) end)
      |> Enum.map(& &1.name)

    case missing do
      [] -> :ok
      names -> {:error, {:missing_variables, names}}
    end
  end

  defp interpolate_variables(content, values, variable_defs) do
    # Build a map with defaults filled in
    full_values =
      Enum.reduce(variable_defs, values, fn var_def, acc ->
        if Map.has_key?(acc, var_def.name) do
          acc
        else
          Map.put(acc, var_def.name, var_def[:default] || "")
        end
      end)

    # Replace all template syntaxes
    Enum.reduce(full_values, content, fn {name, value}, acc ->
      value_str = to_string(value)

      acc
      |> String.replace("{{#{name}}}", value_str)
      |> String.replace("${#{name}}", value_str)
      |> String.replace("<#{name}>", value_str)
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  defp format_yaml_value(value) when is_list(value) do
    "[#{Enum.map_join(value, ", ", &inspect/1)}]"
  end

  defp format_yaml_value(value) when is_map(value) do
    # For nested maps, we'd need proper YAML indentation
    # This is simplified for now
    inspect(value)
  end

  defp format_yaml_value(value) when is_binary(value), do: inspect(value)
  defp format_yaml_value(value) when is_boolean(value), do: to_string(value)
  defp format_yaml_value(value) when is_number(value), do: to_string(value)
  defp format_yaml_value(value), do: inspect(value)

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
