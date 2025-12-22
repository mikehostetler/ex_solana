defmodule JidoCode.ErrorFormatter do
  @moduledoc """
  Shared error formatting utilities for consistent error message display.

  This module consolidates error formatting logic that was previously duplicated
  across multiple modules (Session.Manager, Tools.Manager, Tools.Result).

  ## Usage

      iex> ErrorFormatter.format(:not_found)
      "not_found"

      iex> ErrorFormatter.format("Something went wrong")
      "Something went wrong"

      iex> ErrorFormatter.format({:lua_error, "syntax error", []})
      "syntax error"
  """

  @doc """
  Formats an error reason into a human-readable string.

  Handles various error formats:
  - Binary strings (returned as-is)
  - Atoms (converted to string)
  - Charlists (converted to string)
  - `{:error, reason}` tuples (unwrapped and formatted)
  - `{:lua_error, error, stack}` tuples (extracts error)
  - Maps with `:message` key (extracts message)
  - Other terms (inspected)

  ## Examples

      iex> JidoCode.ErrorFormatter.format("file not found")
      "file not found"

      iex> JidoCode.ErrorFormatter.format(:enoent)
      "enoent"

      iex> JidoCode.ErrorFormatter.format({:error, :permission_denied})
      "permission_denied"

      iex> JidoCode.ErrorFormatter.format(%{message: "Invalid input"})
      "Invalid input"
  """
  @spec format(term()) :: String.t()
  def format(reason) when is_binary(reason), do: reason
  def format(reason) when is_atom(reason), do: Atom.to_string(reason)
  def format(reason) when is_list(reason), do: to_string(reason)
  def format({:error, reason}), do: format(reason)
  def format({:lua_error, error, _stack}), do: format(error)
  def format(%{message: message}) when is_binary(message), do: message
  def format(reason), do: inspect(reason)
end
