defmodule ExSolana.Token do
  @moduledoc """
  Represents a token on the Solana blockchain.

  Used for SPL token operations and DEX integrations.

  ## Examples

      # Create a token
      token = ExSolana.Token.new(
        mint_address,
        "USDC",
        "USD Coin",
        6,
        true  # stablecoin
      )

      # Check if stablecoin
      ExSolana.Token.stablecoin?(token)
      #=> true

  """

  @typedoc """
  A Solana token.

  ## Fields

  - `:mint_address` - Token mint address (32 bytes)
  - `:symbol` - Token symbol (e.g., "USDC", "SOL")
  - `:name` - Full token name
  - `:decimals` - Number of decimals for display
  - `:is_stablecoin` - Whether the token is a stablecoin

  """
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

  ## Parameters

  - `mint_address` - Token mint address (32 bytes)
  - `symbol` - Token symbol (e.g., "USDC")
  - `name` - Full token name
  - `decimals` - Decimal places (e.g., 6 for USDC)
  - `is_stablecoin` - Whether it's a stablecoin (default: false)

  ## Returns

  A `%ExSolana.Token{}` struct.

  ## Examples

      token = ExSolana.Token.new(
        mint_address,
        "USDC",
        "USD Coin",
        6,
        true
      )

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

  ## Parameters

  - `token` - A `%ExSolana.Token{}` struct

  ## Returns

  `true` if the token is marked as a stablecoin, `false` otherwise.

  ## Examples

      ExSolana.Token.stablecoin?(usdc_token)
      #=> true

      ExSolana.Token.stablecoin?(sol_token)
      #=> false

  """
  @spec stablecoin?(t()) :: boolean()
  def stablecoin?(%__MODULE__{is_stablecoin: is_stablecoin}), do: is_stablecoin
end
