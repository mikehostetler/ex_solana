defmodule JidoCode.KnowledgeGraph do
  @moduledoc """
  Knowledge Graph infrastructure for code context management.

  This namespace provides RDF-based storage and querying capabilities for
  representing code entities and their relationships. The knowledge graph
  enables semantic understanding of codebases for enhanced LLM interactions.

  ## Architecture

  The knowledge graph consists of:

  - `JidoCode.KnowledgeGraph.Store` - RDF.Graph wrapper for triple storage
  - `JidoCode.KnowledgeGraph.Entity` - Struct representing code entities
  - `JidoCode.KnowledgeGraph.Vocab.Code` - RDF vocabulary for code concepts
  - `JidoCode.KnowledgeGraph.InMemory` - libgraph-based in-memory operations (planned)

  ## Code Entities

  The graph can represent various Elixir code constructs:

  - Modules and their documentation
  - Functions with arity and visibility
  - Types and typespecs
  - Protocols and implementations
  - Behaviours and callbacks
  - Supervision trees and OTP patterns

  ## Relationships

  Entities are connected through semantic relationships:

  - `defines` - Module defines a function/type
  - `calls` - Function calls another function
  - `imports` - Module imports from another
  - `uses` - Module uses a behaviour/protocol
  - `implements` - Module implements a protocol

  ## Status

  This module is currently a stub. Full implementation is planned for future phases.
  """

  @doc """
  Returns the base IRI for the JidoCode knowledge graph vocabulary.
  """
  @spec base_iri() :: String.t()
  def base_iri, do: "https://jidocode.dev/vocab/code/"

  @doc """
  Returns the base IRI for entity IRIs.
  """
  @spec entity_base_iri() :: String.t()
  def entity_base_iri, do: "https://jidocode.dev/entity/"

  @doc """
  Returns the version of the knowledge graph schema.
  """
  @spec version() :: String.t()
  def version, do: "0.1.0"
end
