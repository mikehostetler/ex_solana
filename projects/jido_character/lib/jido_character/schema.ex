defmodule Jido.Character.Schema do
  @moduledoc """
  Core Zoi schemas for character definitions.

  Provides schema definitions for validating character data structures.
  All fields except `id` are optional to support minimal character definitions.

  Each component module provides:

  - `schema/0` - Returns the Zoi schema for validation
  - `new/1`, `new!/1` - Creates a validated struct with defaults applied
  - Type specs for documentation and Dialyzer

  ## Nested Components

  - `Jido.Character.Schema.Trait` - personality trait with optional intensity
  - `Jido.Character.Schema.KnowledgeItem` - permanent facts the character knows
  - `Jido.Character.Schema.MemoryEntry` - individual memory item with decay
  - `Jido.Character.Schema.Memory` - memory container with capacity
  - `Jido.Character.Schema.Identity` - who the character is
  - `Jido.Character.Schema.Personality` - how the character behaves
  - `Jido.Character.Schema.Voice` - how the character communicates
  """

  alias Jido.Character.Schema.{
    Identity,
    KnowledgeItem,
    Memory,
    MemoryEntry,
    Personality,
    Trait,
    Voice
  }

  @doc "Complete character schema"
  def character do
    Zoi.map(%{
      id: Zoi.string(min_length: 1),
      name: Zoi.string(max_length: 100) |> Zoi.trim() |> Zoi.optional(),
      description: Zoi.string(max_length: 2000) |> Zoi.trim() |> Zoi.optional(),
      identity: Identity.schema() |> Zoi.optional(),
      personality: Personality.schema() |> Zoi.optional(),
      voice: Voice.schema() |> Zoi.optional(),
      memory: Memory.schema() |> Zoi.optional(),
      knowledge: Zoi.array(KnowledgeItem.schema()) |> Zoi.default([]),
      instructions: Zoi.array(Zoi.string()) |> Zoi.default([]),
      extensions: Zoi.any() |> Zoi.default(%{}),
      created_at: Zoi.datetime() |> Zoi.optional(),
      updated_at: Zoi.datetime() |> Zoi.optional(),
      version: Zoi.integer() |> Zoi.non_negative() |> Zoi.default(1)
    })
  end

  @doc "Identity schema - who the character is"
  def identity, do: Identity.schema()

  @doc "Personality schema - how the character behaves"
  def personality, do: Personality.schema()

  @doc "Trait schema - either a simple string or a Trait struct with name and intensity"
  def trait, do: Personality.trait_schema()

  @doc "Voice schema - how the character communicates"
  def voice, do: Voice.schema()

  @doc "Memory schema - what the character remembers"
  def memory, do: Memory.schema()

  @doc "Memory entry schema - individual memory item"
  def memory_entry, do: MemoryEntry.schema()

  @doc "Knowledge item schema - permanent facts the character knows"
  def knowledge_item, do: KnowledgeItem.schema()

  @doc "Trait struct schema"
  def trait_struct, do: Trait.schema()
end
