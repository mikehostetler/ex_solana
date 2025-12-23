defmodule Jido.Character.Ontology.Renderer do
  @moduledoc """
  Renders character schemas and data to semantic web formats.

  Supports exporting:
  - **OWL/RDF-XML** - Schema (TBox) as OWL ontology
  - **RDF Triples** - Data (ABox) as N-Triples or Turtle
  - **JSON-LD** - Combined schema context + data for APIs

  ## Namespace

  The default namespace is `http://jido.ai/character#`. Override with the `:namespace` option.

  ## Examples

      # Export schema as OWL
      Jido.Character.Ontology.Renderer.to_owl()

      # Export character as RDF triples
      {:ok, char} = Jido.Character.new(%{name: "Alex"})
      Jido.Character.Ontology.Renderer.to_rdf(char)

      # Export as JSON-LD
      Jido.Character.Ontology.Renderer.to_jsonld(char)
  """

  @default_namespace "http://jido.ai/character#"
  @rdf_ns "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  @rdfs_ns "http://www.w3.org/2000/01/rdf-schema#"
  @owl_ns "http://www.w3.org/2002/07/owl#"
  @xsd_ns "http://www.w3.org/2001/XMLSchema#"

  @classes [
    {:Character, "A character entity with identity, personality, voice, and memory"},
    {:Identity, "Who the character is - age, background, role, facts"},
    {:Personality, "How the character behaves - traits, values, quirks"},
    {:Trait, "A personality trait with optional intensity"},
    {:Voice, "How the character communicates - tone, style, vocabulary"},
    {:Memory, "Container for character memories with capacity limit"},
    {:MemoryEntry, "Individual memory item with decay properties"},
    {:KnowledgeItem, "Permanent fact the character knows"}
  ]

  @object_properties [
    {:hasIdentity, :Character, :Identity, "Links character to identity"},
    {:hasPersonality, :Character, :Personality, "Links character to personality"},
    {:hasVoice, :Character, :Voice, "Links character to voice"},
    {:hasMemory, :Character, :Memory, "Links character to memory"},
    {:hasKnowledge, :Character, :KnowledgeItem, "Links character to knowledge items"},
    {:hasTrait, :Personality, :Trait, "Links personality to traits"},
    {:hasEntry, :Memory, :MemoryEntry, "Links memory to entries"}
  ]

  @datatype_properties [
    {:name, :Character, :string, "Character's name"},
    {:description, :Character, :string, "Character description"},
    {:age, :Identity, :string, "Age (integer or descriptive string)"},
    {:role, :Identity, :string, "Character's role"},
    {:background, :Identity, :string, "Character's background"},
    {:fact, :Identity, :string, "A fact about the character"},
    {:traitName, :Trait, :string, "Name of the trait"},
    {:intensity, :Trait, :float, "Trait intensity (0.0-1.0)"},
    {:value, :Personality, :string, "A value the character holds"},
    {:quirk, :Personality, :string, "A quirk or idiosyncrasy"},
    {:tone, :Voice, :string, "Communication tone"},
    {:style, :Voice, :string, "Communication style"},
    {:vocabulary, :Voice, :string, "Vocabulary level"},
    {:expression, :Voice, :string, "Common expression"},
    {:content, :MemoryEntry, :string, "Memory content"},
    {:importance, :MemoryEntry, :float, "Memory importance (0.0-1.0)"},
    {:decayRate, :MemoryEntry, :float, "Memory decay rate (0.0-1.0)"},
    {:category, :MemoryEntry, :string, "Memory category"},
    {:timestamp, :MemoryEntry, :dateTime, "When memory was created"},
    {:capacity, :Memory, :integer, "Maximum memory entries"},
    {:knowledgeContent, :KnowledgeItem, :string, "Knowledge content"},
    {:knowledgeCategory, :KnowledgeItem, :string, "Knowledge category"},
    {:knowledgeImportance, :KnowledgeItem, :float, "Knowledge importance"}
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Exports the character ontology schema as OWL/RDF-XML.

  ## Options

  - `:namespace` - Base namespace URI (default: `#{@default_namespace}`)

  ## Examples

      iex> owl = Jido.Character.Ontology.Renderer.to_owl()
      iex> String.contains?(owl, "owl:Class")
      true
  """
  @spec to_owl(keyword()) :: String.t()
  def to_owl(opts \\ []) do
    ns = Keyword.get(opts, :namespace, @default_namespace)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF
      xmlns="#{ns}"
      xmlns:rdf="#{@rdf_ns}"
      xmlns:rdfs="#{@rdfs_ns}"
      xmlns:owl="#{@owl_ns}"
      xmlns:xsd="#{@xsd_ns}"
      xml:base="#{ns}">

      <owl:Ontology rdf:about="">
        <rdfs:label>Jido Character Ontology</rdfs:label>
        <rdfs:comment>Ontology for AI character definitions including identity, personality, voice, and memory.</rdfs:comment>
      </owl:Ontology>

    #{render_owl_classes(ns)}
    #{render_owl_object_properties(ns)}
    #{render_owl_datatype_properties(ns)}
    </rdf:RDF>
    """
  end

  @doc """
  Exports a character as RDF triples.

  ## Options

  - `:namespace` - Base namespace URI (default: `#{@default_namespace}`)
  - `:format` - Output format: `:ntriples` (default) or `:turtle`

  ## Examples

      iex> {:ok, char} = Jido.Character.new(%{name: "Alex"})
      iex> triples = Jido.Character.Ontology.Renderer.to_rdf(char)
      iex> String.contains?(triples, "rdf:type")
      true
  """
  @spec to_rdf(map(), keyword()) :: String.t()
  def to_rdf(%{} = character, opts \\ []) do
    ns = Keyword.get(opts, :namespace, @default_namespace)
    format = Keyword.get(opts, :format, :ntriples)

    triples = character_to_triples(character, ns)

    case format do
      :turtle -> render_turtle(triples, ns)
      :ntriples -> render_ntriples(triples)
    end
  end

  @doc """
  Exports a character as JSON-LD with embedded context.

  ## Options

  - `:namespace` - Base namespace URI (default: `#{@default_namespace}`)

  ## Examples

      iex> {:ok, char} = Jido.Character.new(%{name: "Alex"})
      iex> jsonld = Jido.Character.Ontology.Renderer.to_jsonld(char)
      iex> is_map(jsonld)
      true
  """
  @spec to_jsonld(map(), keyword()) :: map()
  def to_jsonld(%{} = character, opts \\ []) do
    ns = Keyword.get(opts, :namespace, @default_namespace)

    context = %{
      "@vocab" => ns,
      "xsd" => @xsd_ns,
      "name" => %{"@type" => "xsd:string"},
      "description" => %{"@type" => "xsd:string"},
      "age" => %{"@type" => "xsd:string"},
      "intensity" => %{"@type" => "xsd:float"},
      "importance" => %{"@type" => "xsd:float"},
      "decayRate" => %{"@type" => "xsd:float"},
      "capacity" => %{"@type" => "xsd:integer"},
      "timestamp" => %{"@type" => "xsd:dateTime"}
    }

    data = character_to_jsonld_data(character, ns)

    Map.put(data, "@context", context)
  end

  @doc """
  Returns the list of ontology classes.
  """
  @spec classes() :: [{atom(), String.t()}]
  def classes, do: @classes

  @doc """
  Returns the list of object properties.
  """
  @spec object_properties() :: [{atom(), atom(), atom(), String.t()}]
  def object_properties, do: @object_properties

  @doc """
  Returns the list of datatype properties.
  """
  @spec datatype_properties() :: [{atom(), atom(), atom(), String.t()}]
  def datatype_properties, do: @datatype_properties

  # ---------------------------------------------------------------------------
  # OWL Rendering
  # ---------------------------------------------------------------------------

  defp render_owl_classes(ns) do
    @classes
    |> Enum.map(fn {name, comment} ->
      """
        <owl:Class rdf:about="#{ns}#{name}">
          <rdfs:label>#{name}</rdfs:label>
          <rdfs:comment>#{comment}</rdfs:comment>
        </owl:Class>
      """
    end)
    |> Enum.join("\n")
  end

  defp render_owl_object_properties(ns) do
    @object_properties
    |> Enum.map(fn {name, domain, range, comment} ->
      """
        <owl:ObjectProperty rdf:about="#{ns}#{name}">
          <rdfs:label>#{name}</rdfs:label>
          <rdfs:comment>#{comment}</rdfs:comment>
          <rdfs:domain rdf:resource="#{ns}#{domain}"/>
          <rdfs:range rdf:resource="#{ns}#{range}"/>
        </owl:ObjectProperty>
      """
    end)
    |> Enum.join("\n")
  end

  defp render_owl_datatype_properties(ns) do
    @datatype_properties
    |> Enum.map(fn {name, domain, datatype, comment} ->
      xsd_type = xsd_type(datatype)

      """
        <owl:DatatypeProperty rdf:about="#{ns}#{name}">
          <rdfs:label>#{name}</rdfs:label>
          <rdfs:comment>#{comment}</rdfs:comment>
          <rdfs:domain rdf:resource="#{ns}#{domain}"/>
          <rdfs:range rdf:resource="#{@xsd_ns}#{xsd_type}"/>
        </owl:DatatypeProperty>
      """
    end)
    |> Enum.join("\n")
  end

  defp xsd_type(:string), do: "string"
  defp xsd_type(:integer), do: "integer"
  defp xsd_type(:float), do: "float"
  defp xsd_type(:dateTime), do: "dateTime"
  defp xsd_type(:boolean), do: "boolean"

  # ---------------------------------------------------------------------------
  # RDF Triple Generation
  # ---------------------------------------------------------------------------

  defp character_to_triples(char, ns) do
    char_id = Map.get(char, :id, "unnamed")
    char_uri = "#{ns}character/#{char_id}"

    triples = [
      {char_uri, "#{@rdf_ns}type", "#{ns}Character"}
    ]

    triples = add_literal_triple(triples, char_uri, "#{ns}name", Map.get(char, :name))
    triples = add_literal_triple(triples, char_uri, "#{ns}description", Map.get(char, :description))

    triples = add_identity_triples(triples, char_uri, Map.get(char, :identity), ns)
    triples = add_personality_triples(triples, char_uri, Map.get(char, :personality), ns)
    triples = add_voice_triples(triples, char_uri, Map.get(char, :voice), ns)
    triples = add_memory_triples(triples, char_uri, Map.get(char, :memory), ns)
    triples = add_knowledge_triples(triples, char_uri, Map.get(char, :knowledge, []), ns)

    triples
  end

  defp add_identity_triples(triples, _char_uri, nil, _ns), do: triples

  defp add_identity_triples(triples, char_uri, identity, ns) do
    identity_uri = "#{char_uri}/identity"

    triples = [
      {identity_uri, "#{@rdf_ns}type", "#{ns}Identity"},
      {char_uri, "#{ns}hasIdentity", identity_uri}
      | triples
    ]

    triples = add_literal_triple(triples, identity_uri, "#{ns}age", get_field(identity, :age))
    triples = add_literal_triple(triples, identity_uri, "#{ns}role", get_field(identity, :role))
    triples = add_literal_triple(triples, identity_uri, "#{ns}background", get_field(identity, :background))

    facts = get_field(identity, :facts, [])

    Enum.reduce(facts, triples, fn fact, acc ->
      add_literal_triple(acc, identity_uri, "#{ns}fact", fact)
    end)
  end

  defp add_personality_triples(triples, _char_uri, nil, _ns), do: triples

  defp add_personality_triples(triples, char_uri, personality, ns) do
    personality_uri = "#{char_uri}/personality"

    triples = [
      {personality_uri, "#{@rdf_ns}type", "#{ns}Personality"},
      {char_uri, "#{ns}hasPersonality", personality_uri}
      | triples
    ]

    traits = get_field(personality, :traits, [])

    triples =
      traits
      |> Enum.with_index()
      |> Enum.reduce(triples, fn {trait, idx}, acc ->
        add_trait_triples(acc, personality_uri, trait, idx, ns)
      end)

    values = get_field(personality, :values, [])

    triples =
      Enum.reduce(values, triples, fn value, acc ->
        add_literal_triple(acc, personality_uri, "#{ns}value", value)
      end)

    quirks = get_field(personality, :quirks, [])

    Enum.reduce(quirks, triples, fn quirk, acc ->
      add_literal_triple(acc, personality_uri, "#{ns}quirk", quirk)
    end)
  end

  defp add_trait_triples(triples, personality_uri, trait, idx, ns) when is_binary(trait) do
    trait_uri = "#{personality_uri}/trait/#{idx}"

    [
      {trait_uri, "#{@rdf_ns}type", "#{ns}Trait"},
      {personality_uri, "#{ns}hasTrait", trait_uri},
      {trait_uri, "#{ns}traitName", {:literal, trait}}
      | triples
    ]
  end

  defp add_trait_triples(triples, personality_uri, trait, idx, ns) when is_map(trait) do
    trait_uri = "#{personality_uri}/trait/#{idx}"
    name = get_field(trait, :name)
    intensity = get_field(trait, :intensity)

    triples = [
      {trait_uri, "#{@rdf_ns}type", "#{ns}Trait"},
      {personality_uri, "#{ns}hasTrait", trait_uri}
      | triples
    ]

    triples = add_literal_triple(triples, trait_uri, "#{ns}traitName", name)
    add_literal_triple(triples, trait_uri, "#{ns}intensity", intensity)
  end

  defp add_voice_triples(triples, _char_uri, nil, _ns), do: triples

  defp add_voice_triples(triples, char_uri, voice, ns) do
    voice_uri = "#{char_uri}/voice"

    triples = [
      {voice_uri, "#{@rdf_ns}type", "#{ns}Voice"},
      {char_uri, "#{ns}hasVoice", voice_uri}
      | triples
    ]

    tone = get_field(voice, :tone)
    triples = add_literal_triple(triples, voice_uri, "#{ns}tone", tone && to_string(tone))
    triples = add_literal_triple(triples, voice_uri, "#{ns}style", get_field(voice, :style))

    vocabulary = get_field(voice, :vocabulary)
    triples = add_literal_triple(triples, voice_uri, "#{ns}vocabulary", vocabulary && to_string(vocabulary))

    expressions = get_field(voice, :expressions, [])

    Enum.reduce(expressions, triples, fn expr, acc ->
      add_literal_triple(acc, voice_uri, "#{ns}expression", expr)
    end)
  end

  defp add_memory_triples(triples, _char_uri, nil, _ns), do: triples

  defp add_memory_triples(triples, char_uri, memory, ns) do
    memory_uri = "#{char_uri}/memory"

    triples = [
      {memory_uri, "#{@rdf_ns}type", "#{ns}Memory"},
      {char_uri, "#{ns}hasMemory", memory_uri}
      | triples
    ]

    triples = add_literal_triple(triples, memory_uri, "#{ns}capacity", get_field(memory, :capacity))

    entries = get_field(memory, :entries, [])

    entries
    |> Enum.with_index()
    |> Enum.reduce(triples, fn {entry, idx}, acc ->
      add_memory_entry_triples(acc, memory_uri, entry, idx, ns)
    end)
  end

  defp add_memory_entry_triples(triples, memory_uri, entry, idx, ns) do
    entry_uri = "#{memory_uri}/entry/#{idx}"

    triples = [
      {entry_uri, "#{@rdf_ns}type", "#{ns}MemoryEntry"},
      {memory_uri, "#{ns}hasEntry", entry_uri}
      | triples
    ]

    triples = add_literal_triple(triples, entry_uri, "#{ns}content", get_field(entry, :content))
    triples = add_literal_triple(triples, entry_uri, "#{ns}importance", get_field(entry, :importance))
    triples = add_literal_triple(triples, entry_uri, "#{ns}decayRate", get_field(entry, :decay_rate))
    triples = add_literal_triple(triples, entry_uri, "#{ns}category", get_field(entry, :category))

    timestamp = get_field(entry, :timestamp)

    if timestamp do
      add_literal_triple(triples, entry_uri, "#{ns}timestamp", DateTime.to_iso8601(timestamp))
    else
      triples
    end
  end

  defp add_knowledge_triples(triples, _char_uri, [], _ns), do: triples

  defp add_knowledge_triples(triples, char_uri, knowledge, ns) do
    knowledge
    |> Enum.with_index()
    |> Enum.reduce(triples, fn {item, idx}, acc ->
      item_uri = "#{char_uri}/knowledge/#{idx}"

      acc = [
        {item_uri, "#{@rdf_ns}type", "#{ns}KnowledgeItem"},
        {char_uri, "#{ns}hasKnowledge", item_uri}
        | acc
      ]

      acc = add_literal_triple(acc, item_uri, "#{ns}knowledgeContent", get_field(item, :content))
      acc = add_literal_triple(acc, item_uri, "#{ns}knowledgeCategory", get_field(item, :category))
      add_literal_triple(acc, item_uri, "#{ns}knowledgeImportance", get_field(item, :importance))
    end)
  end

  defp add_literal_triple(triples, _subject, _predicate, nil), do: triples

  defp add_literal_triple(triples, subject, predicate, value) do
    [{subject, predicate, {:literal, value}} | triples]
  end

  # ---------------------------------------------------------------------------
  # N-Triples Rendering
  # ---------------------------------------------------------------------------

  defp render_ntriples(triples) do
    triples
    |> Enum.reverse()
    |> Enum.map(&format_ntriple/1)
    |> Enum.join("\n")
  end

  defp format_ntriple({subject, predicate, {:literal, value}}) do
    escaped = escape_literal(value)
    "<#{subject}> <#{predicate}> #{format_literal(escaped)} ."
  end

  defp format_ntriple({subject, predicate, object}) do
    "<#{subject}> <#{predicate}> <#{object}> ."
  end

  defp format_literal(value) when is_binary(value), do: "\"#{value}\""
  defp format_literal(value) when is_integer(value), do: "\"#{value}\"^^<#{@xsd_ns}integer>"
  defp format_literal(value) when is_float(value), do: "\"#{value}\"^^<#{@xsd_ns}float>"
  defp format_literal(value) when is_boolean(value), do: "\"#{value}\"^^<#{@xsd_ns}boolean>"
  defp format_literal(value), do: "\"#{value}\""

  defp escape_literal(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end

  defp escape_literal(value), do: value

  # ---------------------------------------------------------------------------
  # Turtle Rendering
  # ---------------------------------------------------------------------------

  defp render_turtle(triples, ns) do
    prefixes = """
    @prefix : <#{ns}> .
    @prefix rdf: <#{@rdf_ns}> .
    @prefix rdfs: <#{@rdfs_ns}> .
    @prefix xsd: <#{@xsd_ns}> .

    """

    grouped =
      triples
      |> Enum.reverse()
      |> Enum.group_by(fn {subject, _, _} -> subject end)

    body =
      grouped
      |> Enum.map(fn {subject, subject_triples} ->
        predicates =
          subject_triples
          |> Enum.map(fn {_, predicate, object} ->
            pred = shorten_uri(predicate, ns)
            obj = format_turtle_object(object, ns)
            "  #{pred} #{obj}"
          end)
          |> Enum.join(" ;\n")

        "<#{subject}>\n#{predicates} ."
      end)
      |> Enum.join("\n\n")

    prefixes <> body
  end

  defp shorten_uri(uri, ns) do
    cond do
      String.starts_with?(uri, ns) -> ":" <> String.replace_prefix(uri, ns, "")
      String.starts_with?(uri, @rdf_ns) -> "rdf:" <> String.replace_prefix(uri, @rdf_ns, "")
      String.starts_with?(uri, @rdfs_ns) -> "rdfs:" <> String.replace_prefix(uri, @rdfs_ns, "")
      String.starts_with?(uri, @xsd_ns) -> "xsd:" <> String.replace_prefix(uri, @xsd_ns, "")
      true -> "<#{uri}>"
    end
  end

  defp format_turtle_object({:literal, value}, _ns) when is_binary(value) do
    "\"#{escape_literal(value)}\""
  end

  defp format_turtle_object({:literal, value}, _ns) when is_integer(value) do
    "#{value}"
  end

  defp format_turtle_object({:literal, value}, _ns) when is_float(value) do
    "#{value}"
  end

  defp format_turtle_object({:literal, value}, _ns) do
    "\"#{value}\""
  end

  defp format_turtle_object(uri, ns) do
    cond do
      String.starts_with?(uri, ns) -> ":" <> String.replace_prefix(uri, ns, "")
      true -> "<#{uri}>"
    end
  end

  # ---------------------------------------------------------------------------
  # JSON-LD Rendering
  # ---------------------------------------------------------------------------

  defp character_to_jsonld_data(char, ns) do
    char_id = Map.get(char, :id, "unnamed")

    data = %{
      "@id" => "#{ns}character/#{char_id}",
      "@type" => "Character"
    }

    data = put_if_present(data, "name", Map.get(char, :name))
    data = put_if_present(data, "description", Map.get(char, :description))

    data = add_identity_jsonld(data, Map.get(char, :identity))
    data = add_personality_jsonld(data, Map.get(char, :personality))
    data = add_voice_jsonld(data, Map.get(char, :voice))
    data = add_memory_jsonld(data, Map.get(char, :memory))
    add_knowledge_jsonld(data, Map.get(char, :knowledge, []))
  end

  defp add_identity_jsonld(data, nil), do: data

  defp add_identity_jsonld(data, identity) do
    identity_data = %{"@type" => "Identity"}
    identity_data = put_if_present(identity_data, "age", get_field(identity, :age))
    identity_data = put_if_present(identity_data, "role", get_field(identity, :role))
    identity_data = put_if_present(identity_data, "background", get_field(identity, :background))

    facts = get_field(identity, :facts, [])
    identity_data = if facts != [], do: Map.put(identity_data, "facts", facts), else: identity_data

    Map.put(data, "identity", identity_data)
  end

  defp add_personality_jsonld(data, nil), do: data

  defp add_personality_jsonld(data, personality) do
    personality_data = %{"@type" => "Personality"}

    traits = get_field(personality, :traits, [])

    trait_data =
      Enum.map(traits, fn
        trait when is_binary(trait) ->
          %{"@type" => "Trait", "name" => trait}

        trait when is_map(trait) ->
          %{
            "@type" => "Trait",
            "name" => get_field(trait, :name),
            "intensity" => get_field(trait, :intensity)
          }
      end)

    personality_data = if trait_data != [], do: Map.put(personality_data, "traits", trait_data), else: personality_data

    values = get_field(personality, :values, [])
    personality_data = if values != [], do: Map.put(personality_data, "values", values), else: personality_data

    quirks = get_field(personality, :quirks, [])
    personality_data = if quirks != [], do: Map.put(personality_data, "quirks", quirks), else: personality_data

    Map.put(data, "personality", personality_data)
  end

  defp add_voice_jsonld(data, nil), do: data

  defp add_voice_jsonld(data, voice) do
    voice_data = %{"@type" => "Voice"}
    tone = get_field(voice, :tone)
    voice_data = put_if_present(voice_data, "tone", tone && to_string(tone))
    voice_data = put_if_present(voice_data, "style", get_field(voice, :style))
    vocabulary = get_field(voice, :vocabulary)
    voice_data = put_if_present(voice_data, "vocabulary", vocabulary && to_string(vocabulary))

    expressions = get_field(voice, :expressions, [])
    voice_data = if expressions != [], do: Map.put(voice_data, "expressions", expressions), else: voice_data

    Map.put(data, "voice", voice_data)
  end

  defp add_memory_jsonld(data, nil), do: data

  defp add_memory_jsonld(data, memory) do
    memory_data = %{"@type" => "Memory"}
    memory_data = put_if_present(memory_data, "capacity", get_field(memory, :capacity))

    entries = get_field(memory, :entries, [])

    entry_data =
      Enum.map(entries, fn entry ->
        entry_map = %{"@type" => "MemoryEntry"}
        entry_map = put_if_present(entry_map, "content", get_field(entry, :content))
        entry_map = put_if_present(entry_map, "importance", get_field(entry, :importance))
        entry_map = put_if_present(entry_map, "decayRate", get_field(entry, :decay_rate))
        entry_map = put_if_present(entry_map, "category", get_field(entry, :category))

        timestamp = get_field(entry, :timestamp)

        if timestamp do
          Map.put(entry_map, "timestamp", DateTime.to_iso8601(timestamp))
        else
          entry_map
        end
      end)

    memory_data = if entry_data != [], do: Map.put(memory_data, "entries", entry_data), else: memory_data

    Map.put(data, "memory", memory_data)
  end

  defp add_knowledge_jsonld(data, []), do: data

  defp add_knowledge_jsonld(data, knowledge) do
    knowledge_data =
      Enum.map(knowledge, fn item ->
        item_map = %{"@type" => "KnowledgeItem"}
        item_map = put_if_present(item_map, "content", get_field(item, :content))
        item_map = put_if_present(item_map, "category", get_field(item, :category))
        put_if_present(item_map, "importance", get_field(item, :importance))
      end)

    Map.put(data, "knowledge", knowledge_data)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp get_field(map_or_struct, key, default \\ nil)

  defp get_field(%{__struct__: _} = struct, key, default) do
    Map.get(struct, key, default)
  end

  defp get_field(map, key, default) when is_map(map) do
    Map.get(map, key, default)
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
