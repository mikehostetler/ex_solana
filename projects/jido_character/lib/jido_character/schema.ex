defmodule Jido.Character.Schema do
  @moduledoc """
  Core Zoi schemas for character definitions.

  Provides schema definitions for validating character data structures.
  All fields except `id` are optional to support minimal character definitions.

  Characters and their nested components are plain Elixir maps for flexibility
  and Access behaviour compatibility. Each component module provides:

  - `schema/0` - Returns the Zoi schema for validation
  - `new/1`, `new!/1` - Creates a validated map with defaults applied
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

  # ---------------------------------------------------------------------------
  # Trait Schema
  # ---------------------------------------------------------------------------

  defmodule Trait do
    @moduledoc "Personality trait with optional intensity (0.0-1.0)."

    @schema Zoi.object(%{
              name: Zoi.string(min_length: 1),
              intensity: Zoi.float() |> Zoi.gte(0) |> Zoi.lte(1) |> Zoi.default(0.5)
            })

    @type t :: %{name: String.t(), intensity: float()}

    @doc "Returns the Zoi schema for Trait"
    def schema, do: @schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs) do
      case new(attrs) do
        {:ok, trait} -> trait
        {:error, reason} -> raise ArgumentError, "Invalid trait: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # KnowledgeItem Schema
  # ---------------------------------------------------------------------------

  defmodule KnowledgeItem do
    @moduledoc "Permanent fact the character knows (no decay)."

    @schema Zoi.object(%{
              content: Zoi.string(min_length: 1),
              category: Zoi.string() |> Zoi.nullish(),
              importance: Zoi.float() |> Zoi.gte(0) |> Zoi.lte(1) |> Zoi.default(0.5)
            })

    @type t :: %{content: String.t(), category: String.t() | nil, importance: float()}

    @doc "Returns the Zoi schema for KnowledgeItem"
    def schema, do: @schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs) do
      case new(attrs) do
        {:ok, item} -> item
        {:error, reason} -> raise ArgumentError, "Invalid knowledge item: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MemoryEntry Schema
  # ---------------------------------------------------------------------------

  defmodule MemoryEntry do
    @moduledoc "Individual memory item with decay properties."

    @schema Zoi.object(%{
              content: Zoi.string(min_length: 1),
              timestamp: Zoi.datetime() |> Zoi.nullish(),
              importance: Zoi.float() |> Zoi.gte(0) |> Zoi.lte(1) |> Zoi.default(0.5),
              decay_rate: Zoi.float() |> Zoi.gte(0) |> Zoi.lte(1) |> Zoi.default(0.1),
              category: Zoi.string() |> Zoi.nullish()
            })

    @type t :: %{
            content: String.t(),
            timestamp: DateTime.t() | nil,
            importance: float(),
            decay_rate: float(),
            category: String.t() | nil
          }

    @doc "Returns the Zoi schema for MemoryEntry"
    def schema, do: @schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs) do
      case new(attrs) do
        {:ok, entry} -> entry
        {:error, reason} -> raise ArgumentError, "Invalid memory entry: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Memory Schema
  # ---------------------------------------------------------------------------

  defmodule Memory do
    @moduledoc "Character memory with entries and capacity limit."

    @schema Zoi.object(%{
              entries: Zoi.array(Jido.Character.Schema.MemoryEntry.schema()) |> Zoi.default([]),
              capacity: Zoi.integer() |> Zoi.positive() |> Zoi.default(100)
            })

    @type t :: %{
            entries: [Jido.Character.Schema.MemoryEntry.t()],
            capacity: pos_integer()
          }

    @doc "Returns the Zoi schema for Memory"
    def schema, do: @schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs \\ %{}) do
      case new(attrs) do
        {:ok, memory} -> memory
        {:error, reason} -> raise ArgumentError, "Invalid memory: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Identity Schema
  # ---------------------------------------------------------------------------

  defmodule Identity do
    @moduledoc "Character identity - who the character is."

    @schema Zoi.object(%{
              age:
                Zoi.union([
                  Zoi.integer() |> Zoi.non_negative(),
                  Zoi.string()
                ])
                |> Zoi.nullish(),
              background: Zoi.string(max_length: 2000) |> Zoi.nullish(),
              role: Zoi.string(max_length: 200) |> Zoi.nullish(),
              facts: Zoi.array(Zoi.string()) |> Zoi.default([])
            })

    @type t :: %{
            age: non_neg_integer() | String.t() | nil,
            background: String.t() | nil,
            role: String.t() | nil,
            facts: [String.t()]
          }

    @doc "Returns the Zoi schema for Identity"
    def schema, do: @schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs \\ %{}) do
      case new(attrs) do
        {:ok, identity} -> identity
        {:error, reason} -> raise ArgumentError, "Invalid identity: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Personality Schema
  # ---------------------------------------------------------------------------

  defmodule Personality do
    @moduledoc "Character personality - how the character behaves."

    @trait_schema Zoi.union([
                    Zoi.string(),
                    Jido.Character.Schema.Trait.schema()
                  ])

    @schema Zoi.object(%{
              traits: Zoi.array(@trait_schema, max_length: 10) |> Zoi.default([]),
              values: Zoi.array(Zoi.string(), max_length: 10) |> Zoi.default([]),
              quirks: Zoi.array(Zoi.string(), max_length: 10) |> Zoi.default([])
            })

    @type trait :: String.t() | Jido.Character.Schema.Trait.t()
    @type t :: %{
            traits: [trait()],
            values: [String.t()],
            quirks: [String.t()]
          }

    @doc "Returns the Zoi schema for Personality"
    def schema, do: @schema

    @doc "Returns the trait schema (string or Trait map)"
    def trait_schema, do: @trait_schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs \\ %{}) do
      case new(attrs) do
        {:ok, personality} -> personality
        {:error, reason} -> raise ArgumentError, "Invalid personality: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Voice Schema
  # ---------------------------------------------------------------------------

  defmodule Voice do
    @moduledoc "Character voice - how the character communicates."

    @schema Zoi.object(%{
              tone:
                Zoi.enum([
                  :formal,
                  :casual,
                  :playful,
                  :serious,
                  :warm,
                  :cold,
                  :professional,
                  :friendly
                ])
                |> Zoi.default(:casual),
              style: Zoi.string(max_length: 500) |> Zoi.nullish(),
              vocabulary:
                Zoi.enum([:simple, :technical, :academic, :conversational, :poetic])
                |> Zoi.nullish(),
              expressions: Zoi.array(Zoi.string(), max_length: 20) |> Zoi.default([])
            })

    @type t :: %{
            tone: atom(),
            style: String.t() | nil,
            vocabulary: atom() | nil,
            expressions: [String.t()]
          }

    @doc "Returns the Zoi schema for Voice"
    def schema, do: @schema

    @spec new(map()) :: {:ok, t()} | {:error, term()}
    def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

    @spec new!(map()) :: t()
    def new!(attrs \\ %{}) do
      case new(attrs) do
        {:ok, voice} -> voice
        {:error, reason} -> raise ArgumentError, "Invalid voice: #{inspect(reason)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Main Character Schema (map-based for flexibility)
  # ---------------------------------------------------------------------------

  @identity_schema Identity.schema()
  @personality_schema Personality.schema()
  @voice_schema Voice.schema()
  @memory_schema Memory.schema()
  @knowledge_item_schema KnowledgeItem.schema()

  @doc "Complete character schema"
  def character do
    Zoi.map(%{
      id: Zoi.string(min_length: 1),
      name: Zoi.string(max_length: 100) |> Zoi.trim() |> Zoi.optional(),
      description: Zoi.string(max_length: 2000) |> Zoi.trim() |> Zoi.optional(),
      identity: @identity_schema |> Zoi.optional(),
      personality: @personality_schema |> Zoi.optional(),
      voice: @voice_schema |> Zoi.optional(),
      memory: @memory_schema |> Zoi.optional(),
      knowledge: Zoi.array(@knowledge_item_schema) |> Zoi.default([]),
      instructions: Zoi.array(Zoi.string()) |> Zoi.default([]),
      extensions: Zoi.any() |> Zoi.default(%{}),
      created_at: Zoi.datetime() |> Zoi.optional(),
      updated_at: Zoi.datetime() |> Zoi.optional(),
      version: Zoi.integer() |> Zoi.non_negative() |> Zoi.default(1)
    })
  end

  @doc "Identity schema - who the character is"
  def identity, do: @identity_schema

  @doc "Personality schema - how the character behaves"
  def personality, do: @personality_schema

  @doc "Trait schema - either a simple string or a map with name and intensity"
  def trait, do: Personality.trait_schema()

  @doc "Voice schema - how the character communicates"
  def voice, do: @voice_schema

  @doc "Memory schema - what the character remembers"
  def memory, do: @memory_schema

  @doc "Memory entry schema - individual memory item"
  def memory_entry, do: MemoryEntry.schema()

  @doc "Knowledge item schema - permanent facts the character knows"
  def knowledge_item, do: @knowledge_item_schema
end
