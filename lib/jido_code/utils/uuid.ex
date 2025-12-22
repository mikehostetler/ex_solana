defmodule JidoCode.Utils.UUID do
  @moduledoc """
  UUID validation utilities.

  Provides centralized UUID format validation to avoid duplication
  across multiple modules (Executor, HandlerHelpers, etc.).

  ## UUID Format

  Validates standard UUID v4 format:
  - 8 hex digits
  - dash
  - 4 hex digits
  - dash
  - 4 hex digits
  - dash
  - 4 hex digits
  - dash
  - 12 hex digits

  Example: `"550e8400-e29b-41d4-a716-446655440000"`

  ## Usage

      iex> JidoCode.Utils.UUID.valid?("550e8400-e29b-41d4-a716-446655440000")
      true

      iex> JidoCode.Utils.UUID.valid?("not-a-uuid")
      false

      iex> JidoCode.Utils.UUID.valid?(nil)
      false
  """

  # Standard UUID v4 regex pattern (case-insensitive)
  @uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  @doc """
  Checks if a string is a valid UUID format.

  Returns `true` if the string matches the UUID v4 format, `false` otherwise.
  Non-string values always return `false`.

  ## Examples

      iex> JidoCode.Utils.UUID.valid?("550e8400-e29b-41d4-a716-446655440000")
      true

      iex> JidoCode.Utils.UUID.valid?("550E8400-E29B-41D4-A716-446655440000")
      true

      iex> JidoCode.Utils.UUID.valid?("not-a-uuid")
      false

      iex> JidoCode.Utils.UUID.valid?("")
      false

      iex> JidoCode.Utils.UUID.valid?(nil)
      false

      iex> JidoCode.Utils.UUID.valid?(123)
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value) do
    Regex.match?(@uuid_regex, value)
  end

  def valid?(_), do: false

  @doc """
  Returns the UUID regex pattern.

  Useful for modules that need to use the pattern directly
  (e.g., in guards or custom validations).

  ## Examples

      iex> Regex.match?(JidoCode.Utils.UUID.pattern(), "550e8400-e29b-41d4-a716-446655440000")
      true
  """
  @spec pattern() :: Regex.t()
  def pattern, do: @uuid_regex
end
