defmodule JidoCode.Prompt.Defaults do
  @moduledoc """
  Default categories and initialization for the JidoCode prompt system.
  
  This module handles:
  - Initializing default prompt categories in the triplestore
  - Creating user-defined categories
  - Seeding example prompts (optional)
  
  ## Usage
  
  Call `init/0` during application startup to ensure default categories
  are present in the triplestore:
  
      defmodule JidoCode.Application do
        def start(_type, _args) do
          # ... other setup
          JidoCode.Prompt.Defaults.init()
          # ...
        end
      end
  """

  alias JidoCode.Knowledge.Store

  @jido_ns "https://jido.ai/ontology#"
  @user_category_ns "https://jido.ai/user/categories/"

  @doc """
  Initialize default categories in the triplestore.
  
  This is idempotent - calling multiple times won't create duplicates.
  """
  @spec init() :: :ok | {:error, term()}
  def init do
    with :ok <- ensure_category_scheme(),
         :ok <- init_domain_categories(),
         :ok <- init_task_categories(),
         :ok <- init_technique_categories(),
         :ok <- init_complexity_categories(),
         :ok <- init_audience_categories() do
      :ok
    end
  end

  @doc """
  Create a new user-defined category.
  
  ## Parameters
  
  - `name` - Human-readable category name
  - `type` - Category type: `:domain`, `:task`, `:technique`, `:complexity`, `:audience`
  - `parent` - Optional parent category slug
  
  ## Example
  
      iex> Defaults.create_category("My Custom Domain", :domain, "coding")
      :ok
  """
  @spec create_category(String.t(), atom(), String.t() | nil) :: :ok | {:error, term()}
  def create_category(name, type, parent \\ nil) do
    slug = slugify(name)
    uri = "#{@user_category_ns}#{slug}"
    parent_uri = if parent, do: category_uri(parent, type), else: type_top_concept(type)
    type_class = type_to_class(type)

    query = """
    PREFIX jido: <#{@jido_ns}>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    INSERT DATA {
      <#{uri}> a jido:#{type_class} ;
               skos:prefLabel "#{escape(name)}" ;
               skos:broader <#{parent_uri}> ;
               skos:inScheme jido:UserPromptCategoryScheme .
    }
    """

    Store.update(query)
  end

  @doc """
  List all categories of a given type.
  """
  @spec list_categories(atom()) :: {:ok, [map()]} | {:error, term()}
  def list_categories(type) do
    type_class = type_to_class(type)

    query = """
    PREFIX jido: <#{@jido_ns}>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    SELECT ?uri ?label ?parent WHERE {
      ?uri a/rdfs:subClassOf* jido:#{type_class} .
      ?uri skos:prefLabel ?label .
      OPTIONAL { ?uri skos:broader ?parent }
    }
    ORDER BY ?label
    """

    Store.query(query)
  end

  @doc """
  Delete a user-defined category.
  
  System categories cannot be deleted.
  """
  @spec delete_category(String.t()) :: :ok | {:error, term()}
  def delete_category(slug) do
    uri = "#{@user_category_ns}#{slug}"

    # Only delete user categories
    query = """
    PREFIX jido: <#{@jido_ns}>

    DELETE WHERE {
      <#{uri}> ?p ?o .
    }
    """

    Store.update(query)
  end

  @doc """
  Seed example prompts for demonstration.
  
  These are optional and can be called manually.
  """
  @spec seed_examples() :: :ok | {:error, term()}
  def seed_examples do
    examples = [
      example_elixir_review(),
      example_genserver_template(),
      example_error_handling_fragment()
    ]

    Enum.each(examples, fn prompt_data ->
      prompt = JidoCode.Prompt.new(prompt_data)
      JidoCode.Prompt.Repository.create(prompt)
    end)

    :ok
  end

  # Private: Initialization

  defp ensure_category_scheme do
    query = """
    PREFIX jido: <#{@jido_ns}>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

    INSERT {
      jido:UserPromptCategoryScheme a jido:PromptCategoryScheme, skos:ConceptScheme ;
        rdfs:label "User Prompt Categories" .
    }
    WHERE {
      FILTER NOT EXISTS { jido:UserPromptCategoryScheme a skos:ConceptScheme }
    }
    """

    Store.update(query)
  end

  defp init_domain_categories do
    categories = [
      # Top-level
      {"Coding", nil},
      {"Documentation", nil},
      {"Analysis", nil},
      {"Planning", nil},
      # Coding sub-categories
      {"Code Generation", "coding"},
      {"Code Review", "coding"},
      {"Debugging", "coding"},
      {"Refactoring", "coding"},
      {"Testing", "coding"},
      {"Architecture", "coding"},
      # Elixir-specific
      {"Elixir", "coding"},
      {"OTP", "elixir"},
      {"GenServer", "otp"},
      {"Supervisor", "otp"},
      {"Phoenix", "elixir"},
      {"LiveView", "phoenix"},
      {"Channels", "phoenix"},
      {"Ecto", "elixir"},
      {"Ash", "elixir"},
      {"Commanded", "elixir"}
    ]

    insert_categories(categories, :domain)
  end

  defp init_task_categories do
    categories = [
      {"Generation", nil},
      {"Transformation", nil},
      {"Evaluation", nil},
      {"Extraction", nil},
      {"Summarization", nil},
      {"Classification", nil},
      {"Reasoning", nil},
      {"Validation", nil},
      {"Explanation", nil}
    ]

    insert_categories(categories, :task)
  end

  defp init_technique_categories do
    categories = [
      {"Zero-Shot", nil},
      {"Few-Shot", nil},
      {"Chain-of-Thought", nil},
      {"Tree-of-Thought", nil},
      {"Self-Consistency", nil},
      {"ReAct", nil},
      {"Reflection", nil},
      {"Role-Play", nil},
      {"Structured-Output", nil}
    ]

    insert_categories(categories, :technique)
  end

  defp init_complexity_categories do
    categories = [
      {"Simple", nil},
      {"Intermediate", nil},
      {"Advanced", nil},
      {"Expert", nil}
    ]

    insert_categories(categories, :complexity)
  end

  defp init_audience_categories do
    categories = [
      {"Beginner", nil},
      {"Practitioner", nil},
      {"Advanced", nil},
      {"Developer", nil}
    ]

    insert_categories(categories, :audience)
  end

  defp insert_categories(categories, type) do
    type_class = type_to_class(type)
    top_concept = type_top_concept(type)

    triples =
      categories
      |> Enum.map(fn {name, parent} ->
        slug = slugify(name)
        uri = "#{@jido_ns}#{camelize(slug)}#{type_suffix(type)}"

        parent_uri =
          if parent do
            "#{@jido_ns}#{camelize(parent)}#{type_suffix(type)}"
          else
            top_concept
          end

        """
          <#{uri}> a jido:#{type_class} ;
                   skos:prefLabel "#{name}" ;
                   skos:broader <#{parent_uri}> ;
                   skos:inScheme jido:JidoPromptCategoryScheme .
        """
      end)
      |> Enum.join("\n")

    query = """
    PREFIX jido: <#{@jido_ns}>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>

    INSERT DATA {
    #{triples}
    }
    """

    Store.update(query)
  end

  # Private: Helpers

  defp type_to_class(:domain), do: "DomainCategory"
  defp type_to_class(:task), do: "TaskCategory"
  defp type_to_class(:technique), do: "TechniqueCategory"
  defp type_to_class(:complexity), do: "ComplexityCategory"
  defp type_to_class(:audience), do: "AudienceCategory"

  defp type_top_concept(:domain), do: "#{@jido_ns}DomainCategories"
  defp type_top_concept(:task), do: "#{@jido_ns}TaskCategories"
  defp type_top_concept(:technique), do: "#{@jido_ns}TechniqueCategories"
  defp type_top_concept(:complexity), do: "#{@jido_ns}ComplexityCategories"
  defp type_top_concept(:audience), do: "#{@jido_ns}AudienceCategories"

  defp type_suffix(:domain), do: "Domain"
  defp type_suffix(:task), do: "Task"
  defp type_suffix(:technique), do: "Technique"
  defp type_suffix(:complexity), do: "Complexity"
  defp type_suffix(:audience), do: "Audience"

  defp category_uri(slug, type) do
    "#{@jido_ns}#{camelize(slug)}#{type_suffix(type)}"
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp camelize(slug) do
    slug
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  # Private: Example prompts

  defp example_elixir_review do
    %{
      id: "elixir-code-review",
      name: "Elixir Code Review",
      type: :system,
      description: "Comprehensive code review for Elixir projects focusing on OTP patterns and best practices.",
      categories: %{
        domain: ["code-review", "elixir"],
        task: "evaluation",
        technique: "role-play",
        complexity: "intermediate",
        audience: "developer"
      },
      variables: [
        %{name: "code", type: "string", required: true, description: "The code to review"},
        %{name: "context", type: "string", required: false, default: "General review", description: "Review focus"}
      ],
      tags: ["elixir", "review", "otp", "best-practices"],
      target: %{language: "elixir", model_family: "Claude"},
      content: """
      # Elixir Code Review

      You are an expert Elixir developer conducting a thorough code review.

      ## Code to Review

      ```elixir
      {{code}}
      ```

      ## Review Context
      {{context}}

      ## Review Checklist

      ### 1. OTP Patterns
      - Proper use of GenServer, Supervisor, and other OTP behaviours
      - Appropriate restart strategies
      - Process isolation and fault tolerance

      ### 2. Functional Style
      - Immutability and pure functions
      - Proper use of pattern matching
      - Pipeline usage where appropriate

      ### 3. Error Handling
      - Tagged tuple returns ({:ok, _} / {:error, _})
      - Appropriate use of with statements
      - Let-it-crash philosophy adherence

      ### 4. Code Quality
      - Naming conventions
      - Documentation (@moduledoc, @doc, @spec)
      - Test coverage considerations

      ## Output Format

      Provide feedback as:
      1. **Summary**: 1-2 sentence overall assessment
      2. **Critical Issues**: Must fix
      3. **Suggestions**: Nice to have
      4. **Positive Notes**: What's done well
      """
    }
  end

  defp example_genserver_template do
    %{
      id: "genserver-template",
      name: "GenServer Template Generator",
      type: :system,
      description: "Generates a well-structured GenServer module from requirements.",
      categories: %{
        domain: ["code-generation", "otp", "genserver"],
        task: "generation",
        technique: "structured-output",
        complexity: "intermediate",
        audience: "developer"
      },
      variables: [
        %{name: "module_name", type: "string", required: true, description: "The module name"},
        %{name: "state_fields", type: "string", required: true, description: "State fields description"},
        %{name: "operations", type: "string", required: false, default: "CRUD operations", description: "Operations needed"}
      ],
      tags: ["elixir", "genserver", "otp", "template", "generation"],
      target: %{language: "elixir"},
      content: """
      # GenServer Template Generator

      Generate a complete, well-documented GenServer module.

      ## Requirements

      - **Module Name**: {{module_name}}
      - **State Fields**: {{state_fields}}
      - **Operations**: {{operations}}

      ## Template Structure

      Generate a GenServer with:

      1. Module documentation (@moduledoc)
      2. Type specifications for state
      3. Client API functions (public interface)
      4. Server callbacks (handle_call, handle_cast, handle_info)
      5. Private helper functions
      6. Proper error handling

      ## Output

      Provide the complete module code with:
      - All necessary `use GenServer` setup
      - `start_link/1` with proper child_spec
      - Type specs for all public functions
      - Inline comments explaining design decisions
      """
    }
  end

  defp example_error_handling_fragment do
    %{
      id: "elixir-error-handling",
      name: "Elixir Error Handling Fragment",
      type: :fragment,
      description: "Reusable fragment with Elixir error handling guidelines.",
      categories: %{
        domain: ["elixir"],
        task: "generation"
      },
      variables: [],
      tags: ["elixir", "error-handling", "fragment", "guidelines"],
      content: """
      ## Error Handling Guidelines

      Follow these Elixir error handling conventions:

      ### Tagged Tuples
      Always use `{:ok, result}` and `{:error, reason}` for functions that can fail.

      ### With Statements
      Chain fallible operations with `with`:
      ```elixir
      with {:ok, user} <- find_user(id),
           {:ok, account} <- get_account(user),
           {:ok, balance} <- check_balance(account) do
        {:ok, balance}
      else
        {:error, :user_not_found} -> {:error, "User not found"}
        {:error, :insufficient_funds} -> {:error, "Insufficient funds"}
        error -> error
      end
      ```

      ### Let It Crash
      For unexpected errors, let the process crash and rely on supervision.
      Only rescue exceptions at system boundaries (e.g., API endpoints).

      ### Custom Errors
      Define custom exception modules for domain-specific errors:
      ```elixir
      defmodule MyApp.ValidationError do
        defexception [:message, :field]
      end
      ```
      """
    }
  end
end
