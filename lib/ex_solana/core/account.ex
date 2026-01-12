defmodule ExSolana.Account do
  @moduledoc """
  Functions, types, and structures related to Solana
  [accounts](https://docs.solana.com/developing/programming-model/accounts).
  """

  @typedoc """
  All the information needed to encode an account in a transaction message.
  """
  @type t :: %__MODULE__{
          signer?: boolean(),
          writable?: boolean(),
          key: ExSolana.key() | nil
        }

  @derive Jason.Encoder
  defstruct [
    :key,
    signer?: false,
    writable?: false
  ]

  @doc """
  Creates a new Account struct from a map of parameters.

  ## Parameters

  - `params`: A map containing the following optional keys:
    - `:key` - The account's public key (ExSolana.key())
    - `:signer?` - Boolean indicating if the account is a signer (default: false)
    - `:writable?` - Boolean indicating if the account is writable (default: false)

  ## Examples

      iex> ExSolana.Account.new(%{key: "some_public_key", signer?: true})
      %ExSolana.Account{key: "some_public_key", signer?: true, writable?: false}

  """
  @spec new(map()) :: t()
  def new(params) when is_map(params) do
    %__MODULE__{
      key: Map.get(params, :key),
      signer?: Map.get(params, :signer?, false),
      writable?: Map.get(params, :writable?, false)
    }
  end
end
