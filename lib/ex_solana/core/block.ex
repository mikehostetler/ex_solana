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

    @schema Zoi.struct(
              __MODULE__,
              %{
                blockhash: Zoi.string(description: "Block hash"),
                previous_blockhash:
                  Zoi.string(description: "Previous block hash")
                  |> Zoi.optional(),
                parent_slot:
                  Zoi.integer(description: "Parent slot number")
                  |> Zoi.optional(),
                block_time:
                  Zoi.integer(description: "Unix timestamp of block production")
                  |> Zoi.optional(),
                block_height:
                  Zoi.integer(description: "Block height")
                  |> Zoi.optional(),
                transactions:
                  Zoi.list(Zoi.any(), description: "Transactions in the block")
                  |> Zoi.default([])
                  |> Zoi.optional(),
                rewards:
                  Zoi.list(Zoi.any(), description: "Rewards distributed in the block")
                  |> Zoi.default([])
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

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

    @schema Zoi.struct(
              __MODULE__,
              %{
                signature:
                  Zoi.string(description: "Transaction signature")
                  |> Zoi.optional(),
                slot:
                  Zoi.integer(description: "Slot number")
                  |> Zoi.optional(),
                err:
                  Zoi.any(description: "Transaction error, if any")
                  |> Zoi.default(nil)
                  |> Zoi.optional(),
                fee:
                  Zoi.integer(description: "Transaction fee in lamports")
                  |> Zoi.optional(),
                meta:
                  Zoi.any(description: "Transaction metadata")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # Reward
  # ============================================================================

  defmodule Reward do
    @moduledoc """
    A reward distributed in a block.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                pubkey:
                  Zoi.string(description: "Public key of reward recipient")
                  |> Zoi.optional(),
                lamports:
                  Zoi.integer(description: "Reward amount in lamports")
                  |> Zoi.optional(),
                post_balance:
                  Zoi.integer(description: "Balance after reward")
                  |> Zoi.optional(),
                reward_type:
                  Zoi.string(description: "Type of reward: fee, rent, voting, staking")
                  |> Zoi.optional(),
                commission:
                  Zoi.integer(description: "Commission (if validator)")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # Block Metadata
  # ============================================================================

  defmodule Metadata do
    @moduledoc """
    Block metadata from getBlock RPC response.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                blockhash: Zoi.string(description: "Block hash"),
                block_height:
                  Zoi.integer(description: "Block height")
                  |> Zoi.optional(),
                block_time:
                  Zoi.integer(description: "Unix timestamp")
                  |> Zoi.optional(),
                parent_slot:
                  Zoi.integer(description: "Parent slot")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end
end
