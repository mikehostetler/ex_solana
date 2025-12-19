defmodule JidoCode.KnowledgeGraph.Vocab.CodeTest do
  use ExUnit.Case, async: true

  alias JidoCode.KnowledgeGraph.Vocab

  # Helper to access capitalized vocabulary terms
  defp vocab_term(term), do: apply(Vocab.Code, term, [])

  describe "vocabulary terms" do
    test "entity type terms are accessible" do
      # Capital terms must be accessed via apply/3 or the sigil
      assert %RDF.IRI{} = vocab_term(:Module)
      assert %RDF.IRI{} = vocab_term(:Function)
      assert %RDF.IRI{} = vocab_term(:Type)
      assert %RDF.IRI{} = vocab_term(:Protocol)
      assert %RDF.IRI{} = vocab_term(:Behaviour)
      assert %RDF.IRI{} = vocab_term(:Macro)
    end

    test "relationship terms are accessible" do
      # Lowercase terms can be accessed directly
      assert %RDF.IRI{} = Vocab.Code.defines()
      assert %RDF.IRI{} = Vocab.Code.calls()
      assert %RDF.IRI{} = Vocab.Code.imports()
      assert %RDF.IRI{} = Vocab.Code.uses()
      assert %RDF.IRI{} = Vocab.Code.implements()
      assert %RDF.IRI{} = Vocab.Code.depends_on()
    end

    test "property terms are accessible" do
      assert %RDF.IRI{} = Vocab.Code.name()
      assert %RDF.IRI{} = Vocab.Code.arity()
      assert %RDF.IRI{} = Vocab.Code.visibility()
      assert %RDF.IRI{} = Vocab.Code.doc()
      assert %RDF.IRI{} = Vocab.Code.file_path()
      assert %RDF.IRI{} = Vocab.Code.line_number()
    end

    test "terms have correct base IRI" do
      module_iri = vocab_term(:Module) |> to_string()

      assert module_iri == "https://jidocode.dev/vocab/code/Module"
    end

    test "lowercase terms have correct base IRI" do
      defines_iri = Vocab.Code.defines() |> to_string()

      assert defines_iri == "https://jidocode.dev/vocab/code/defines"
    end

    test "can use terms in RDF triples" do
      subject = RDF.iri("http://example.org/MyModule")

      triple = {
        subject,
        RDF.type(),
        vocab_term(:Module)
      }

      graph = RDF.graph() |> RDF.Graph.add(triple)

      assert RDF.Graph.triple_count(graph) == 1
    end

    test "vocabulary lists all terms" do
      terms = Vocab.Code.__terms__()

      assert :Module in terms
      assert :Function in terms
      assert :defines in terms
      assert :name in terms
    end
  end

  describe "vocabulary usage in graph" do
    test "can build a simple code entity graph" do
      module_iri = RDF.iri("https://jidocode.dev/entity/MyApp.User")
      function_iri = RDF.iri("https://jidocode.dev/entity/MyApp.User.create/1")

      graph =
        RDF.graph()
        # Module type
        |> RDF.Graph.add({module_iri, RDF.type(), vocab_term(:Module)})
        |> RDF.Graph.add({module_iri, Vocab.Code.name(), RDF.literal("MyApp.User")})
        # Function type
        |> RDF.Graph.add({function_iri, RDF.type(), vocab_term(:Function)})
        |> RDF.Graph.add({function_iri, Vocab.Code.name(), RDF.literal("create")})
        |> RDF.Graph.add({function_iri, Vocab.Code.arity(), RDF.literal(1)})
        |> RDF.Graph.add({function_iri, Vocab.Code.visibility(), RDF.literal("public")})
        # Relationship
        |> RDF.Graph.add({module_iri, Vocab.Code.defines(), function_iri})

      assert RDF.Graph.triple_count(graph) == 7
    end
  end
end
