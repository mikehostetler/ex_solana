defmodule JidoCode.KnowledgeGraph.Vocab do
  @moduledoc """
  RDF vocabularies for the knowledge graph.

  This module defines namespaces for vocabulary terms used in the knowledge graph.

  ## Code Vocabulary

  The `Code` vocabulary defines terms for Elixir code constructs and their relationships,
  enabling semantic representation of codebases in an RDF graph.

  ### Entity Types

  - `Module` - An Elixir module
  - `Function` - A function definition
  - `Type` - A type or typespec
  - `Protocol` - A protocol definition
  - `Behaviour` - A behaviour definition
  - `Macro` - A macro definition

  ### Relationships

  - `defines` - Module defines an entity (function, type, etc.)
  - `calls` - Function calls another function
  - `imports` - Module imports from another module
  - `uses` - Module uses a behaviour or protocol
  - `implements` - Module implements a protocol
  - `depends_on` - General dependency relationship

  ### Properties

  - `name` - The name of the entity
  - `arity` - Function/macro arity
  - `visibility` - Public or private
  - `doc` - Documentation string
  - `file_path` - Source file location
  - `line_number` - Line number in source

  ### Usage

      alias JidoCode.KnowledgeGraph.Vocab

      # Access lowercase terms directly as functions
      Vocab.Code.defines()       # => RDF.IRI for defines relationship
      Vocab.Code.name()          # => RDF.IRI for name property

      # Access capitalized terms via apply/3
      apply(Vocab.Code, :Module, [])  # => RDF.IRI for module type
  """

  use RDF.Vocabulary.Namespace

  defvocab(Code,
    base_iri: "https://jidocode.dev/vocab/code/",
    terms: [
      # Entity types
      :Module,
      :Function,
      :Type,
      :Protocol,
      :Behaviour,
      :Macro,
      :Struct,
      :Exception,

      # Relationships
      :defines,
      :calls,
      :imports,
      :uses,
      :implements,
      :depends_on,
      :supervises,
      :aliases,

      # Properties
      :name,
      :arity,
      :visibility,
      :doc,
      :file_path,
      :line_number,
      :module_name,
      :spec
    ],
    strict: false
  )
end
