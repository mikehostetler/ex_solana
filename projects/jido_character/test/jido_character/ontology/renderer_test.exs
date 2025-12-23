defmodule Jido.Character.Ontology.RendererTest do
  use ExUnit.Case, async: true

  alias Jido.Character.Ontology.Renderer

  @default_ns "http://jido.ai/character#"

  describe "to_owl/1" do
    test "generates valid OWL/RDF-XML structure" do
      owl = Renderer.to_owl()

      assert String.contains?(owl, ~s(<?xml version="1.0" encoding="UTF-8"?>))
      assert String.contains?(owl, "<rdf:RDF")
      assert String.contains?(owl, "<owl:Ontology")
      assert String.contains?(owl, "</rdf:RDF>")
    end

    test "includes all character classes" do
      owl = Renderer.to_owl()

      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}Character"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}Identity"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}Personality"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}Trait"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}Voice"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}Memory"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}MemoryEntry"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}KnowledgeItem"))
    end

    test "includes object properties" do
      owl = Renderer.to_owl()

      assert String.contains?(owl, "<owl:ObjectProperty")
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}hasIdentity"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}hasPersonality"))
    end

    test "includes datatype properties" do
      owl = Renderer.to_owl()

      assert String.contains?(owl, "<owl:DatatypeProperty")
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}name"))
      assert String.contains?(owl, ~s(rdf:about="#{@default_ns}intensity"))
    end

    test "respects custom namespace" do
      custom_ns = "http://example.com/my-ontology#"
      owl = Renderer.to_owl(namespace: custom_ns)

      assert String.contains?(owl, ~s(xmlns="#{custom_ns}"))
      assert String.contains?(owl, ~s(rdf:about="#{custom_ns}Character"))
    end
  end

  describe "to_rdf/2" do
    setup do
      {:ok, char} =
        Jido.Character.new(%{
          name: "Alex",
          description: "A test character",
          identity: %{
            age: 30,
            role: "Researcher",
            background: "Academic background",
            facts: ["Has PhD", "Likes coffee"]
          },
          personality: %{
            traits: ["curious", %{name: "patient", intensity: 0.8}],
            values: ["honesty"],
            quirks: ["Uses analogies"]
          },
          voice: %{
            tone: :warm,
            style: "Conversational",
            expressions: ["Great question!"]
          },
          memory: %{
            capacity: 50,
            entries: [
              %{content: "User prefers Elixir", importance: 0.9, decay_rate: 0.05}
            ]
          },
          knowledge: [
            %{content: "Expert in Elixir", category: "skills", importance: 0.95}
          ]
        })

      %{char: char}
    end

    test "generates N-Triples format by default", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>")
      assert String.contains?(rdf, "<#{@default_ns}Character>")
      assert String.contains?(rdf, ~s("Alex"))
    end

    test "includes character type triple", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
      assert String.contains?(rdf, "#{@default_ns}Character")
    end

    test "includes identity triples", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "#{@default_ns}hasIdentity")
      assert String.contains?(rdf, "#{@default_ns}Identity")
      assert String.contains?(rdf, ~s("Researcher"))
      assert String.contains?(rdf, ~s("Has PhD"))
    end

    test "includes personality and trait triples", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "#{@default_ns}hasPersonality")
      assert String.contains?(rdf, "#{@default_ns}Personality")
      assert String.contains?(rdf, "#{@default_ns}hasTrait")
      assert String.contains?(rdf, "#{@default_ns}Trait")
      assert String.contains?(rdf, ~s("curious"))
      assert String.contains?(rdf, ~s("patient"))
      assert String.contains?(rdf, "0.8")
    end

    test "includes voice triples", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "#{@default_ns}hasVoice")
      assert String.contains?(rdf, "#{@default_ns}Voice")
      assert String.contains?(rdf, ~s("warm"))
    end

    test "includes memory triples", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "#{@default_ns}hasMemory")
      assert String.contains?(rdf, "#{@default_ns}Memory")
      assert String.contains?(rdf, "#{@default_ns}hasEntry")
      assert String.contains?(rdf, "#{@default_ns}MemoryEntry")
      assert String.contains?(rdf, ~s("User prefers Elixir"))
    end

    test "includes knowledge triples", %{char: char} do
      rdf = Renderer.to_rdf(char)

      assert String.contains?(rdf, "#{@default_ns}hasKnowledge")
      assert String.contains?(rdf, "#{@default_ns}KnowledgeItem")
      assert String.contains?(rdf, ~s("Expert in Elixir"))
    end

    test "generates Turtle format when requested", %{char: char} do
      rdf = Renderer.to_rdf(char, format: :turtle)

      assert String.contains?(rdf, "@prefix :")
      assert String.contains?(rdf, "@prefix rdf:")
      assert String.contains?(rdf, "rdf:type")
      assert String.contains?(rdf, ":Character")
    end

    test "handles minimal character", %{} do
      {:ok, minimal} = Jido.Character.new(%{name: "Min"})
      rdf = Renderer.to_rdf(minimal)

      assert String.contains?(rdf, ~s("Min"))
      assert String.contains?(rdf, "#{@default_ns}Character")
    end
  end

  describe "to_jsonld/2" do
    setup do
      {:ok, char} =
        Jido.Character.new(%{
          name: "Alex",
          identity: %{role: "Researcher"},
          personality: %{
            traits: ["curious", %{name: "patient", intensity: 0.8}]
          },
          knowledge: [
            %{content: "Expert in Elixir", category: "skills"}
          ]
        })

      %{char: char}
    end

    test "includes @context", %{char: char} do
      jsonld = Renderer.to_jsonld(char)

      assert Map.has_key?(jsonld, "@context")
      assert jsonld["@context"]["@vocab"] == @default_ns
    end

    test "includes @id and @type", %{char: char} do
      jsonld = Renderer.to_jsonld(char)

      assert String.contains?(jsonld["@id"], "character/")
      assert jsonld["@type"] == "Character"
    end

    test "includes character data", %{char: char} do
      jsonld = Renderer.to_jsonld(char)

      assert jsonld["name"] == "Alex"
    end

    test "includes nested identity", %{char: char} do
      jsonld = Renderer.to_jsonld(char)

      assert jsonld["identity"]["@type"] == "Identity"
      assert jsonld["identity"]["role"] == "Researcher"
    end

    test "includes personality with traits", %{char: char} do
      jsonld = Renderer.to_jsonld(char)

      assert jsonld["personality"]["@type"] == "Personality"
      assert length(jsonld["personality"]["traits"]) == 2

      [string_trait, map_trait] = jsonld["personality"]["traits"]
      assert string_trait["name"] == "curious"
      assert map_trait["name"] == "patient"
      assert map_trait["intensity"] == 0.8
    end

    test "includes knowledge items", %{char: char} do
      jsonld = Renderer.to_jsonld(char)

      assert length(jsonld["knowledge"]) == 1
      [item] = jsonld["knowledge"]
      assert item["@type"] == "KnowledgeItem"
      assert item["content"] == "Expert in Elixir"
      assert item["category"] == "skills"
    end

    test "respects custom namespace", %{char: char} do
      custom_ns = "http://example.com/my-ontology#"
      jsonld = Renderer.to_jsonld(char, namespace: custom_ns)

      assert jsonld["@context"]["@vocab"] == custom_ns
      assert String.starts_with?(jsonld["@id"], custom_ns)
    end
  end

  describe "classes/0" do
    test "returns all ontology classes" do
      classes = Renderer.classes()

      assert length(classes) == 8

      class_names = Enum.map(classes, fn {name, _} -> name end)
      assert :Character in class_names
      assert :Identity in class_names
      assert :Personality in class_names
      assert :Trait in class_names
      assert :Voice in class_names
      assert :Memory in class_names
      assert :MemoryEntry in class_names
      assert :KnowledgeItem in class_names
    end
  end

  describe "object_properties/0" do
    test "returns object properties with domain and range" do
      props = Renderer.object_properties()

      assert length(props) >= 5

      has_identity = Enum.find(props, fn {name, _, _, _} -> name == :hasIdentity end)
      assert has_identity == {:hasIdentity, :Character, :Identity, "Links character to identity"}
    end
  end

  describe "datatype_properties/0" do
    test "returns datatype properties" do
      props = Renderer.datatype_properties()

      name_prop = Enum.find(props, fn {name, _, _, _} -> name == :name end)
      assert name_prop == {:name, :Character, :string, "Character's name"}

      intensity_prop = Enum.find(props, fn {name, _, _, _} -> name == :intensity end)
      assert intensity_prop == {:intensity, :Trait, :float, "Trait intensity (0.0-1.0)"}
    end
  end
end
