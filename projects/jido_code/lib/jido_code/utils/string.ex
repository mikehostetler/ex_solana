defmodule JidoCode.Utils.String do
  @moduledoc """
  String utility functions for JidoCode.

  Provides common string manipulation functions used across the codebase.
  """

  @doc """
  Truncates a string to the specified maximum length.

  If the string is longer than `max_length`, it is truncated and an ellipsis
  is appended. The resulting string will be at most `max_length` characters.

  ## Options

  - `:suffix` - The suffix to append when truncating (default: "...")

  ## Examples

      iex> JidoCode.Utils.String.truncate("Hello, World!", 10)
      "Hello, ..."

      iex> JidoCode.Utils.String.truncate("Short", 10)
      "Short"

      iex> JidoCode.Utils.String.truncate("Hello", 8, suffix: "…")
      "Hello"

      iex> JidoCode.Utils.String.truncate("Hello, World!", 8, suffix: "…")
      "Hello, …"
  """
  @spec truncate(String.t(), pos_integer(), keyword()) :: String.t()
  def truncate(string, max_length, opts \\ [])

  def truncate(string, max_length, _opts) when byte_size(string) <= max_length do
    string
  end

  def truncate(string, max_length, opts) when max_length > 0 do
    suffix = Keyword.get(opts, :suffix, "...")
    suffix_length = String.length(suffix)

    if max_length <= suffix_length do
      String.slice(string, 0, max_length)
    else
      content_length = max_length - suffix_length
      String.slice(string, 0, content_length) <> suffix
    end
  end

  @doc """
  Safely truncates a binary for parsing operations.

  Unlike `truncate/3`, this function performs a raw byte truncation without
  adding a suffix. Useful for limiting input size before regex operations
  to prevent ReDoS attacks.

  ## Examples

      iex> JidoCode.Utils.String.truncate_binary("Hello, World!", 5)
      "Hello"

      iex> JidoCode.Utils.String.truncate_binary("Short", 100)
      "Short"
  """
  @spec truncate_binary(binary(), pos_integer()) :: binary()
  def truncate_binary(binary, max_length) when byte_size(binary) <= max_length do
    binary
  end

  def truncate_binary(binary, max_length) when max_length > 0 do
    binary_part(binary, 0, max_length)
  end

  @doc """
  Converts a value to a string for display purposes.

  Handles various types gracefully:
  - Strings are returned as-is
  - Atoms are converted to strings
  - Other values are inspected

  ## Examples

      iex> JidoCode.Utils.String.to_display_string("hello")
      "hello"

      iex> JidoCode.Utils.String.to_display_string(:world)
      "world"

      iex> JidoCode.Utils.String.to_display_string(%{key: "value"})
      ~s(%{key: "value"})
  """
  @spec to_display_string(term()) :: String.t()
  def to_display_string(value) when is_binary(value), do: value
  def to_display_string(value) when is_atom(value), do: Atom.to_string(value)
  def to_display_string(value), do: inspect(value)
end
