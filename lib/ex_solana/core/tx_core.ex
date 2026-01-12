defmodule ExSolana.Transaction.Core do
  @moduledoc """
  Core Solana transaction structures.

  Defines structs corresponding to Solana transaction structures,
  mirroring the Solana.Storage protobuf definitions.

  ## Types

  This module contains low-level transaction structures used throughout
  the ex_solana package. Most users should use the higher-level
  `ExSolana.Transaction` module instead.

  ## Examples

      iex> tx_meta = %ExSolana.Transaction.Core.TransactionStatusMeta{
      ...>   err: nil,
      ...>   fee: 5000,
      ...>   status: "Ok"
      ...> }

  """

  alias ExSolana.{Key, Signature}

  @type reward_type :: :unspecified | :fee | :rent | :staking | :voting

  @reward_types [:unspecified, :fee, :rent, :staking, :voting]

  @doc """
  Returns the list of valid reward types.
  """
  @spec reward_types() :: [reward_type()]
  def reward_types, do: @reward_types

  # ============================================================================
  # TransactionError
  # ============================================================================

  defmodule TransactionError do
    @moduledoc """
    Transaction error information.

    ## Fields

    - `:err` - Error code or message
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                err:
                  Zoi.string(description: "Transaction error message or code")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # AccountKey
  # ============================================================================

  defmodule AccountKey do
    @moduledoc """
    Account key metadata in a transaction.

    ## Fields

    - `:pubkey` - Public key (32 bytes)
    - `:signer` - Whether this account signed the transaction
    - `:writable` - Whether this account is writable

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                pubkey: Zoi.string(description: "Account public key (32 bytes)"),
                signer:
                  Zoi.boolean(description: "Whether this account signed the transaction")
                  |> Zoi.default(false),
                writable:
                  Zoi.boolean(description: "Whether this account is writable")
                  |> Zoi.default(false)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # InnerInstruction
  # ============================================================================

  defmodule InnerInstruction do
    @moduledoc """
    An inner instruction invoked during transaction processing.

    ## Fields

    - `:program_id_index` - Index of the program in the account keys list
    - `:accounts` - Account indices used by this instruction
    - `:data` - Instruction data
    - `:stack_height` - Stack height when this instruction was executed

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                program_id_index: Zoi.integer(description: "Index of program in account keys"),
                accounts: Zoi.string(description: "Account indices used by instruction"),
                data: Zoi.string(description: "Instruction data"),
                stack_height:
                  Zoi.integer(description: "Stack height at execution")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # InnerInstructions
  # ============================================================================

  defmodule InnerInstructions do
    @moduledoc """
    Inner instructions invoked during an instruction's execution.

    ## Fields

    - `:index` - Index of the outer instruction
    - `:instructions` - List of inner instructions

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                index: Zoi.integer(description: "Index of the outer instruction"),
                instructions:
                  Zoi.list(
                    Zoi.any(description: "List of inner instructions"),
                    description: "Inner instructions"
                  )
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # CompiledInstruction
  # ============================================================================

  defmodule CompiledInstruction do
    @moduledoc """
    A compiled instruction in a transaction message.

    ## Fields

    - `:program_id_index` - Index of the program in the account keys list
    - `:accounts` - Account indices used by this instruction
    - `:data` - Instruction data
    - `:stack_height` - Stack height when this instruction was executed
    - `:parsed` - Parsed instruction data (if available)

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                program_id_index: Zoi.integer(description: "Index of program in account keys"),
                accounts: Zoi.string(description: "Account indices used by instruction"),
                data: Zoi.string(description: "Instruction data"),
                stack_height:
                  Zoi.integer(description: "Stack height at execution")
                  |> Zoi.optional(),
                parsed:
                  Zoi.any(description: "Parsed instruction data")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # UiTokenAmount
  # ============================================================================

  defmodule UiTokenAmount do
    @moduledoc """
    UI representation of a token amount.

    ## Fields

    - `:ui_amount` - Token amount as float
    - `:decimals` - Token decimals
    - `:amount` - Raw amount string
    - `:ui_amount_string` - UI amount as string

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                ui_amount: Zoi.float(description: "Token amount as float"),
                decimals: Zoi.integer(description: "Token decimals"),
                amount: Zoi.string(description: "Raw amount string"),
                ui_amount_string: Zoi.string(description: "UI amount as string")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # TokenBalance
  # ============================================================================

  defmodule TokenBalance do
    @moduledoc """
    Token balance change in a transaction.

    ## Fields

    - `:account_index` - Index of the account in the transaction
    - `:mint` - Token mint address
    - `:ui_token_amount` - UI token amount
    - `:owner` - Token owner address
    - `:program_id` - Token program ID

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                account_index: Zoi.integer(description: "Account index in transaction"),
                mint: Zoi.string(description: "Token mint address"),
                ui_token_amount: Zoi.any(description: "UI token amount"),
                owner: Zoi.string(description: "Token owner address"),
                program_id: Zoi.string(description: "Token program ID")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # ReturnData
  # ============================================================================

  defmodule ReturnData do
    @moduledoc """
    Return data from a program invocation.

    ## Fields

    - `:program_id` - Program that returned data
    - `:data` - Returned data bytes

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                program_id: Zoi.string(description: "Program ID that returned data"),
                data: Zoi.string(description: "Returned data bytes")
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
    Reward distributed in a block.

    ## Fields

    - `:pubkey` - Reward recipient address
    - `:lamports` - Reward amount in lamports
    - `:post_balance` - Account balance after reward
    - `:reward_type` - Type of reward
    - `:commission` - Commission (if applicable)

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                pubkey: Zoi.string(description: "Reward recipient address"),
                lamports: Zoi.integer(description: "Reward amount in lamports"),
                post_balance: Zoi.integer(description: "Account balance after reward"),
                reward_type: Zoi.atom(description: "Type of reward"),
                commission:
                  Zoi.string(description: "Commission percentage")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # UnixTimestamp
  # ============================================================================

  defmodule UnixTimestamp do
    @moduledoc """
    Unix timestamp in a transaction.

    ## Fields

    - `:timestamp` - Unix timestamp

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                timestamp: Zoi.integer(description: "Unix timestamp")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # BlockHeight
  # ============================================================================

  defmodule BlockHeight do
    @moduledoc """
    Block height in a transaction.

    ## Fields

    - `:block_height` - Block height

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                block_height: Zoi.integer(description: "Block height")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # NumPartitions
  # ============================================================================

  defmodule NumPartitions do
    @moduledoc """
    Number of partitions in a transaction.

    ## Fields

    - `:num_partitions` - Number of partitions

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                num_partitions: Zoi.integer(description: "Number of partitions")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # LoadedAddress
  # ============================================================================

  defmodule LoadedAddress do
    @moduledoc """
    An address loaded from an Address Lookup Table.

    ## Fields

    - `:address` - Loaded address
    - `:stack_height` - Stack height when address was loaded

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                address: Zoi.string(description: "Loaded address"),
                stack_height:
                  Zoi.integer(description: "Stack height when loaded")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # LoadedAddresses
  # ============================================================================

  defmodule LoadedAddresses do
    @moduledoc """
    Addresses loaded from Address Lookup Tables.

    ## Fields

    - `:writable` - Writable addresses
    - `:readonly` - Read-only addresses

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                writable:
                  Zoi.list(
                    Zoi.any(description: "Writable addresses"),
                    description: "Writable addresses"
                  ),
                readonly:
                  Zoi.list(
                    Zoi.any(description: "Read-only addresses"),
                    description: "Read-only addresses"
                  )
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # TransactionStatusMeta
  # ============================================================================

  defmodule TransactionStatusMeta do
    @moduledoc """
    Transaction status and metadata.

    ## Fields

    - `:err` - Transaction error (if any)
    - `:fee` - Transaction fee in lamports
    - `:pre_balances` - Account balances before transaction
    - `:post_balances` - Account balances after transaction
    - `:inner_instructions` - Inner instructions invoked
    - `:inner_instructions_none` - Whether inner instructions were not requested
    - `:log_messages` - Program log messages
    - `:log_messages_none` - Whether logs were not requested
    - `:pre_token_balances` - Token balances before transaction
    - `:post_token_balances` - Token balances after transaction
    - `:rewards` - Rewards distributed
    - `:loaded_writable_addresses` - Writable addresses from ALTs
    - `:loaded_readonly_addresses` - Read-only addresses from ALTs
    - `:loaded_addresses` - All loaded addresses
    - `:status` - Transaction status
    - `:return_data` - Return data from programs
    - `:return_data_none` - Whether return data was not requested
    - `:compute_units_consumed` - Compute units consumed

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                err:
                  Zoi.any(description: "Transaction error")
                  |> Zoi.optional(),
                fee: Zoi.integer(description: "Transaction fee in lamports"),
                pre_balances:
                  Zoi.list(
                    Zoi.integer(description: "Pre-transaction balances"),
                    description: "Account balances before transaction"
                  ),
                post_balances:
                  Zoi.list(
                    Zoi.integer(description: "Post-transaction balances"),
                    description: "Account balances after transaction"
                  ),
                inner_instructions:
                  Zoi.list(
                    Zoi.any(description: "Inner instructions"),
                    description: "Inner instructions invoked"
                  )
                  |> Zoi.optional(),
                inner_instructions_none:
                  Zoi.boolean(description: "Whether inner instructions were not requested")
                  |> Zoi.optional(),
                log_messages:
                  Zoi.list(
                    Zoi.string(description: "Log messages"),
                    description: "Program log messages"
                  )
                  |> Zoi.optional(),
                log_messages_none:
                  Zoi.boolean(description: "Whether logs were not requested")
                  |> Zoi.optional(),
                pre_token_balances:
                  Zoi.list(
                    Zoi.any(description: "Pre-transaction token balances"),
                    description: "Token balances before transaction"
                  )
                  |> Zoi.optional(),
                post_token_balances:
                  Zoi.list(
                    Zoi.any(description: "Post-transaction token balances"),
                    description: "Token balances after transaction"
                  )
                  |> Zoi.optional(),
                rewards:
                  Zoi.list(
                    Zoi.any(description: "Rewards"),
                    description: "Rewards distributed"
                  )
                  |> Zoi.optional(),
                loaded_writable_addresses:
                  Zoi.list(
                    Zoi.string(description: "Writable addresses from ALTs"),
                    description: "Writable addresses from ALTs"
                  )
                  |> Zoi.optional(),
                loaded_readonly_addresses:
                  Zoi.list(
                    Zoi.string(description: "Read-only addresses from ALTs"),
                    description: "Read-only addresses from ALTs"
                  )
                  |> Zoi.optional(),
                loaded_addresses:
                  Zoi.any(description: "All loaded addresses")
                  |> Zoi.optional(),
                status:
                  Zoi.string(description: "Transaction status")
                  |> Zoi.optional(),
                return_data:
                  Zoi.any(description: "Return data from programs")
                  |> Zoi.optional(),
                return_data_none:
                  Zoi.boolean(description: "Whether return data was not requested")
                  |> Zoi.optional(),
                compute_units_consumed:
                  Zoi.integer(description: "Compute units consumed")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # MessageHeader
  # ============================================================================

  defmodule MessageHeader do
    @moduledoc """
    Transaction message header.

    ## Fields

    - `:num_required_signatures` - Number of signatures required
    - `:num_readonly_signed_accounts` - Number of read-only signed accounts
    - `:num_readonly_unsigned_accounts` - Number of read-only unsigned accounts

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                num_required_signatures:
                  Zoi.integer(description: "Number of signatures required"),
                num_readonly_signed_accounts:
                  Zoi.integer(description: "Number of read-only signed accounts"),
                num_readonly_unsigned_accounts:
                  Zoi.integer(description: "Number of read-only unsigned accounts")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # MessageAddressTableLookup
  # ============================================================================

  defmodule MessageAddressTableLookup do
    @moduledoc """
    Address Lookup Table lookup in a message.

    ## Fields

    - `:account_key` - Address Lookup Table account
    - `:writable_indexes` - Writable account indexes
    - `:readonly_indexes` - Read-only account indexes

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                account_key: Zoi.string(description: "Address Lookup Table account"),
                writable_indexes: Zoi.string(description: "Writable account indexes"),
                readonly_indexes: Zoi.string(description: "Read-only account indexes")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # Message
  # ============================================================================

  defmodule Message do
    @moduledoc """
    Transaction message.

    ## Fields

    - `:header` - Message header
    - `:account_keys` - Account keys in the message
    - `:recent_blockhash` - Recent blockhash
    - `:instructions` - Compiled instructions
    - `:versioned` - Whether this is a versioned message
    - `:address_table_lookups` - Address Lookup Table lookups

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                header: Zoi.any(description: "Message header"),
                account_keys:
                  Zoi.list(
                    Zoi.string(description: "Account keys"),
                    description: "Account keys in the message"
                  ),
                recent_blockhash: Zoi.string(description: "Recent blockhash"),
                instructions:
                  Zoi.list(
                    Zoi.any(description: "Compiled instructions"),
                    description: "Compiled instructions"
                  ),
                versioned:
                  Zoi.boolean(description: "Whether this is a versioned message")
                  |> Zoi.default(false),
                address_table_lookups:
                  Zoi.list(
                    Zoi.any(description: "Address Lookup Table lookups"),
                    description: "Address Lookup Table lookups"
                  )
                  |> Zoi.default([])
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # Transaction
  # ============================================================================

  defmodule Transaction do
    @moduledoc """
    Core transaction structure.

    ## Fields

    - `:signatures` - Transaction signatures
    - `:message` - Transaction message

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                signatures:
                  Zoi.list(
                    Zoi.string(description: "Transaction signatures"),
                    description: "Transaction signatures"
                  ),
                message: Zoi.any(description: "Transaction message")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # TransactionInfo
  # ============================================================================

  defmodule TransactionInfo do
    @moduledoc """
    Complete transaction information.

    ## Fields

    - `:transaction` - The transaction
    - `:signature` - Transaction signature
    - `:is_vote` - Whether this is a vote transaction
    - `:meta` - Transaction metadata
    - `:index` - Transaction index in block

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                transaction: Zoi.any(description: "The transaction"),
                signature: Zoi.string(description: "Transaction signature"),
                is_vote: Zoi.boolean(description: "Whether this is a vote transaction"),
                meta: Zoi.any(description: "Transaction metadata"),
                index: Zoi.integer(description: "Transaction index in block")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # ConfirmedTransaction
  # ============================================================================

  defmodule ConfirmedTransaction do
    @moduledoc """
    A confirmed transaction on chain.

    ## Fields

    - `:transaction` - The transaction
    - `:slot` - Slot number
    - `:block_time` - Block timestamp
    - `:version` - Transaction version

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                transaction: Zoi.any(description: "The transaction"),
                slot: Zoi.integer(description: "Slot number"),
                block_time: Zoi.integer(description: "Block timestamp"),
                version: Zoi.string(description: "Transaction version")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # Invocation
  # ============================================================================

  defmodule Invocation do
    @moduledoc """
    A program invocation.

    ## Fields

    - `:program_id` - Program ID
    - `:instruction` - Instruction name
    - `:params` - Instruction parameters
    - `:data` - Raw instruction data
    - `:accounts` - Accounts involved
    - `:logs` - Log messages
    - `:events` - Events emitted
    - `:analyzed_data` - Analyzed instruction data
    - `:actions` - Actions performed
    - `:inner_invocations` - Nested invocations

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                program_id: Zoi.string(description: "Program ID"),
                instruction: Zoi.atom(description: "Instruction name"),
                params:
                  Zoi.any(description: "Instruction parameters")
                  |> Zoi.default(%{}),
                data:
                  Zoi.string(description: "Raw instruction data")
                  |> Zoi.default(""),
                accounts:
                  Zoi.list(
                    Zoi.any(description: "Accounts involved"),
                    description: "Accounts involved"
                  )
                  |> Zoi.default([]),
                logs:
                  Zoi.list(
                    Zoi.string(description: "Log messages"),
                    description: "Log messages"
                  )
                  |> Zoi.default([]),
                events:
                  Zoi.any(description: "Events emitted")
                  |> Zoi.optional(),
                analyzed_data:
                  Zoi.any(description: "Analyzed instruction data")
                  |> Zoi.optional(),
                actions:
                  Zoi.list(
                    Zoi.any(description: "Actions performed"),
                    description: "Actions performed"
                  )
                  |> Zoi.default([]),
                inner_invocations:
                  Zoi.list(
                    Zoi.any(description: "Nested invocations"),
                    description: "Nested invocations"
                  )
                  |> Zoi.default([])
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # ParsedIx
  # ============================================================================

  defmodule ParsedIx do
    @moduledoc """
    A parsed instruction from transaction logs.

    ## Fields

    - `:id` - Instruction ID
    - `:parent` - Parent instruction ID
    - `:level` - Nesting level
    - `:children` - Child instruction IDs
    - `:logs` - Associated log messages
    - `:program` - Program ID
    - `:ix` - The instruction

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.integer(description: "Instruction ID"),
                parent: Zoi.integer(description: "Parent instruction ID"),
                level: Zoi.integer(description: "Nesting level"),
                children:
                  Zoi.list(
                    Zoi.integer(description: "Child instruction IDs"),
                    description: "Child instruction IDs"
                  ),
                logs:
                  Zoi.list(
                    Zoi.string(description: "Associated log messages"),
                    description: "Associated log messages"
                  ),
                program: Zoi.string(description: "Program ID"),
                ix: Zoi.any(description: "The instruction")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  # ============================================================================
  # AnalyzedIx
  # ============================================================================

  defmodule AnalyzedIx do
    @moduledoc """
    An analyzed instruction with decoded data.

    ## Fields

    - `:id` - Instruction ID
    - `:parent` - Parent instruction ID
    - `:level` - Nesting level
    - `:children` - Child instruction IDs
    - `:logs` - Associated log messages
    - `:program` - Program ID
    - `:ix` - The instruction
    - `:decoded_ix` - Decoded instruction data
    - `:event` - Parsed event
    - `:action` - Human-readable action

    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.integer(description: "Instruction ID"),
                parent: Zoi.integer(description: "Parent instruction ID"),
                level: Zoi.integer(description: "Nesting level"),
                children:
                  Zoi.list(
                    Zoi.integer(description: "Child instruction IDs"),
                    description: "Child instruction IDs"
                  ),
                logs:
                  Zoi.list(
                    Zoi.string(description: "Associated log messages"),
                    description: "Associated log messages"
                  ),
                program: Zoi.string(description: "Program ID"),
                ix: Zoi.any(description: "The instruction"),
                decoded_ix:
                  Zoi.any(description: "Decoded instruction data")
                  |> Zoi.optional(),
                event:
                  Zoi.any(description: "Parsed event")
                  |> Zoi.optional(),
                action:
                  Zoi.any(description: "Human-readable action")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end
end
