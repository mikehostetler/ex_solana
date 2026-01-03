defmodule JidoCode.Prompt.RDFMapper do
  @moduledoc """
  Convert between Prompt structs and RDF triples.
  
  This module handles serialization of prompts to RDF for storage in the
  triplestore, and deserialization back to Prompt structs.
  
  ## Namespace
  
  User prompts are stored under `https://jido.ai/user/prompts/` with their ID
  as the local part. For example, a prompt with ID "my-review" would have the URI:
  
      https://jido.ai/user/prompts/my-review
  
  ## RDF Structure
  
  Each prompt generates triples for:
  - The prompt itself (type, id, name, description, etc.)
  - Its content (separate PromptContent node)
  - Its version(s) (separate PromptVersion nodes)
  - Its variables (separate PromptVariable nodes)
  - Category links
  - Target configuration
  - Tags
  """

  alias JidoCode.Prompt

  @jido_ns "https://jido.ai/ontology#"
  @user_prompt_ns "https://jido.ai/user/prompts/"
  @user_category_ns "https://jido.ai/user/categories/"
  @rdf_ns "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  @xsd_ns "http://www.w3.org/2001/XMLSchema#"

  @type_mapping %{
    system: "SystemPrompt",
    user: "UserPrompt",
    assistant: "AssistantPrompt",
    meta: "MetaPrompt",
    fragment: "PromptFragment",
    tool: "ToolPrompt",
    validation: "ValidationPrompt"
  }

  @doc """
  Convert a Prompt struct to RDF triples.
  
  Returns a list of triple tuples: `{subject, predicate, object}`
  
  ## Example
  
      iex> prompt = %JidoCode.Prompt{id: "test", name: "Test", type: :system, ...}
      iex> triples = JidoCode.Prompt.RDFMapper.to_triples(prompt)
      iex> length(triples) > 0
      true
  """
  @spec to_triples(Prompt.t()) :: [{String.t(), String.t(), term()}]
  def to_triples(%Prompt{} = prompt) do
    prompt_uri = prompt_uri(prompt.id)
    content_uri = content_uri(prompt.id)
    version_uri = version_uri(prompt.id, prompt.version)

    []
    |> add_prompt_triples(prompt, prompt_uri)
    |> add_content_triples(prompt, prompt_uri, content_uri)
    |> add_version_triples(prompt, prompt_uri, version_uri)
    |> add_variable_triples(prompt, prompt_uri)
    |> add_category_triples(prompt, prompt_uri)
    |> add_target_triples(prompt, prompt_uri)
    |> add_tag_triples(prompt, prompt_uri)
  end

  @doc """
  Generate a SPARQL INSERT DATA query for a prompt.
  """
  @spec to_sparql_insert(Prompt.t()) :: String.t()
  def to_sparql_insert(%Prompt{} = prompt) do
    triples = to_triples(prompt)

    turtle_triples =
      triples
      |> Enum.map(&format_triple/1)
      |> Enum.join("\n")

    """
    PREFIX jido: <#{@jido_ns}>
    PREFIX rdf: <#{@rdf_ns}>
    PREFIX xsd: <#{@xsd_ns}>

    INSERT DATA {
    #{turtle_triples}
    }
    """
  end

  @doc """
  Generate a SPARQL DELETE query for a prompt by ID.
  """
  @spec to_sparql_delete(String.t()) :: String.t()
  def to_sparql_delete(prompt_id) do
    uri = prompt_uri(prompt_id)

    """
    PREFIX jido: <#{@jido_ns}>

    DELETE WHERE {
      {
        <#{uri}> ?p ?o .
      } UNION {
        <#{uri}/content> ?p ?o .
      } UNION {
        <#{uri}> jido:hasPromptVersion ?v .
        ?v ?p ?o .
      } UNION {
        <#{uri}> jido:hasVariable ?var .
        ?var ?p ?o .
      }
    }
    """
  end

  @doc """
  Parse RDF triples into a Prompt struct.
  
  Expects a map of predicate -> object(s) for the prompt subject.
  """
  @spec from_triples(String.t(), map()) :: {:ok, Prompt.t()} | {:error, term()}
  def from_triples(prompt_id, data) do
    try do
      prompt = %Prompt{
        id: prompt_id,
        uri: prompt_uri(prompt_id),
        name: get_value(data, "promptName"),
        type: parse_type(data),
        slug: get_value(data, "promptSlug", prompt_id),
        description: get_value(data, "promptDescription"),
        content: get_content(data),
        version: get_current_version(data),
        categories: get_categories(data),
        variables: get_variables(data),
        target: get_target(data),
        tags: get_list(data, "hasPromptTag"),
        created_at: get_datetime(data, "promptCreatedAt"),
        modified_at: get_datetime(data, "promptModifiedAt"),
        author: get_author(data)
      }

      {:ok, prompt}
    rescue
      e -> {:error, {:parse_error, Exception.message(e)}}
    end
  end

  @doc """
  Get the URI for a prompt by ID.
  """
  @spec prompt_uri(String.t()) :: String.t()
  def prompt_uri(id), do: "#{@user_prompt_ns}#{id}"

  @doc """
  Extract prompt ID from URI.
  """
  @spec id_from_uri(String.t()) :: String.t() | nil
  def id_from_uri(uri) do
    if String.starts_with?(uri, @user_prompt_ns) do
      String.replace_prefix(uri, @user_prompt_ns, "")
    else
      nil
    end
  end

  # Private: URI builders

  defp content_uri(id), do: "#{@user_prompt_ns}#{id}/content"
  defp version_uri(id, version), do: "#{@user_prompt_ns}#{id}/v/#{version}"
  defp variable_uri(prompt_id, var_name), do: "#{@user_prompt_ns}#{prompt_id}/var/#{var_name}"

  defp jido(term), do: "#{@jido_ns}#{term}"
  defp rdf(term), do: "#{@rdf_ns}#{term}"

  # Private: Triple builders

  defp add_prompt_triples(triples, prompt, uri) do
    type_class = Map.get(@type_mapping, prompt.type, "Prompt")

    triples
    |> add_triple(uri, rdf("type"), {:uri, jido(type_class)})
    |> add_triple(uri, jido("promptId"), {:literal, prompt.id})
    |> add_triple(uri, jido("promptName"), {:literal, prompt.name})
    |> maybe_add_triple(uri, jido("promptSlug"), prompt.slug, prompt.slug != prompt.id)
    |> maybe_add_triple(uri, jido("promptDescription"), prompt.description)
    |> maybe_add_datetime(uri, jido("promptCreatedAt"), prompt.created_at)
    |> maybe_add_datetime(uri, jido("promptModifiedAt"), prompt.modified_at)
    |> maybe_add_author(uri, prompt.author)
  end

  defp add_content_triples(triples, prompt, prompt_uri, content_uri) do
    triples
    |> add_triple(prompt_uri, jido("hasPromptContent"), {:uri, content_uri})
    |> add_triple(content_uri, rdf("type"), {:uri, jido("PromptContent")})
    |> add_triple(content_uri, jido("contentText"), {:literal, prompt.content})
    |> add_triple(content_uri, jido("hasContentFormat"), {:uri, jido("MarkdownFormat")})
  end

  defp add_version_triples(triples, prompt, prompt_uri, version_uri) do
    triples
    |> add_triple(prompt_uri, jido("currentPromptVersion"), {:uri, version_uri})
    |> add_triple(prompt_uri, jido("hasPromptVersion"), {:uri, version_uri})
    |> add_triple(version_uri, rdf("type"), {:uri, jido("PromptVersion")})
    |> add_triple(version_uri, jido("versionNumber"), {:literal, prompt.version})
    |> add_triple(version_uri, jido("versionOf"), {:uri, prompt_uri})
    |> add_triple(version_uri, jido("hasPromptStatus"), {:uri, jido("PromptPublished")})
  end

  defp add_variable_triples(triples, prompt, prompt_uri) do
    Enum.reduce(prompt.variables, triples, fn var, acc ->
      var_uri = variable_uri(prompt.id, var.name)

      acc
      |> add_triple(prompt_uri, jido("hasVariable"), {:uri, var_uri})
      |> add_triple(var_uri, rdf("type"), {:uri, jido("PromptVariable")})
      |> add_triple(var_uri, jido("variableName"), {:literal, var.name})
      |> add_triple(var_uri, jido("variableType"), {:literal, var.type})
      |> add_triple(var_uri, jido("variableRequired"), {:literal, var.required, :boolean})
      |> maybe_add_triple(var_uri, jido("variableDefault"), var[:default])
      |> maybe_add_triple(var_uri, jido("variableDescription"), var[:description])
    end)
  end

  defp add_category_triples(triples, prompt, prompt_uri) do
    cats = prompt.categories

    triples
    |> add_category_list(prompt_uri, jido("hasDomainCategory"), cats[:domain])
    |> add_category_list(prompt_uri, jido("hasTaskCategory"), cats[:task])
    |> add_category_list(prompt_uri, jido("hasTechniqueCategory"), cats[:technique])
    |> add_category_list(prompt_uri, jido("hasComplexityCategory"), cats[:complexity])
    |> add_category_list(prompt_uri, jido("hasAudienceCategory"), cats[:audience])
  end

  defp add_category_list(triples, _uri, _pred, nil), do: triples

  defp add_category_list(triples, uri, pred, cats) when is_list(cats) do
    Enum.reduce(cats, triples, fn cat, acc ->
      cat_uri = category_uri(cat)
      add_triple(acc, uri, pred, {:uri, cat_uri})
    end)
  end

  defp add_category_list(triples, uri, pred, cat) do
    add_category_list(triples, uri, pred, [cat])
  end

  defp category_uri(slug) when is_binary(slug) do
    # Check if it's a user category or system category
    # User categories start with "user:" or don't have a known pattern
    cond do
      String.starts_with?(slug, "user:") ->
        "#{@user_category_ns}#{String.replace_prefix(slug, "user:", "")}"

      is_system_category?(slug) ->
        # Convert slug to CamelCase for system categories
        camel = slug_to_camel(slug)
        jido("#{camel}Domain")

      true ->
        # Assume user category
        "#{@user_category_ns}#{slug}"
    end
  end

  defp is_system_category?(slug) do
    system_categories = ~w(
      coding code-generation code-review debugging refactoring testing
      documentation architecture analysis planning
      elixir otp phoenix ecto ash commanded genserver supervisor liveview
      generation transformation evaluation extraction summarization
      classification reasoning validation explanation
      zero-shot few-shot chain-of-thought tree-of-thought self-consistency
      react reflection role-play structured-output
      simple intermediate advanced expert
      beginner practitioner developer
    )

    slug in system_categories
  end

  defp slug_to_camel(slug) do
    slug
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp add_target_triples(triples, prompt, prompt_uri) do
    target = prompt.target

    triples
    |> maybe_add_triple(prompt_uri, jido("targetLanguage"), target[:language])
    |> maybe_add_list(prompt_uri, jido("targetFramework"), target[:framework])
    |> maybe_add_triple(prompt_uri, jido("targetModel"), target[:model])
    |> maybe_add_triple(prompt_uri, jido("modelFamily"), target[:model_family])
    |> maybe_add_integer(prompt_uri, jido("minContextLength"), target[:min_context])
  end

  defp add_tag_triples(triples, prompt, prompt_uri) do
    Enum.reduce(prompt.tags, triples, fn tag, acc ->
      add_triple(acc, prompt_uri, jido("hasPromptTag"), {:literal, tag})
    end)
  end

  # Private: Triple helpers

  defp add_triple(triples, s, p, o), do: [{s, p, o} | triples]

  defp maybe_add_triple(triples, _s, _p, nil), do: triples
  defp maybe_add_triple(triples, _s, _p, _v, false), do: triples

  defp maybe_add_triple(triples, s, p, v, true) do
    add_triple(triples, s, p, {:literal, v})
  end

  defp maybe_add_triple(triples, s, p, v) when not is_nil(v) do
    add_triple(triples, s, p, {:literal, v})
  end

  defp maybe_add_list(triples, _s, _p, nil), do: triples

  defp maybe_add_list(triples, s, p, list) when is_list(list) do
    Enum.reduce(list, triples, fn item, acc ->
      add_triple(acc, s, p, {:literal, item})
    end)
  end

  defp maybe_add_list(triples, s, p, item), do: add_triple(triples, s, p, {:literal, item})

  defp maybe_add_integer(triples, _s, _p, nil), do: triples

  defp maybe_add_integer(triples, s, p, i) do
    add_triple(triples, s, p, {:literal, i, :integer})
  end

  defp maybe_add_datetime(triples, _s, _p, nil), do: triples

  defp maybe_add_datetime(triples, s, p, %DateTime{} = dt) do
    add_triple(triples, s, p, {:literal, DateTime.to_iso8601(dt), :datetime})
  end

  defp maybe_add_author(triples, _uri, nil), do: triples

  defp maybe_add_author(triples, uri, author) do
    author_uri = "https://jido.ai/agents/#{author}"
    add_triple(triples, uri, jido("promptCreatedBy"), {:uri, author_uri})
  end

  # Private: Triple formatting for SPARQL

  defp format_triple({s, p, {:uri, o}}) do
    "  <#{s}> <#{p}> <#{o}> ."
  end

  defp format_triple({s, p, {:literal, o}}) when is_binary(o) do
    escaped = escape_string(o)
    "  <#{s}> <#{p}> \"\"\"#{escaped}\"\"\" ."
  end

  defp format_triple({s, p, {:literal, o}}) when is_boolean(o) do
    "  <#{s}> <#{p}> #{o} ."
  end

  defp format_triple({s, p, {:literal, o}}) when is_number(o) do
    "  <#{s}> <#{p}> #{o} ."
  end

  defp format_triple({s, p, {:literal, o, :boolean}}) do
    "  <#{s}> <#{p}> #{o} ."
  end

  defp format_triple({s, p, {:literal, o, :integer}}) do
    "  <#{s}> <#{p}> \"#{o}\"^^xsd:integer ."
  end

  defp format_triple({s, p, {:literal, o, :datetime}}) do
    "  <#{s}> <#{p}> \"#{o}\"^^xsd:dateTime ."
  end

  defp escape_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  # Private: Parsing helpers

  defp get_value(data, key, default \\ nil) do
    Map.get(data, key, default)
  end

  defp get_list(data, key) do
    case Map.get(data, key) do
      nil -> []
      list when is_list(list) -> list
      item -> [item]
    end
  end

  defp parse_type(data) do
    case Map.get(data, "type") do
      uri when is_binary(uri) ->
        cond do
          String.ends_with?(uri, "SystemPrompt") -> :system
          String.ends_with?(uri, "UserPrompt") -> :user
          String.ends_with?(uri, "AssistantPrompt") -> :assistant
          String.ends_with?(uri, "MetaPrompt") -> :meta
          String.ends_with?(uri, "PromptFragment") -> :fragment
          String.ends_with?(uri, "ToolPrompt") -> :tool
          String.ends_with?(uri, "ValidationPrompt") -> :validation
          true -> :system
        end

      _ ->
        :system
    end
  end

  defp get_content(data) do
    case Map.get(data, "content") do
      %{"contentText" => text} -> text
      _ -> ""
    end
  end

  defp get_current_version(data) do
    case Map.get(data, "currentVersion") do
      %{"versionNumber" => version} -> version
      _ -> "1.0.0"
    end
  end

  defp get_categories(data) do
    %{
      domain: parse_category_values(Map.get(data, "hasDomainCategory")),
      task: parse_category_value(Map.get(data, "hasTaskCategory")),
      technique: parse_category_value(Map.get(data, "hasTechniqueCategory")),
      complexity: parse_category_value(Map.get(data, "hasComplexityCategory")),
      audience: parse_category_value(Map.get(data, "hasAudienceCategory"))
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
    |> Map.new()
  end

  defp parse_category_values(nil), do: []
  defp parse_category_values(list) when is_list(list), do: Enum.map(list, &parse_category_value/1)
  defp parse_category_values(value), do: [parse_category_value(value)]

  defp parse_category_value(nil), do: nil

  defp parse_category_value(uri) when is_binary(uri) do
    cond do
      String.contains?(uri, "/user/categories/") ->
        uri |> String.split("/") |> List.last()

      String.contains?(uri, "#") ->
        uri
        |> String.split("#")
        |> List.last()
        |> String.replace(~r/Domain$/, "")
        |> camel_to_slug()

      true ->
        uri
    end
  end

  defp camel_to_slug(camel) do
    camel
    |> String.replace(~r/([A-Z])/, "-\\1")
    |> String.downcase()
    |> String.trim_leading("-")
  end

  defp get_variables(data) do
    case Map.get(data, "variables") do
      nil ->
        []

      vars when is_list(vars) ->
        Enum.map(vars, fn var ->
          %{
            name: var["variableName"],
            type: var["variableType"] || "string",
            required: var["variableRequired"] || false,
            default: var["variableDefault"],
            description: var["variableDescription"]
          }
        end)

      _ ->
        []
    end
  end

  defp get_target(data) do
    %{
      language: Map.get(data, "targetLanguage"),
      framework: get_list(data, "targetFramework"),
      model: Map.get(data, "targetModel"),
      model_family: Map.get(data, "modelFamily"),
      min_context: Map.get(data, "minContextLength")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] end)
    |> Map.new()
  end

  defp get_datetime(data, key) do
    case Map.get(data, key) do
      nil ->
        nil

      str when is_binary(str) ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_author(data) do
    case Map.get(data, "promptCreatedBy") do
      nil -> nil
      uri when is_binary(uri) -> uri |> String.split("/") |> List.last()
      _ -> nil
    end
  end
end
