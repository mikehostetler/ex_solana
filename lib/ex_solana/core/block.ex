defmodule ExSolana.Block do
  @moduledoc """
  Solana block types and schemas.

  ## Overview

  Represents confirmed blocks and block-related data from the Solana blockchain.

  ## Examples

      # Decode a confirmed block from RPC response
      {:ok, block} = ExSolana.Block.Confirmed.from_rpc(response)

  """

  alias ExSolana.Error
  alias ExSolana.{Key, Signature}

  @typedoc """
  Unix timestamp in seconds since epoch.
  """
  @type unix_timestamp :: non_neg_integer()

  @typedoc """
  Block height (slot number).
  """
  @type block_height :: non_neg_integer()

  # ============================================================================
  # Confirmed Block
  # ============================================================================

  defmodule Confirmed do
    @moduledoc """
    A confirmed Solana block.

    Contains block metadata, transactions, and rewards.
    """

    use Zoi

    @schema Zoi.struct(
              __MODULE__,
              %{
                blockhash:
                  Zoi.string()
                  |> Zoi.description("Block hash"),
                previous_blockhash:
                  Zoi.string()
                  |> Zoi.description("Previous block hash")
                  |> Zoi.optional(),
                parent_slot:
                  Zoi.integer()
                  |> Zoi.description("Parent slot number")
                  |> Zoi.optional(),
                block_time:
                  Zoi.integer()
                  |> Zoi.description("Unix timestamp of block production")
                  |> Zoi.optional(),
                block_height:
                  Zoi.integer()
                  |> Zoi.description("Block height")
                  |> Zoi.optional(),
                transactions:
                  Zoi.list(Zoi.any())
                  |> Zoi.description("Transactions in the block")
                  |> Zoi.default([])
                  |> Zoi.optional(),
                rewards:
                  Zoi.list(Zoi.any())
                  |> Zoi.description("Rewards distributed in the block")
                  |> Zoi.default([])
                  |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [
      :blockhash,
      :previous_blockhash,
      :parent_slot,
      :block_time,
      :block_height,
      transactions: [],
      rewards: []
    ]

    @type t :: %__MODULE__{
            blockhash: String.t(),
            previous_blockhash: String.t() | nil,
            parent_slot: non_neg_integer() | nil,
            block_time: non_neg_integer() | nil,
            block_height: non_neg_integer() | nil,
            transactions: list(),
            rewards: list()
          }

    @doc """
    Creates a confirmed block from an RPC response.

    ## Parameters

    - `rpc_response` - Map from RPC response

    ## Returns

    - `{:ok, block}` - Valid confirmed block
    - `{:error, %ValidationError{}}` - Invalid response format

    """
    @spec from_rpc(map()) :: {:ok, t()} | {:error, Error.t()}
    def from_rpc(%{"blockhash" => blockhash} = response) when is_binary(blockhash) do
      {:ok,
       %__MODULE__{
         blockhash: blockhash,
         previous_blockhash: Map.get(response, "previousBlockhash"),
         parent_slot: Map.get(response, "parentSlot"),
         block_time: Map.get(response, "blockTime"),
         block_height: Map.get(response, "blockHeight"),
         transactions: Map.get(response, "transactions", []),
         rewards: Map.get(response, "rewards", [])
       }}
    end

    def from_rpc(_) do
      {:error, Error.validation_error("Invalid block response", field: :blockhash)}
    end
  end

  # ============================================================================
  # Confirmed Transaction
  # ============================================================================

  defmodule ConfirmedTransaction do
    @moduledoc """
    A confirmed transaction within a block.
    """

    use Zoi

    @schema Zoi.struct(
              __MODULE__,
              %{
                signature:
                  Zoi.binary()
                  |> Zoi.description("Transaction signature")
                  |> Zoi.optional(),
                slot:
                  Zoi.integer()
                  |> Zoi.description("Slot number")
                  |> Zoi.optional(),
                err:
                  Zoi.any()
                  |> Zoi.description("Transaction error, if any")
                  |> Zoi.default(nil)
                  |> Zoi.optional(),
                fee:
                  Zoi.integer()
                  |> Zoi.description("Transaction fee in lamports")
                  |> Zoi.optional(),
                meta:
                  Zoi.any()
                  |> Zoi.description("Transaction metadata")
                  |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:signature, :slot, :fee, :meta, err: nil]

    @type t :: %__MODULE__{
            signature: Signature.t() | nil,
            slot: non_neg_integer() | nil,
            err: any() | nil,
            fee: non_neg_integer() | nil,
            meta: map() | nil
          }
  end

  # ============================================================================
  # Reward
  # ============================================================================

  defmodule Reward do
    @moduledoc """
    A reward distributed in a block.
    """

    use Zoi

    @schema Zoi.struct(
              __MODULE__,
              %{
                pubkey:
                  Zoi.string()
                  |> Zoi.description("Public key of reward recipient")
                  |> Zoi.optional(),
                lamports:
                  Zoi.integer()
                  |> Zoi.description("Reward amount in lamports")
                  |> Zoi.optional(),
                post_balance:
                  Zoi.integer()
                  |> Zoi.description("Balance after reward")
                  |> Zoi.optional(),
                reward_type:
                  Zoi.string()
                  |> Zoi.description("Type of reward: fee, rent, voting, staking")
                  |> Zoi.optional(),
                commission:
                  Zoi.integer()
                  |> Zoi.description("Commission (if validator)")
                  |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:pubkey, :lamports, :post_balance, :reward_type, :commission]

    @type t :: %__MODULE__{
            pubkey: Key.t() | nil,
            lamports: integer() | nil,
            post_balance: non_neg_integer() | nil,
            reward_type: String.t() | nil,
            commission: non_neg_integer() | nil
          }
  end

  # ============================================================================
  # Block Metadata
  # ============================================================================

  defmodule Metadata do
    @moduledoc """
    Block metadata from getBlock RPC response.
    """

    use Zoi

    @schema Zoi.struct(
              __MODULE__,
              %{
                blockhash:
                  Zoi.string()
                  |> Zoi.description("Block hash"),
                block_height:
                  Zoi.integer()
                  |> Zoi.description("Block height")
                  |> Zoi.optional(),
                block_time:
                  Zoi.integer()
                  |> Zoi.description("Unix timestamp")
                  |> Zoi.optional(),
                parent_slot:
                  Zoi.integer()
                  |> Zoi.description("Parent slot")
                  |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:blockhash, :block_height, :block_time, :parent_slot]

    @type t :: %__MODULE__{
            blockhash: String.t(),
            block_height: non_neg_integer() | nil,
            block_time: non_neg_integer() | nil,
            parent_slot: non_neg_integer() | nil
          }
  end
end
