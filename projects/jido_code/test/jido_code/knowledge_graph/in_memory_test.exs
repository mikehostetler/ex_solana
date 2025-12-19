defmodule JidoCode.KnowledgeGraph.InMemoryTest do
  use ExUnit.Case, async: true

  alias JidoCode.KnowledgeGraph.Entity
  alias JidoCode.KnowledgeGraph.InMemory

  describe "new/0" do
    test "creates an empty directed graph" do
      graph = InMemory.new()

      assert InMemory.empty?(graph)
      assert InMemory.vertex_count(graph) == 0
      assert InMemory.edge_count(graph) == 0
    end
  end

  describe "edge_types/0" do
    test "returns list of valid edge types" do
      types = InMemory.edge_types()

      assert is_list(types)
      assert :defines in types
      assert :calls in types
      assert :imports in types
      assert :uses in types
      assert :implements in types
      assert :depends_on in types
      assert :supervises in types
      assert :aliases in types
    end
  end

  describe "entity_types/0" do
    test "returns list of valid entity types" do
      types = InMemory.entity_types()

      assert is_list(types)
      assert :module in types
      assert :function in types
      assert :type in types
      assert :protocol in types
      assert :behaviour in types
      assert :macro in types
      assert :struct in types
      assert :exception in types
    end
  end

  describe "empty?/1" do
    test "returns true for empty graph" do
      graph = InMemory.new()
      assert InMemory.empty?(graph)
    end

    test "returns false for graph with vertices" do
      graph =
        InMemory.new()
        |> Graph.add_vertex(:some_module)

      refute InMemory.empty?(graph)
    end
  end

  describe "vertex_count/1" do
    test "returns 0 for empty graph" do
      graph = InMemory.new()
      assert InMemory.vertex_count(graph) == 0
    end

    test "returns correct count after adding vertices" do
      graph =
        InMemory.new()
        |> Graph.add_vertex(:module_a)
        |> Graph.add_vertex(:module_b)
        |> Graph.add_vertex(:function_c)

      assert InMemory.vertex_count(graph) == 3
    end
  end

  describe "edge_count/1" do
    test "returns 0 for empty graph" do
      graph = InMemory.new()
      assert InMemory.edge_count(graph) == 0
    end

    test "returns correct count after adding edges" do
      graph =
        InMemory.new()
        |> Graph.add_edge(:a, :b, label: :calls)
        |> Graph.add_edge(:b, :c, label: :calls)

      assert InMemory.edge_count(graph) == 2
    end
  end

  describe "libgraph operations" do
    test "can add vertices with labels" do
      graph =
        InMemory.new()
        |> Graph.add_vertex(:my_module, [:module])
        |> Graph.add_vertex(:my_function, [:function])

      vertices = Graph.vertices(graph)

      assert :my_module in vertices
      assert :my_function in vertices
    end

    test "can add edges with labels" do
      graph =
        InMemory.new()
        |> Graph.add_edge(:module_a, :function_b, label: :defines)
        |> Graph.add_edge(:function_b, :function_c, label: :calls)

      edges = Graph.edges(graph)

      assert length(edges) == 2

      defines_edge = Enum.find(edges, &(&1.label == :defines))
      assert defines_edge.v1 == :module_a
      assert defines_edge.v2 == :function_b

      calls_edge = Enum.find(edges, &(&1.label == :calls))
      assert calls_edge.v1 == :function_b
      assert calls_edge.v2 == :function_c
    end

    test "can find neighbors" do
      graph =
        InMemory.new()
        |> Graph.add_edge(:a, :b)
        |> Graph.add_edge(:a, :c)
        |> Graph.add_edge(:b, :d)

      # Out neighbors of :a
      out_neighbors = Graph.out_neighbors(graph, :a)
      assert :b in out_neighbors
      assert :c in out_neighbors
      refute :d in out_neighbors

      # In neighbors of :b
      in_neighbors = Graph.in_neighbors(graph, :b)
      assert :a in in_neighbors
      refute :c in in_neighbors
    end

    test "can traverse graph with edges/2" do
      graph =
        InMemory.new()
        |> Graph.add_edge(:module, :func_a, label: :defines)
        |> Graph.add_edge(:module, :func_b, label: :defines)
        |> Graph.add_edge(:func_a, :func_c, label: :calls)

      # Get edges from module
      module_edges = Graph.edges(graph, :module)

      assert length(module_edges) == 2
      assert Enum.all?(module_edges, &(&1.v1 == :module))
    end

    test "supports topological sort for DAGs" do
      graph =
        InMemory.new()
        |> Graph.add_edge(:a, :b)
        |> Graph.add_edge(:b, :c)
        |> Graph.add_edge(:a, :c)

      sorted = Graph.topsort(graph)

      # :a should come before :b and :c
      assert is_list(sorted)
      a_idx = Enum.find_index(sorted, &(&1 == :a))
      b_idx = Enum.find_index(sorted, &(&1 == :b))
      c_idx = Enum.find_index(sorted, &(&1 == :c))

      assert a_idx < b_idx
      assert a_idx < c_idx
      assert b_idx < c_idx
    end

    test "detects cycles" do
      graph =
        InMemory.new()
        |> Graph.add_edge(:a, :b)
        |> Graph.add_edge(:b, :c)
        |> Graph.add_edge(:c, :a)

      # topsort returns false for cyclic graphs
      assert Graph.topsort(graph) == false
    end
  end

  describe "stub functions" do
    test "build_dependency_graph/1 returns :not_implemented" do
      entities = [
        Entity.new(:module, MyApp.User),
        Entity.new(:function, :create, module: MyApp.User, arity: 1)
      ]

      assert {:error, :not_implemented} = InMemory.build_dependency_graph(entities)
    end

    test "find_related_entities/2 returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} = InMemory.find_related_entities(graph, :some_entity)
    end

    test "find_related_entities/3 with opts returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} =
               InMemory.find_related_entities(graph, :some_entity, max_depth: 3)
    end

    test "add_entity/2 returns :not_implemented" do
      graph = InMemory.new()
      entity = Entity.new(:module, MyApp.User)

      assert {:error, :not_implemented} = InMemory.add_entity(graph, entity)
    end

    test "add_relationship/4 returns :not_implemented" do
      graph = InMemory.new()

      assert {:error, :not_implemented} =
               InMemory.add_relationship(graph, :from, :to, :calls)
    end
  end
end
