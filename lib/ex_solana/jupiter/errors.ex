defmodule ExSolana.Jupiter.Errors do
  @moduledoc """
  Error types and handling for Jupiter operations.

  This module provides a centralized exception type for Jupiter-related errors
  and helper functions for creating errors from HTTP responses.

  ## Error Reasons

  * `:invalid_api_key` - The API key is missing or invalid
  * `:rate_limited` - Too many requests to the Jupiter API
  * `:insufficient_liquidity` - Not enough liquidity for the requested swap
  * `:slippage_tolerance_exceeded` - Price moved beyond slippage tolerance
  * `:invalid_token_mint` - Invalid token mint address
  * `:invalid_amount` - Invalid swap amount
  * `:network_error` - Network communication error
  * `:timeout` - Request timeout
  * `:unknown_error` - Unknown error

  ## Example

      iex> raise ExSolana.Jupiter.Errors, reason: :invalid_api_key

      iex> ExSolana.Jupiter.Errors.from_http_status(401)
      %ExSolana.Jupiter.Errors{reason: :invalid_api_key, message: "Invalid API key"}

  """

  @type error_reason ::
          :invalid_api_key
          | :rate_limited
          | :insufficient_liquidity
          | :slippage_tolerance_exceeded
          | :invalid_token_mint
          | :invalid_amount
          | :network_error
          | :timeout
          | :unknown_error

  @type t :: %__MODULE__{
          reason: error_reason(),
          message: String.t(),
          details: map() | nil
        }

  defexception [:reason, :message, :details]

  @impl true
  def exception(opts) when is_list(opts) do
    reason = Keyword.get(opts, :reason, :unknown_error)

    message =
      case Keyword.get(opts, :message) do
        nil -> default_message(reason)
        msg when is_binary(msg) -> msg
      end

    details = Keyword.get(opts, :details)

    %__MODULE__{reason: reason, message: message, details: details}
  end

  @impl true
  def exception(opts) when is_map(opts) do
    exception(Map.to_list(opts))
  end

  @impl true
  def message(%__MODULE__{message: message}), do: message

  @doc """
  Creates an error from an HTTP status code.

  ## Examples

      iex> ExSolana.Jupiter.Errors.from_http_status(401)
      %ExSolana.Jupiter.Errors{reason: :invalid_api_key, message: "Invalid API key"}

      iex> ExSolana.Jupiter.Errors.from_http_status(429)
      %ExSolana.Jupiter.Errors{reason: :rate_limited, message: "Rate limit exceeded"}

  """
  @spec from_http_status(non_neg_integer()) :: t()
  def from_http_status(401) do
    exception(reason: :invalid_api_key, message: "Invalid API key")
  end

  def from_http_status(429) do
    exception(reason: :rate_limited, message: "Rate limit exceeded")
  end

  def from_http_status(503) do
    exception(reason: :network_error, message: "Service unavailable")
  end

  def from_http_status(504) do
    exception(reason: :timeout, message: "Gateway timeout")
  end

  def from_http_status(status) when status >= 500 do
    exception(reason: :network_error, message: "Server error: #{status}")
  end

  def from_http_status(status) when status >= 400 do
    exception(reason: :unknown_error, message: "Client error: #{status}")
  end

  def from_http_status(_status) do
    exception(reason: :unknown_error, message: "Unexpected HTTP status")
  end

  @doc """
  Creates an error from a response body.

  ## Examples

      iex> ExSolana.Jupiter.Errors.from_response_body(%{"error" => "Insufficient liquidity"})
      %ExSolana.Jupiter.Errors{message: "Insufficient liquidity"}

  """
  @spec from_response_body(map()) :: t()
  def from_response_body(%{"error" => error_msg}) when is_binary(error_msg) do
    exception(message: error_msg, reason: reason_from_message(error_msg))
  end

  def from_response_body(body) when is_map(body) do
    exception(
      message: "Unknown error response",
      reason: :unknown_error,
      details: body
    )
  end

  @doc """
  Creates an error for insufficient liquidity.

  """
  @spec insufficient_liquidity() :: t()
  def insufficient_liquidity do
    exception(
      reason: :insufficient_liquidity,
      message: "Insufficient liquidity for this swap"
    )
  end

  @doc """
  Creates an error for slippage tolerance exceeded.

  """
  @spec slippage_exceeded() :: t()
  def slippage_exceeded do
    exception(
      reason: :slippage_tolerance_exceeded,
      message: "Price moved beyond slippage tolerance"
    )
  end

  @doc """
  Creates an error for invalid token mint address.

  """
  @spec invalid_token_mint(String.t()) :: t()
  def invalid_token_mint(mint) when is_binary(mint) do
    exception(
      reason: :invalid_token_mint,
      message: "Invalid token mint address: #{mint}"
    )
  end

  @doc """
  Creates an error for invalid swap amount.

  """
  @spec invalid_amount(String.t()) :: t()
  def invalid_amount(reason) when is_binary(reason) do
    exception(
      reason: :invalid_amount,
      message: "Invalid swap amount: #{reason}"
    )
  end

  # Private helpers

  defp default_message(:invalid_api_key), do: "Invalid API key"
  defp default_message(:rate_limited), do: "Rate limit exceeded"
  defp default_message(:insufficient_liquidity), do: "Insufficient liquidity"
  defp default_message(:slippage_tolerance_exceeded), do: "Slippage tolerance exceeded"
  defp default_message(:invalid_token_mint), do: "Invalid token mint address"
  defp default_message(:invalid_amount), do: "Invalid swap amount"
  defp default_message(:network_error), do: "Network error"
  defp default_message(:timeout), do: "Request timeout"
  defp default_message(:unknown_error), do: "Unknown error"

  defp reason_from_message(msg) when is_binary(msg) do
    lower_msg = String.downcase(msg)

    cond do
      String.contains?(lower_msg, "insufficient") or String.contains?(lower_msg, "liquidity") ->
        :insufficient_liquidity

      String.contains?(lower_msg, "slippage") ->
        :slippage_tolerance_exceeded

      String.contains?(lower_msg, "token") or String.contains?(lower_msg, "mint") ->
        :invalid_token_mint

      String.contains?(lower_msg, "amount") ->
        :invalid_amount

      true ->
        :unknown_error
    end
  end
end
