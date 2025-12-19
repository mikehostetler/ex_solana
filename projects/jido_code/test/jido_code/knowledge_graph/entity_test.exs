defmodule JidoCode.KnowledgeGraph.EntityTest do
  use ExUnit.Case, async: true

  alias JidoCode.KnowledgeGraph.Entity

  describe "new/3" do
    test "creates a module entity" do
      entity = Entity.new(:module, MyApp.User)

      assert entity.type == :module
      assert entity.name == MyApp.User
      assert entity.metadata == %{}
    end

    test "creates a function entity with options" do
      entity =
        Entity.new(:function, :create,
          module: MyApp.User,
          arity: 1,
          visibility: :public
        )

      assert entity.type == :function
      assert entity.name == :create
      assert entity.module == MyApp.User
      assert entity.arity == 1
      assert entity.visibility == :public
    end

    test "creates an entity with all fields" do
      entity =
        Entity.new(:function, :process,
          module: MyApp.Worker,
          arity: 2,
          visibility: :private,
          file_path: "lib/my_app/worker.ex",
          line_number: 42,
          doc: "Processes the given data",
          metadata: %{deprecated: true}
        )

      assert entity.type == :function
      assert entity.name == :process
      assert entity.module == MyApp.Worker
      assert entity.arity == 2
      assert entity.visibility == :private
      assert entity.file_path == "lib/my_app/worker.ex"
      assert entity.line_number == 42
      assert entity.doc == "Processes the given data"
      assert entity.metadata == %{deprecated: true}
    end
  end

  describe "qualified_name/1" do
    test "returns module name for module entities" do
      entity = Entity.new(:module, MyApp.User)

      assert Entity.qualified_name(entity) == "Elixir.MyApp.User"
    end

    test "returns function with arity for function entities" do
      entity = Entity.new(:function, :create, module: MyApp.User, arity: 1)

      assert Entity.qualified_name(entity) == "Elixir.MyApp.User.create/1"
    end

    test "returns function without arity when arity is nil" do
      entity = Entity.new(:function, :init, module: MyApp.Server)

      assert Entity.qualified_name(entity) == "Elixir.MyApp.Server.init"
    end

    test "returns macro with arity for macro entities" do
      entity = Entity.new(:macro, :defstruct, module: Kernel, arity: 1)

      assert Entity.qualified_name(entity) == "Elixir.Kernel.defstruct/1"
    end

    test "returns type name for type entities" do
      entity = Entity.new(:type, :user, module: MyApp.Types)

      assert Entity.qualified_name(entity) == "Elixir.MyApp.Types.user"
    end
  end

  describe "to_iri/1" do
    test "generates IRI for module entity" do
      entity = Entity.new(:module, MyApp.User)
      iri = Entity.to_iri(entity)

      assert %RDF.IRI{} = iri
      assert to_string(iri) =~ "https://jidocode.dev/entity/"
      assert to_string(iri) =~ "MyApp.User"
    end

    test "generates IRI for function entity" do
      entity = Entity.new(:function, :create, module: MyApp.User, arity: 1)
      iri = Entity.to_iri(entity)

      assert %RDF.IRI{} = iri
      assert to_string(iri) =~ "https://jidocode.dev/entity/"
      assert to_string(iri) =~ "create"
    end

    test "URL-encodes special characters" do
      entity = Entity.new(:function, :+, module: Kernel, arity: 2)
      iri = Entity.to_iri(entity)

      # The + should be URL-encoded
      assert %RDF.IRI{} = iri
    end
  end

  describe "struct" do
    test "has all expected fields" do
      entity = %Entity{}

      assert Map.has_key?(entity, :type)
      assert Map.has_key?(entity, :name)
      assert Map.has_key?(entity, :module)
      assert Map.has_key?(entity, :arity)
      assert Map.has_key?(entity, :visibility)
      assert Map.has_key?(entity, :file_path)
      assert Map.has_key?(entity, :line_number)
      assert Map.has_key?(entity, :doc)
      assert Map.has_key?(entity, :metadata)
    end

    test "defaults metadata to empty map" do
      entity = %Entity{}

      assert entity.metadata == %{}
    end
  end
end
