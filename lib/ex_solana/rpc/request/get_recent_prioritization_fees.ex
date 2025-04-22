defmodule ExSolana.RPC.Request.GetRecentPrioritizationFees do
  @moduledoc """
  Functions for creating a getRecentPrioritizationFees request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @doc """
  Returns a list of recent prioritization fees from recent blocks.

  ## Parameters

  - `addresses`: An array of account addresses as base-58 encoded strings (optional).

  ## Options

  {NimbleOptions.docs(@get_recent_prioritization_fees_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getrecentprioritizationfees).
  """
  @spec get_recent_prioritization_fees([ExSolana.key()] | nil) ::
          Request.t() | {:error, String.t()}
  def get_recent_prioritization_fees(addresses \\ nil) do
    with {:ok, encoded_addresses} <- encode_addresses(addresses) do
      {"getRecentPrioritizationFees", [encoded_addresses]}
    end
  end

  defp encode_addresses(nil), do: {:ok, nil}

  defp encode_addresses(addresses) when is_list(addresses) do
    encoded = Enum.map(addresses, &encode_key/1)

    if Enum.all?(encoded, fn result -> match?({:ok, _}, result) end) do
      {:ok, Enum.map(encoded, fn {:ok, key} -> key end)}
    else
      {:error, "Failed to encode one or more addresses"}
    end
  end

  defp encode_addresses(_), do: {:error, "Addresses must be a list of public keys or nil"}
end
