defmodule JidoCode.Error do
  @moduledoc """
  Standardized error handling for JidoCode.

  This module provides a consistent error structure across all JidoCode modules.
  All errors are returned as `{:error, %JidoCode.Error{}}` tuples for uniformity.

  ## Error Structure

  Each error contains:
  - `:code` - Atom identifying the error type (e.g., `:message_too_long`)
  - `:message` - Human-readable error message
  - `:details` - Optional map with additional context

  ## Usage

      # Create an error
      error = JidoCode.Error.new(:validation_failed, "Message too long", %{max: 10000})
      {:error, error}

      # Pattern match on error code
      case result do
        {:ok, value} -> value
        {:error, %JidoCode.Error{code: :not_found}} -> handle_not_found()
        {:error, %JidoCode.Error{code: :validation_failed, message: msg}} -> handle_validation(msg)
      end

  ## Standard Error Codes

  Configuration:
  - `:config_missing` - Required configuration not found
  - `:config_invalid` - Configuration value is invalid
  - `:provider_not_found` - LLM provider not found in registry
  - `:model_not_found` - Model not found for provider
  - `:api_key_missing` - API key not configured

  Validation:
  - `:validation_failed` - General validation failure
  - `:message_too_long` - Message exceeds maximum length
  - `:empty_message` - Message is empty

  Execution:
  - `:execution_failed` - Action execution failed
  - `:timeout` - Operation timed out
  - `:reasoning_failed` - CoT reasoning failed

  System:
  - `:internal_error` - Unexpected internal error
  - `:not_found` - Resource not found
  """

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: map() | nil
        }

  defstruct [:code, :message, :details]

  @doc """
  Creates a new error with the given code and message.

  ## Examples

      JidoCode.Error.new(:validation_failed, "Input is invalid")
      JidoCode.Error.new(:not_found, "User not found", %{user_id: 123})
  """
  @spec new(atom(), String.t(), map() | nil) :: t()
  def new(code, message, details \\ nil) when is_atom(code) and is_binary(message) do
    %__MODULE__{
      code: code,
      message: message,
      details: details
    }
  end

  @doc """
  Wraps an error in a tuple for consistent return values.

  ## Examples

      JidoCode.Error.wrap(:not_found, "Resource not found")
      # => {:error, %JidoCode.Error{code: :not_found, message: "Resource not found"}}
  """
  @spec wrap(atom(), String.t(), map() | nil) :: {:error, t()}
  def wrap(code, message, details \\ nil) do
    {:error, new(code, message, details)}
  end

  @doc """
  Converts a legacy error format to JidoCode.Error.

  Handles various legacy error formats:
  - `{:error, string}` - String error message
  - `{:error, {atom, string}}` - Tuple with code and message
  - `{:error, atom}` - Atom-only error
  - `{:error, %JidoCode.Error{}}` - Already wrapped

  ## Examples

      JidoCode.Error.from_legacy({:error, "Something went wrong"})
      # => {:error, %JidoCode.Error{code: :unknown, message: "Something went wrong"}}

      JidoCode.Error.from_legacy({:error, {:not_found, "User not found"}})
      # => {:error, %JidoCode.Error{code: :not_found, message: "User not found"}}
  """
  @spec from_legacy({:error, term()}) :: {:error, t()}
  def from_legacy({:error, %__MODULE__{} = error}), do: {:error, error}

  def from_legacy({:error, {code, message}}) when is_atom(code) and is_binary(message) do
    {:error, new(code, message)}
  end

  def from_legacy({:error, code}) when is_atom(code) do
    {:error, new(code, Atom.to_string(code))}
  end

  def from_legacy({:error, message}) when is_binary(message) do
    {:error, new(:unknown, message)}
  end

  def from_legacy({:error, other}) do
    {:error, new(:unknown, inspect(other))}
  end
end
