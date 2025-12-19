defmodule JidoCode.KnowledgeGraph.GraphRAGTest do
  use ExUnit.Case, async: true

  alias JidoCode.KnowledgeGraph.GraphRAG
  alias JidoCode.KnowledgeGraph.InMemory

  describe "query/3" do
    test "returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} = GraphRAG.query(graph, "How does User.create work?")
    end

    test "with options returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} =
               GraphRAG.query(graph, "Find related functions", max_depth: 3, max_tokens: 2000)
    end
  end

  describe "build_context/3" do
    test "returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} = GraphRAG.build_context(graph, :some_entity)
    end

    test "with options returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} =
               GraphRAG.build_context(graph, :some_entity, include_source: false)
    end
  end

  describe "rank_entities/3" do
    test "returns :not_implemented" do
      graph = InMemory.new()
      entities = [:entity_a, :entity_b, :entity_c]

      assert {:error, :not_implemented} =
               GraphRAG.rank_entities(entities, "Find the main module", graph)
    end
  end
end
