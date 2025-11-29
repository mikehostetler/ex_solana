defimpl Kaizen.Evolvable, for: BitString do
  @moduledoc """
  Implementation of Kaizen.Evolvable for strings.

  Treats strings as lists of characters for evolutionary operations.

  ## Examples

      iex> genome = Kaizen.Evolvable.to_genome("evolve")
      iex> Kaizen.Evolvable.from_genome("evolve", genome)
      "evolve"

      iex> Kaizen.Evolvable.similarity("hello", "hello")
      0.0

      iex> similarity = Kaizen.Evolvable.similarity("hello", "hallo")
      iex> similarity > 0.0 and similarity < 0.5
      true
  """

  @doc """
  Convert string to list of characters (genome).

  ## Examples

      iex> Kaizen.Evolvable.to_genome("hello")
      ~c"hello"

      iex> Kaizen.Evolvable.to_genome("")
      ~c""

      iex> Kaizen.Evolvable.to_genome("🚀")
      [128640]
  """
  def to_genome(string) when is_binary(string) do
    String.to_charlist(string)
  end

  @doc """
  Convert character list back to string.

  ## Examples

      iex> Kaizen.Evolvable.from_genome("original", ~c"hi")
      "hi"

      iex> Kaizen.Evolvable.from_genome("ignored", ~c"new")
      "new"

      iex> Kaizen.Evolvable.from_genome("any", ~c"")
      ""
  """
  def from_genome(_original, charlist) when is_list(charlist) do
    List.to_string(charlist)
  end

  @doc """
  Calculate similarity using Jaro distance (0.0 = identical, 1.0 = completely different).

  ## Examples

      iex> Kaizen.Evolvable.similarity("hello", "hello")
      0.0

      iex> similarity = Kaizen.Evolvable.similarity("hello", "world")
      iex> similarity > 0.0 and similarity <= 1.0
      true

      iex> sim_similar = Kaizen.Evolvable.similarity("test", "tests")
      iex> sim_different = Kaizen.Evolvable.similarity("test", "xyz")
      iex> sim_different > sim_similar
      true
  """
  def similarity(string1, string2) when is_binary(string1) and is_binary(string2) do
    jaro_distance = String.jaro_distance(string1, string2)
    # Invert so 0.0 = identical, 1.0 = completely different
    1.0 - jaro_distance
  end
end
