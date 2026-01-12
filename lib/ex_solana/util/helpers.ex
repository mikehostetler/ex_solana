defmodule ExSolana.Util.Helpers do
  @moduledoc """
  General helper functions for the ex_solana package.

  ## Functions

  - `chunk/3` - Chunks binary data into specified sizes
  - `validate/2` - Validates parameters against a schema

  ## Examples

      # Chunk binary into parts
      ExSolana.Util.Helpers.chunk(<<1, 2, 3, 4>>, 2)
      #=> [<<1, 2>>, <<3, 4>>]

  """

  @doc """
  Validates parameters against a schema.

  NOTE: This is a simplified validation. Full schema validation
  will be implemented with Zoi in a future update.

  ## Parameters

    * `params` - Parameters to validate
    * `schema` - Schema definition

  ## Returns

    * `{:ok, map()}` - Validated parameters as map
    * `{:error, term()}` - Validation error

  ## Examples

      iex> ExSolana.Util.Helpers.validate([a: 1], [])
      {:ok, %{}}

  """
  def validate(params, schema) do
    # Simplified validation - convert to map
    # TODO: Implement proper Zoi-based validation
    {:ok, Map.new(params)}
  end

  @doc """
  Chunks a binary into parts of specified sizes.

  ## Parameters

    * `string` - Binary to chunk
    * `size` - Size of each chunk (integer or list of integers)

  ## Returns

    * `list(binary())` - List of chunked binaries

  ## Examples

      iex> ExSolana.Util.Helpers.chunk(<<1, 2, 3, 4>>, 2)
      [<<1, 2>>, <<3, 4>>]

      iex> ExSolana.Util.Helpers.chunk(<<1, 2, 3, 4, 5>>, [2, 3])
      [<<1, 2>>, <<3, 4, 5>>]

  """
  def chunk(string, size), do: chunk(string, size, [])

  defp chunk(<<>>, _size, acc), do: Enum.reverse(acc)

  defp chunk(string, [size | sizes], acc) when byte_size(string) > size do
    <<c::size(size)-binary, rest::binary>> = string
    chunk(rest, sizes, [c | acc])
  end

  defp chunk(string, size, acc) when byte_size(string) > size do
    <<c::size(size)-binary, rest::binary>> = string
    chunk(rest, size, [c | acc])
  end

  defp chunk(leftover, _size, acc) do
    chunk(<<>>, [], [leftover | acc])
  end
end
