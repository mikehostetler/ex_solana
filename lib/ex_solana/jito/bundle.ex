defmodule ExSolana.Jito.Bundle do
  @moduledoc """
  Functions for creating, encoding, and preparing Jito bundles from ExSolana transactions.

  Bundles are a list of transactions that execute sequentially and atomically,
  ensuring an all-or-nothing outcome within the same slot.

  Guidelines:
  - Bundles can contain up to 5 transactions.
  - Transactions in a bundle are guaranteed to execute in the order they are listed.
  - If any transaction in a bundle fails, none of the transactions will be committed.
  - Tips should be included as an instruction in one of the transactions in the bundle,
    typically the last one. This module does not handle tip creation or validation.
  """

  alias ExSolana.Jito.Bundle.Bundle
  alias ExSolana.Jito.Packet.Meta
  alias ExSolana.Jito.Packet.Packet
  alias ExSolana.Jito.Searcher.SendBundleRequest
  alias ExSolana.Jito.Shared.Header
  alias ExSolana.Transaction

  require Logger

  @max_transactions 5

  defstruct [:transactions, :header]

  @type t :: %__MODULE__{
          transactions: list(Transaction.t()),
          header: Header.t()
        }

  @doc """
  Builds a Jito bundle from a list of ExSolana transactions.

  ## Examples

      iex> ExSolana.Jito.Bundle.build([tx1, tx2, tx3])
      {:ok, %ExSolana.Jito.Bundle{...}}

  """
  @spec build(list(Transaction.t())) :: {:ok, t()} | {:error, atom()}
  def build(transactions) do
    case validate_transactions(transactions) do
      :ok ->
        bundle = %__MODULE__{
          transactions: transactions,
          header: %Header{ts: DateTime.utc_now()}
        }

        {:ok, bundle}

      {:error, reason} ->
        Logger.warning("Failed to build Jito Bundle: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Converts a Jito bundle to a SendBundleRequest for submission to the Jito network.
  """
  @spec to_request(t()) :: {:ok, SendBundleRequest.t()} | {:error, atom()}
  def to_request(%__MODULE__{} = bundle) do
    with {:ok, packets} <- build_packets(bundle.transactions) do
      request = %SendBundleRequest{
        bundle: %Bundle{
          header: bundle.header,
          packets: packets
        }
      }

      {:ok, request}
    end
  end

  defp build_packets(transactions) do
    packets = Enum.map(transactions, &transaction_to_packet/1)

    if Enum.any?(packets, &match?({:error, _}, &1)) do
      {:error, :transaction_conversion_failed}
    else
      {:ok, packets}
    end
  end

  defp transaction_to_packet(transaction) do
    case Transaction.to_binary(transaction) do
      {:ok, tx_data} ->
        %Packet{
          data: tx_data,
          meta: %Meta{
            size: byte_size(tx_data)
          }
        }

      {:error, reason} ->
        Logger.warning("Failed to convert transaction to binary: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_transactions(transactions) when length(transactions) > @max_transactions do
    {:error, :too_many_transactions}
  end

  defp validate_transactions(_transactions), do: :ok
end
