defprotocol Kaizen.Evolvable do
  @moduledoc """
  Protocol for making any data structure evolvable.

  This protocol defines how entities can be converted to and from
  a normalized genome representation for evolutionary operations.
  """

  @type genome :: term()
  @type entity :: term()

  @doc """
  Convert an entity to its genome representation.

  The genome should be a structure that can be easily mutated
  and crossed over with other genomes of the same type.

  ## Examples

      iex> Kaizen.Evolvable.to_genome("hello")
      ['h', 'e', 'l', 'l', 'o']
  """
  @spec to_genome(entity()) :: genome()
  def to_genome(entity)

  @doc """
  Convert a genome back to the original entity type.

  The original entity is provided for context and type information.

  ## Examples

      iex> Kaizen.Evolvable.from_genome("original", ['h', 'i'])
      "hi"
  """
  @spec from_genome(entity(), genome()) :: entity()
  def from_genome(original_entity, genome)

  @doc """
  Calculate similarity between two entities (0.0 = identical, 1.0 = completely different).

  This is used for diversity maintenance and convergence detection.

  ## Examples

      iex> Kaizen.Evolvable.similarity("hello", "hello")
      0.0
      
      iex> Kaizen.Evolvable.similarity("hello", "world")
      1.0
  """
  @spec similarity(entity(), entity()) :: float()
  def similarity(entity1, entity2)
end
