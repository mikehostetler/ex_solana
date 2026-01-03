defmodule JidoCode.Prompt.Repository do
  @moduledoc """
  CRUD operations for prompts in the triplestore.
  
  This module provides the persistence layer for user-defined prompts,
  using the JidoCode knowledge graph as the backing store.
  
  ## Operations
  
  - `create/1` - Create a new prompt
  - `get/1` - Get a prompt by ID or slug
  - `update/2` - Update an existing prompt
  - `delete/1` - Delete a prompt
  - `list/1` - List prompts with optional filters
  - `search/1` - Full-text search across prompts
  - `exists?/1` - Check if a prompt exists
  """

  alias JidoCode.Prompt
  alias JidoCode.Prompt.RDFMapper
  alias JidoCode.Knowledge.Store

  @user_prompt_ns "https://jido.ai/user/prompts/"

  @doc """
  Create a new prompt in the triplestore.
  
  ## Example
  
      iex> prompt = %JidoCode.Prompt{id: "my-prompt", name: "My Prompt", ...}
      iex> {:ok, saved} = JidoCode.Prompt.Repository.create(prompt)
      iex> saved.uri
      "https://jido.ai/user/prompts/my-prompt"
  """
  @spec create(Prompt.t()) :: {:ok, Prompt.t()} | {:error, term()}
  def create(%Prompt{} = prompt) do
    with :ok <- validate_unique_id(prompt.id),
         query <- RDFMapper.to_sparql_insert(prompt),
         :ok <- Store.update(query) do
      {:ok, %{prompt | uri: "#{@user_prompt_ns}#{prompt.id}"}}
    end
  end

  @doc """
  Get a prompt by ID or slug.
  
  ## Example
  
      iex> {:ok, prompt} = JidoCode.Prompt.Repository.get("my-prompt")
      iex> prompt.name
      "My Prompt"
  """
  @spec get(String.t()) :: {:ok, Prompt.t()} | {:error, :not_found | term()}
  def get(id_or_slug) do
    query = """
    PREFIX jido: <https://jido.ai/ontology#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    SELECT ?id WHERE {
      ?prompt a ?type .
      ?type rdfs:subClassOf* jido:Prompt .
      {
        ?prompt jido:promptId "#{escape(id_or_slug)}" .
      } UNION {
        ?prompt jido:promptSlug "#{escape(id_or_slug)}" .
      }
      ?prompt jido:promptId ?id .
    }
    LIMIT 1
    """

    case Store.query(query) do
      {:ok, [%{"id" => id}]} ->
        load_prompt(id)

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Update an existing prompt.
  
  The changes map can include any Prompt field to update.
  
  ## Example
  
      iex> {:ok, updated} = JidoCode.Prompt.Repository.update("my-prompt", %{name: "New Name"})
      iex> updated.name
      "New Name"
  """
  @spec update(String.t(), map()) :: {:ok, Prompt.t()} | {:error, term()}
  def update(id, changes) do
    with {:ok, existing} <- get(id),
         updated <- apply_changes(existing, changes),
         updated <- %{updated | modified_at: DateTime.utc_now()},
         :ok <- delete(id),
         {:ok, prompt} <- create(updated) do
      {:ok, prompt}
    end
  end

  @doc """
  Delete a prompt by ID.
  
  ## Example
  
      iex> :ok = JidoCode.Prompt.Repository.delete("my-prompt")
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(id) do
    query = RDFMapper.to_sparql_delete(id)
    Store.update(query)
  end

  @doc """
  List all prompts, optionally filtered.
  
  ## Options
  
  - `:category` - Filter by category slug
  - `:type` - Filter by prompt type (system, user, etc.)
  - `:tag` - Filter by tag
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Offset for pagination (default: 0)
  
  ## Example
  
      iex> {:ok, prompts} = JidoCode.Prompt.Repository.list(category: "code-review")
      iex> length(prompts)
      3
  """
  @spec list(keyword()) :: {:ok, [Prompt.t()]} | {:error, term()}
  def list(opts \\ []) do
    query = build_list_query(opts)

    case Store.query(query) do
      {:ok, results} ->
        prompts =
          results
          |> Enum.map(fn %{"id" => id} -> get(id) end)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, p} -> p end)

        {:ok, prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search prompts by text query.
  
  Searches across name, description, tags, and content.
  
  ## Example
  
      iex> {:ok, prompts} = JidoCode.Prompt.Repository.search("elixir review")
      iex> length(prompts) > 0
      true
  """
  @spec search(String.t()) :: {:ok, [Prompt.t()]} | {:error, term()}
  def search(query_text) do
    escaped = escape(query_text)

    query = """
    PREFIX jido: <https://jido.ai/ontology#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    SELECT DISTINCT ?id WHERE {
      ?prompt a ?type .
      ?type rdfs:subClassOf* jido:Prompt .
      ?prompt jido:promptId ?id .

      {
        ?prompt jido:promptName ?name .
        FILTER(CONTAINS(LCASE(?name), LCASE("#{escaped}")))
      } UNION {
        ?prompt jido:promptDescription ?desc .
        FILTER(CONTAINS(LCASE(?desc), LCASE("#{escaped}")))
      } UNION {
        ?prompt jido:hasPromptTag ?tag .
        FILTER(CONTAINS(LCASE(?tag), LCASE("#{escaped}")))
      } UNION {
        ?prompt jido:hasPromptContent ?content .
        ?content jido:contentText ?text .
        FILTER(CONTAINS(LCASE(?text), LCASE("#{escaped}")))
      }
    }
    """

    case Store.query(query) do
      {:ok, results} ->
        prompts =
          results
          |> Enum.map(fn %{"id" => id} -> get(id) end)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, p} -> p end)

        {:ok, prompts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a prompt exists by ID or slug.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(id_or_slug) do
    case get(id_or_slug) do
      {:ok, _} -> true
      {:error, :not_found} -> false
      _ -> false
    end
  end

  @doc """
  Get prompts by category.
  """
  @spec by_category(String.t()) :: {:ok, [Prompt.t()]} | {:error, term()}
  def by_category(category_slug) do
    list(category: category_slug)
  end

  @doc """
  Get prompts by type.
  """
  @spec by_type(atom()) :: {:ok, [Prompt.t()]} | {:error, term()}
  def by_type(type) when is_atom(type) do
    list(type: type)
  end

  @doc """
  Count total prompts, optionally filtered.
  """
  @spec count(keyword()) :: {:ok, integer()} | {:error, term()}
  def count(opts \\ []) do
    query = build_count_query(opts)

    case Store.query(query) do
      {:ok, [%{"count" => count}]} -> {:ok, count}
      {:ok, []} -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp validate_unique_id(id) do
    if exists?(id) do
      {:error, {:already_exists, id}}
    else
      :ok
    end
  end

  defp load_prompt(id) do
    # Build a CONSTRUCT or DESCRIBE query to get all prompt data
    uri = RDFMapper.prompt_uri(id)

    query = """
    PREFIX jido: <https://jido.ai/ontology#>

    SELECT ?p ?o WHERE {
      <#{uri}> ?p ?o .
    }
    """

    content_query = """
    PREFIX jido: <https://jido.ai/ontology#>

    SELECT ?p ?o WHERE {
      <#{uri}> jido:hasPromptContent ?content .
      ?content ?p ?o .
    }
    """

    version_query = """
    PREFIX jido: <https://jido.ai/ontology#>

    SELECT ?p ?o WHERE {
      <#{uri}> jido:currentPromptVersion ?version .
      ?version ?p ?o .
    }
    """

    variables_query = """
    PREFIX jido: <https://jido.ai/ontology#>

    SELECT ?var ?p ?o WHERE {
      <#{uri}> jido:hasVariable ?var .
      ?var ?p ?o .
    }
    """

    with {:ok, main_data} <- Store.query(query),
         {:ok, content_data} <- Store.query(content_query),
         {:ok, version_data} <- Store.query(version_query),
         {:ok, var_data} <- Store.query(variables_query) do
      data =
        build_data_map(main_data)
        |> Map.put("content", build_data_map(content_data))
        |> Map.put("currentVersion", build_data_map(version_data))
        |> Map.put("variables", build_variables_list(var_data))

      RDFMapper.from_triples(id, data)
    end
  end

  defp build_data_map(results) do
    Enum.reduce(results, %{}, fn %{"p" => p, "o" => o}, acc ->
      key = extract_local_name(p)
      Map.put(acc, key, o)
    end)
  end

  defp build_variables_list(results) do
    results
    |> Enum.group_by(fn %{"var" => var} -> var end)
    |> Enum.map(fn {_var_uri, props} ->
      Enum.reduce(props, %{}, fn %{"p" => p, "o" => o}, acc ->
        key = extract_local_name(p)
        Map.put(acc, key, o)
      end)
    end)
  end

  defp extract_local_name(uri) do
    cond do
      String.contains?(uri, "#") ->
        uri |> String.split("#") |> List.last()

      String.contains?(uri, "/") ->
        uri |> String.split("/") |> List.last()

      true ->
        uri
    end
  end

  defp apply_changes(prompt, changes) do
    Enum.reduce(changes, prompt, fn {key, value}, acc ->
      if Map.has_key?(acc, key) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp build_list_query(opts) do
    category = Keyword.get(opts, :category)
    type = Keyword.get(opts, :type)
    tag = Keyword.get(opts, :tag)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    filters = []

    filters =
      if category do
        cat_uri = category_to_uri(category)
        [
          """
          ?prompt jido:hasDomainCategory ?cat .
          ?cat skos:broader* <#{cat_uri}> .
          """
          | filters
        ]
      else
        filters
      end

    filters =
      if type do
        type_class = type_to_class(type)
        ["?prompt a jido:#{type_class} ." | filters]
      else
        filters
      end

    filters =
      if tag do
        ["?prompt jido:hasPromptTag \"#{escape(tag)}\" ." | filters]
      else
        filters
      end

    filter_clause = Enum.join(filters, "\n")

    """
    PREFIX jido: <https://jido.ai/ontology#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>

    SELECT ?id ?name WHERE {
      ?prompt a ?type .
      ?type rdfs:subClassOf* jido:Prompt .
      ?prompt jido:promptId ?id .
      ?prompt jido:promptName ?name .
      #{filter_clause}
    }
    ORDER BY ?name
    LIMIT #{limit}
    OFFSET #{offset}
    """
  end

  defp build_count_query(opts) do
    category = Keyword.get(opts, :category)

    filter_clause =
      if category do
        cat_uri = category_to_uri(category)

        """
        ?prompt jido:hasDomainCategory ?cat .
        ?cat skos:broader* <#{cat_uri}> .
        """
      else
        ""
      end

    """
    PREFIX jido: <https://jido.ai/ontology#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>

    SELECT (COUNT(DISTINCT ?prompt) as ?count) WHERE {
      ?prompt a ?type .
      ?type rdfs:subClassOf* jido:Prompt .
      #{filter_clause}
    }
    """
  end

  defp category_to_uri(slug) do
    # Convert slug to category URI
    camel =
      slug
      |> String.split("-")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    "https://jido.ai/ontology##{camel}Domain"
  end

  defp type_to_class(:system), do: "SystemPrompt"
  defp type_to_class(:user), do: "UserPrompt"
  defp type_to_class(:assistant), do: "AssistantPrompt"
  defp type_to_class(:meta), do: "MetaPrompt"
  defp type_to_class(:fragment), do: "PromptFragment"
  defp type_to_class(:tool), do: "ToolPrompt"
  defp type_to_class(:validation), do: "ValidationPrompt"
  defp type_to_class(_), do: "Prompt"

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
