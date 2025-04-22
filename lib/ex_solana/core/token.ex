defmodule ExSolana.Token do
  @moduledoc """
  Represents a token on the Solana blockchain.
  """
  require Logger

  @type t :: %__MODULE__{
          mint_address: ExSolana.Key.t(),
          symbol: String.t(),
          name: String.t(),
          decimals: non_neg_integer(),
          is_stablecoin: boolean()
        }

  defstruct [:mint_address, :symbol, :name, :decimals, :is_stablecoin]

  @doc """
  Creates a new token struct.
  """
  @spec new(ExSolana.Key.t(), String.t(), String.t(), non_neg_integer(), boolean()) :: t()
  def new(mint_address, symbol, name, decimals, is_stablecoin \\ false) do
    %__MODULE__{
      mint_address: mint_address,
      symbol: symbol,
      name: name,
      decimals: decimals,
      is_stablecoin: is_stablecoin
    }
  end

  @doc """
  Checks if a token is a stablecoin.
  """
  @spec stablecoin?(t()) :: boolean()
  def stablecoin?(%__MODULE__{is_stablecoin: is_stablecoin}), do: is_stablecoin
end
