defmodule JidoCode.KnowledgeGraph.StoreTest do
  use ExUnit.Case, async: true

  alias JidoCode.KnowledgeGraph.Entity
  alias JidoCode.KnowledgeGraph.Store

  describe "new/0" do
    test "creates an empty store" do
      store = Store.new()

      assert %Store{} = store
      assert Store.empty?(store)
      assert Store.count(store) == 0
    end

    test "creates a named store" do
      name = RDF.iri("http://example.org/test-graph")
      store = Store.new(name: name)

      assert store.name == name
    end
  end

  describe "empty?/1" do
    test "returns true for empty store" do
      store = Store.new()

      assert Store.empty?(store)
    end

    test "returns false after adding triple" do
      store = Store.new()
      triple = {RDF.iri("http://example.org/s"), RDF.iri("http://example.org/p"), "object"}
      {:ok, store} = Store.add_triple(store, triple)

      refute Store.empty?(store)
    end
  end

  describe "count/1" do
    test "returns 0 for empty store" do
      store = Store.new()

      assert Store.count(store) == 0
    end

    test "returns correct count after adding triples" do
      store = Store.new()

      {:ok, store} =
        Store.add_triple(
          store,
          {RDF.iri("http://example.org/s1"), RDF.iri("http://example.org/p"), "o1"}
        )

      {:ok, store} =
        Store.add_triple(
          store,
          {RDF.iri("http://example.org/s2"), RDF.iri("http://example.org/p"), "o2"}
        )

      assert Store.count(store) == 2
    end
  end

  describe "add_triple/2" do
    test "adds a triple to the store" do
      store = Store.new()
      subject = RDF.iri("http://example.org/subject")
      predicate = RDF.iri("http://example.org/predicate")
      object = RDF.literal("test value")

      {:ok, updated_store} = Store.add_triple(store, {subject, predicate, object})

      assert Store.count(updated_store) == 1
    end

    test "can add multiple triples" do
      store = Store.new()

      triples = [
        {RDF.iri("http://example.org/a"), RDF.iri("http://example.org/p"), "1"},
        {RDF.iri("http://example.org/b"), RDF.iri("http://example.org/p"), "2"},
        {RDF.iri("http://example.org/c"), RDF.iri("http://example.org/p"), "3"}
      ]

      store =
        Enum.reduce(triples, store, fn triple, acc ->
          {:ok, new_store} = Store.add_triple(acc, triple)
          new_store
        end)

      assert Store.count(store) == 3
    end
  end

  describe "to_graph/1" do
    test "returns the underlying RDF.Graph" do
      store = Store.new()
      graph = Store.to_graph(store)

      assert %RDF.Graph{} = graph
    end
  end

  describe "stub functions" do
    test "add_entity/2 returns :not_implemented" do
      store = Store.new()
      entity = Entity.new(:module, MyApp.Test)

      assert {:error, :not_implemented} = Store.add_entity(store, entity)
    end

    test "query/2 returns :not_implemented" do
      store = Store.new()

      assert {:error, :not_implemented} = Store.query(store, %{type: :module})
    end

    test "clear/1 returns :not_implemented" do
      store = Store.new()

      assert {:error, :not_implemented} = Store.clear(store)
    end
  end

  describe "RDF.ex integration" do
    test "can create and query an RDF graph directly" do
      # Verify RDF.ex is working correctly
      graph = RDF.graph()

      assert RDF.Graph.empty?(graph)

      # Add a triple
      graph =
        RDF.Graph.add(graph, {
          RDF.iri("http://example.org/test"),
          RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
          RDF.iri("http://example.org/Module")
        })

      assert RDF.Graph.triple_count(graph) == 1
    end

    test "can use RDF literals" do
      graph = RDF.graph()

      graph =
        RDF.Graph.add(graph, {
          RDF.iri("http://example.org/func"),
          RDF.iri("http://example.org/arity"),
          RDF.literal(2)
        })

      assert RDF.Graph.triple_count(graph) == 1
    end
  end
end
