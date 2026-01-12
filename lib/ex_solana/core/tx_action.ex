defmodule ExSolana.Transaction.Action do
  @moduledoc """
  Represents a single action performed during transaction execution.

  This module provides a structured way to represent and analyze
  individual actions within a Solana transaction.

  ## Fields

  - `:type` - The type of action (e.g., :transfer, :swap, :mint)
  - `:description` - Human-readable description of the action
  - `:details` - Additional details about the action (program-specific)

  ## Examples

      iex> action = %ExSolana.Transaction.Action{
      ...>   type: :transfer,
      ...>   description: "Transfer 1000 lamports from A to B",
      ...>   details: %{from: "address1", to: "address2", amount: 1000}
      ...> }

  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              type:
                Zoi.atom(description: "The type of action"),
              description:
                Zoi.string(description: "Human-readable description of the action"),
              details:
                Zoi.any(description: "Additional details about the action")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Creates a new transaction action.

  ## Options

    * `:type` - The type of action (required)
    * `:description` - Human-readable description (required)
    * `:details` - Additional details map (optional, defaults to %{})

  ## Examples

      action = ExSolana.Transaction.Action.new(
        type: :transfer,
        description: "Transfer 1000 lamports",
        details: %{amount: 1000}
      )

  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    type = Keyword.fetch!(opts, :type)
    description = Keyword.fetch!(opts, :description)
    details = Keyword.get(opts, :details, %{})

    %__MODULE__{
      type: type,
      description: description,
      details: details
    }
  end

  @doc """
  Creates a transfer action.

  """
  @spec transfer(Key.t(), Key.t(), integer()) :: t()
  def transfer(from, to, amount) do
    new(
      type: :transfer,
      description: "Transfer #{amount} lamports from #{short_key(from)} to #{short_key(to)}",
      details: %{from: from, to: to, amount: amount}
    )
  end

  @doc """
  Creates a token transfer action.

  """
  @spec token_transfer(Key.t(), Key.t(), String.t(), integer()) :: t()
  def token_transfer(from, to, mint, amount) do
    new(
      type: :token_transfer,
      description:
        "Transfer #{amount} tokens (mint: #{short_key(mint)}) from #{short_key(from)} to #{short_key(to)}",
      details: %{from: from, to: to, mint: mint, amount: amount}
    )
  end

  @doc """
  Creates a swap action.

  """
  @spec swap(Key.t(), String.t(), String.t(), integer()) :: t()
  def swap(user, from_mint, to_mint, amount) do
    new(
      type: :swap,
      description:
        "Swap #{amount} of #{short_key(from_mint)} for #{short_key(to_mint)}",
      details: %{user: user, from_mint: from_mint, to_mint: to_mint, amount: amount}
    )
  end

  @doc """
  Creates a mint tokens action.

  """
  @spec mint(Key.t(), Key.t(), integer()) :: t()
  def mint(mint_authority, mint, amount) do
    new(
      type: :mint,
      description: "Mint #{amount} tokens to #{short_key(mint)}",
      details: %{mint_authority: mint_authority, mint: mint, amount: amount}
    )
  end

  @doc """
  Creates a burn tokens action.

  """
  @spec burn(Key.t(), Key.t(), integer()) :: t()
  def burn(account, mint, amount) do
    new(
      type: :burn,
      description: "Burn #{amount} tokens from #{short_key(account)}",
      details: %{account: account, mint: mint, amount: amount}
    )
  end

  @doc """
  Creates a create account action.

  """
  @spec create_account(Key.t(), Key.t(), integer()) :: t()
  def create_account(payer, address, lamports) do
    new(
      type: :create_account,
      description: "Create account #{short_key(address)} with #{lamports} lamports",
      details: %{payer: payer, address: address, lamports: lamports}
    )
  end

  # Private helper for shortening keys
  defp short_key(key) when is_binary(key) do
    if byte_size(key) > 16 do
      String.slice(key, 0, 8) <> "..." <> String.slice(key, -8, 8)
    else
      key
    end
  end
end
