defmodule ExSolana.Actions do
  @moduledoc """
  Human-readable action representations for Solana transactions.

  These modules provide structured representations of decoded Solana
  instructions with human-readable descriptions.
  """

  defmodule Behaviour do
    @moduledoc """
    Behaviour for actions that can be converted to human-readable format.
    """
    @callback to_human_readable(struct()) :: String.t()

    defmacro __using__(_opts) do
      quote do
        @behaviour ExSolana.Actions.Behaviour

        def to_human_readable(struct) do
          "#{__MODULE__}: #{inspect(struct)}"
        end

        defoverridable to_human_readable: 1
      end
    end
  end

  defmodule RequestUnits do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                units:
                  Zoi.integer()
                  |> Zoi.default("Compute units requested")
              },
              coerce: true
            )

    defstruct [:units]

    def to_human_readable(%__MODULE__{} = action) do
      "Requested #{action.units} compute units"
    end
  end

  defmodule SetComputeUnitLimit do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                units:
                  Zoi.integer()
                  |> Zoi.default("Compute unit limit")
              },
              coerce: true
            )

    defstruct [:units]

    def to_human_readable(%__MODULE__{} = action) do
      "Set compute unit limit to #{action.units}"
    end
  end

  defmodule SetComputeUnitPrice do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                micro_lamports:
                  Zoi.integer()
                  |> Zoi.default("Micro-lamports per compute unit")
              },
              coerce: true
            )

    defstruct [:micro_lamports]

    def to_human_readable(%__MODULE__{} = action) do
      "Set compute unit price to #{action.micro_lamports} micro-lamports"
    end
  end

  defmodule CreateAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                lamports:
                  Zoi.integer()
                  |> Zoi.default("Lamports to fund the account"),
                space:
                  Zoi.integer()
                  |> Zoi.default("Account data space in bytes"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Owner program address")
              },
              coerce: true
            )

    defstruct [:lamports, :space, :owner]

    def to_human_readable(%__MODULE__{} = action) do
      "Created account with #{action.lamports} lamports and #{action.space} bytes of space"
    end
  end

  defmodule GetAccountDataSize do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                account:
                  Zoi.string()
                  |> Zoi.default("Account address")
              },
              coerce: true
            )

    defstruct [:account]

    def to_human_readable(%__MODULE__{} = action) do
      "Retrieved account data size for #{action.account}"
    end
  end

  defmodule TokenTransfer do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Token amount transferred"),
                source:
                  Zoi.string()
                  |> Zoi.default("Source token account"),
                destination:
                  Zoi.string()
                  |> Zoi.default("Destination token account"),
                authority:
                  Zoi.string()
                  |> Zoi.default("Authority that approved the transfer")
              },
              coerce: true
            )

    defstruct [:amount, :source, :destination, :authority]

    def to_human_readable(%__MODULE__{} = transfer) do
      "Transferred #{transfer.amount} tokens from #{transfer.source} to #{transfer.destination} by authority #{transfer.authority}"
    end
  end

  defmodule CreateAssociatedTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                funding_address:
                  Zoi.string()
                  |> Zoi.default("Account paying for creation"),
                associated_account_address:
                  Zoi.string()
                  |> Zoi.default("Associated token account address"),
                wallet_address:
                  Zoi.string()
                  |> Zoi.default("Wallet address"),
                token_mint_address:
                  Zoi.string()
                  |> Zoi.default("Token mint address")
              },
              coerce: true
            )

    defstruct [
      :funding_address,
      :associated_account_address,
      :wallet_address,
      :token_mint_address
    ]

    def to_human_readable(%__MODULE__{} = action) do
      "Created Associated Token Account #{action.associated_account_address} " <>
        "for wallet #{action.wallet_address} and token mint #{action.token_mint_address}, " <>
        "funded by #{action.funding_address}"
    end
  end

  defmodule CreateIdempotentAssociatedTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                funding_address:
                  Zoi.string()
                  |> Zoi.default("Account paying for creation"),
                associated_account_address:
                  Zoi.string()
                  |> Zoi.default("Associated token account address"),
                wallet_address:
                  Zoi.string()
                  |> Zoi.default("Wallet address"),
                token_mint_address:
                  Zoi.string()
                  |> Zoi.default("Token mint address")
              },
              coerce: true
            )

    defstruct [
      :funding_address,
      :associated_account_address,
      :wallet_address,
      :token_mint_address
    ]

    def to_human_readable(%__MODULE__{} = action) do
      "Created or verified Associated Token Account #{action.associated_account_address} " <>
        "for wallet #{action.wallet_address} and token mint #{action.token_mint_address}, " <>
        "funded by #{action.funding_address}"
    end
  end

  defmodule RecoverNestedAssociatedTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                nested_associated_account_address:
                  Zoi.string()
                  |> Zoi.default("Nested ATA to recover"),
                nested_token_mint_address:
                  Zoi.string()
                  |> Zoi.default("Nested token mint"),
                destination_associated_account_address:
                  Zoi.string()
                  |> Zoi.default("Destination ATA"),
                owner_associated_account_address:
                  Zoi.string()
                  |> Zoi.default("Owner ATA"),
                owner_token_mint_address:
                  Zoi.string()
                  |> Zoi.default("Owner token mint"),
                wallet_address:
                  Zoi.string()
                  |> Zoi.default("Wallet initiating recovery")
              },
              coerce: true
            )

    defstruct [
      :nested_associated_account_address,
      :nested_token_mint_address,
      :destination_associated_account_address,
      :owner_associated_account_address,
      :owner_token_mint_address,
      :wallet_address
    ]

    def to_human_readable(%__MODULE__{} = action) do
      "Recovered nested Associated Token Account #{action.nested_associated_account_address} " <>
        "for token mint #{action.nested_token_mint_address} to " <>
        "destination #{action.destination_associated_account_address}, " <>
        "owned by #{action.owner_associated_account_address} " <>
        "with token mint #{action.owner_token_mint_address}, " <>
        "initiated by wallet #{action.wallet_address}"
    end
  end

  defmodule SolTransfer do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("SOL amount transferred"),
                sender:
                  Zoi.string()
                  |> Zoi.default("Sender address"),
                recipient:
                  Zoi.string()
                  |> Zoi.default("Recipient address")
              },
              coerce: true
            )

    defstruct [:amount, :sender, :recipient]

    def to_human_readable(%__MODULE__{} = transfer) do
      "Sent #{transfer.amount} SOL from #{transfer.sender} to #{transfer.recipient}"
    end
  end

  defmodule TokenSwap do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                slot:
                  Zoi.integer()
                  |> Zoi.default("Slot number"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Swap owner"),
                from_token:
                  Zoi.string()
                  |> Zoi.default("Input token"),
                from_token_decimals:
                  Zoi.integer()
                  |> Zoi.default("Input token decimals"),
                to_token:
                  Zoi.string()
                  |> Zoi.default("Output token"),
                to_token_decimals:
                  Zoi.integer()
                  |> Zoi.default("Output token decimals"),
                pool_address:
                  Zoi.string()
                  |> Zoi.default("Pool address"),
                amount_in:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Input amount"),
                amount_out:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Output amount"),
                price:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Execution price"),
                fee:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Swap fee")
              },
              coerce: true
            )

    defstruct [
      :slot,
      :owner,
      :from_token,
      :from_token_decimals,
      :to_token,
      :to_token_decimals,
      :pool_address,
      :amount_in,
      :amount_out,
      :price,
      :fee
    ]

    def to_human_readable(%__MODULE__{} = swap) do
      "Owner #{swap.owner} swapped #{swap.amount_in} #{swap.from_token} for #{swap.amount_out} #{swap.to_token} " <>
        "on #{swap.pool_address} with a price of #{swap.price} and a fee of #{swap.fee}"
    end
  end

  defmodule LiquidityProvision do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount1:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("First token amount"),
                token1:
                  Zoi.string()
                  |> Zoi.default("First token symbol"),
                amount2:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Second token amount"),
                token2:
                  Zoi.string()
                  |> Zoi.default("Second token symbol"),
                pool:
                  Zoi.string()
                  |> Zoi.default("Pool address")
              },
              coerce: true
            )

    defstruct [:amount1, :token1, :amount2, :token2, :pool]

    def to_human_readable(%__MODULE__{} = provision) do
      "Added liquidity: #{Decimal.to_string(provision.amount1)} #{provision.token1} and #{Decimal.to_string(provision.amount2)} #{provision.token2} to #{provision.pool}"
    end
  end

  defmodule LiquidityRemoval do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("LP token amount"),
                pool:
                  Zoi.string()
                  |> Zoi.default("Pool address")
              },
              coerce: true
            )

    defstruct [:amount, :pool]

    def to_human_readable(%__MODULE__{} = removal) do
      "Removed liquidity: #{Decimal.to_string(removal.amount)} LP tokens from #{removal.pool}"
    end
  end

  defmodule StakeSol do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("SOL amount staked"),
                validator:
                  Zoi.string()
                  |> Zoi.default("Validator address")
              },
              coerce: true
            )

    defstruct [:amount, :validator]

    def to_human_readable(%__MODULE__{} = stake) do
      "Staked #{Decimal.to_string(stake.amount)} SOL to validator #{stake.validator}"
    end
  end

  defmodule UnstakeSol do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("SOL amount unstaked"),
                validator:
                  Zoi.string()
                  |> Zoi.default("Validator address")
              },
              coerce: true
            )

    defstruct [:amount, :validator]

    def to_human_readable(%__MODULE__{} = unstake) do
      "Unstaked #{Decimal.to_string(unstake.amount)} SOL from validator #{unstake.validator}"
    end
  end

  defmodule CreateTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Owner address")
              },
              coerce: true
            )

    defstruct [:token, :owner]

    def to_human_readable(%__MODULE__{} = create) do
      "Created new token account for #{create.token} owned by #{create.owner}"
    end
  end

  defmodule CloseTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                account:
                  Zoi.string()
                  |> Zoi.default("Token account address"),
                destination:
                  Zoi.string()
                  |> Zoi.default("Destination for lamports"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Owner address")
              },
              coerce: true
            )

    defstruct [:account, :destination, :owner]

    def to_human_readable(%__MODULE__{} = close) do
      "Closed token account #{close.account} owned by #{close.owner} and transferred to #{close.destination}"
    end
  end

  defmodule MintTokens do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Tokens minted"),
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol"),
                recipient:
                  Zoi.string()
                  |> Zoi.default("Recipient address")
              },
              coerce: true
            )

    defstruct [:amount, :token, :recipient]

    def to_human_readable(%__MODULE__{} = mint) do
      "Minted #{Decimal.to_string(mint.amount)} #{mint.token} to #{mint.recipient}"
    end
  end

  defmodule BurnTokens do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Tokens burned"),
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol"),
                account:
                  Zoi.string()
                  |> Zoi.default("Token account address")
              },
              coerce: true
            )

    defstruct [:amount, :token, :account]

    def to_human_readable(%__MODULE__{} = burn) do
      "Burned #{Decimal.to_string(burn.amount)} #{burn.token} from #{burn.account}"
    end
  end

  defmodule CreateNft do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token_id:
                  Zoi.string()
                  |> Zoi.default("NFT token ID"),
                collection:
                  Zoi.string()
                  |> Zoi.default("Collection name")
              },
              coerce: true
            )

    defstruct [:token_id, :collection]

    def to_human_readable(%__MODULE__{} = create) do
      "Created NFT #{create.token_id} in collection #{create.collection}"
    end
  end

  defmodule ListNftForSale do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token_id:
                  Zoi.string()
                  |> Zoi.default("NFT token ID"),
                price:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Listing price in SOL")
              },
              coerce: true
            )

    defstruct [:token_id, :price]

    def to_human_readable(%__MODULE__{} = list) do
      "Listed NFT #{list.token_id} for sale at #{Decimal.to_string(list.price)} SOL"
    end
  end

  defmodule BuyNft do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token_id:
                  Zoi.string()
                  |> Zoi.default("NFT token ID"),
                price:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Purchase price in SOL")
              },
              coerce: true
            )

    defstruct [:token_id, :price]

    def to_human_readable(%__MODULE__{} = buy) do
      "Purchased NFT #{buy.token_id} for #{Decimal.to_string(buy.price)} SOL"
    end
  end

  defmodule CancelNftListing do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token_id:
                  Zoi.string()
                  |> Zoi.default("NFT token ID")
              },
              coerce: true
            )

    defstruct [:token_id]

    def to_human_readable(%__MODULE__{} = cancel) do
      "Cancelled listing for NFT #{cancel.token_id}"
    end
  end

  defmodule DelegateStake do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Stake amount delegated"),
                delegate:
                  Zoi.string()
                  |> Zoi.default("Delegate address")
              },
              coerce: true
            )

    defstruct [:amount, :delegate]

    def to_human_readable(%__MODULE__{} = delegate) do
      "Delegated #{Decimal.to_string(delegate.amount)} stake to #{delegate.delegate}"
    end
  end

  defmodule CreateProgramAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                program:
                  Zoi.string()
                  |> Zoi.default("Program address")
              },
              coerce: true
            )

    defstruct [:program]

    def to_human_readable(%__MODULE__{} = create) do
      "Created program account for #{create.program}"
    end
  end

  defmodule UpgradeProgram do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                program:
                  Zoi.string()
                  |> Zoi.default("Program address")
              },
              coerce: true
            )

    defstruct [:program]

    def to_human_readable(%__MODULE__{} = upgrade) do
      "Upgraded program #{upgrade.program} to new version"
    end
  end

  defmodule Vote do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                validator:
                  Zoi.string()
                  |> Zoi.default("Validator vote address")
              },
              coerce: true
            )

    defstruct [:validator]

    def to_human_readable(%__MODULE__{} = vote) do
      "Submitted vote for validator #{vote.validator}"
    end
  end

  defmodule CreateMultisig do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                signers:
                  Zoi.integer()
                  |> Zoi.default("Total number of signers"),
                required_signatures:
                  Zoi.integer()
                  |> Zoi.default("Required signatures")
              },
              coerce: true
            )

    defstruct [:signers, :required_signatures]

    def to_human_readable(%__MODULE__{} = create) do
      "Created multisig wallet with #{create.signers} signers and #{create.required_signatures} required signatures"
    end
  end

  defmodule ApproveTokenDelegate do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                amount:
                  Zoi.struct(
                    Decimal,
                    %{}
                  )
                  |> Zoi.default("Delegated amount"),
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Token owner"),
                delegate:
                  Zoi.string()
                  |> Zoi.default("Delegate address")
              },
              coerce: true
            )

    defstruct [:amount, :token, :owner, :delegate]

    def to_human_readable(%__MODULE__{} = approve) do
      "Approved #{Decimal.to_string(approve.amount)} #{approve.token} to be spent by delegate #{approve.delegate} on behalf of #{approve.owner}"
    end
  end

  defmodule RevokeTokenDelegate do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Token owner")
              },
              coerce: true
            )

    defstruct [:token, :owner]

    def to_human_readable(%__MODULE__{} = revoke) do
      "Revoked delegation for #{revoke.token} owned by #{revoke.owner}"
    end
  end

  defmodule SetTokenAuthority do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                token:
                  Zoi.string()
                  |> Zoi.default("Token or mint address"),
                authority_type:
                  Zoi.atom()
                  |> Zoi.default("Authority type (:mint_tokens or :freeze_account)"),
                new_authority:
                  Zoi.string() |> Zoi.default("New authority address") |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:token, :authority_type, :new_authority]

    def to_human_readable(%__MODULE__{} = set_authority) do
      "Set #{set_authority.authority_type} authority for #{set_authority.token} to #{set_authority.new_authority || "None"}"
    end
  end

  defmodule FreezeTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                account:
                  Zoi.string()
                  |> Zoi.default("Token account address"),
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol")
              },
              coerce: true
            )

    defstruct [:account, :token]

    def to_human_readable(%__MODULE__{} = freeze) do
      "Froze token account #{freeze.account} for #{freeze.token}"
    end
  end

  defmodule ThawTokenAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                account:
                  Zoi.string()
                  |> Zoi.default("Token account address"),
                token:
                  Zoi.string()
                  |> Zoi.default("Token symbol")
              },
              coerce: true
            )

    defstruct [:account, :token]

    def to_human_readable(%__MODULE__{} = thaw) do
      "Thawed token account #{thaw.account} for #{thaw.token}"
    end
  end

  defmodule InitializeMint do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                mint:
                  Zoi.string()
                  |> Zoi.default("Mint address"),
                decimals:
                  Zoi.integer()
                  |> Zoi.default("Token decimals"),
                mint_authority:
                  Zoi.string()
                  |> Zoi.default("Mint authority address"),
                freeze_authority:
                  Zoi.string() |> Zoi.default("Freeze authority address") |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:mint, :decimals, :mint_authority, :freeze_authority]

    def to_human_readable(%__MODULE__{} = action) do
      "Initialized mint #{action.mint} with #{action.decimals} decimals, " <>
        "mint authority #{action.mint_authority}" <>
        if(action.freeze_authority,
          do: " and freeze authority #{action.freeze_authority}",
          else: ""
        )
    end
  end

  defmodule InitializeAccount do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                account:
                  Zoi.string()
                  |> Zoi.default("Token account address"),
                mint:
                  Zoi.string()
                  |> Zoi.default("Mint address"),
                owner:
                  Zoi.string()
                  |> Zoi.default("Owner address"),
                rent:
                  Zoi.string()
                  |> Zoi.default("Rent exemption authority")
              },
              coerce: true
            )

    defstruct [:account, :mint, :owner, :rent]

    def to_human_readable(%__MODULE__{} = action) do
      "Initialized token account #{action.account} for mint #{action.mint}, owned by #{action.owner}"
    end
  end

  defmodule InitializeMultisig do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                multisig:
                  Zoi.string()
                  |> Zoi.default("Multisig account address"),
                m:
                  Zoi.integer()
                  |> Zoi.default("Required signatures")
              },
              coerce: true
            )

    defstruct [:multisig, :m]

    def to_human_readable(%__MODULE__{} = action) do
      "Initialized multisig account #{action.multisig} requiring #{action.m} signatures"
    end
  end

  defmodule Unknown do
    @moduledoc false

    use ExSolana.Actions.Behaviour

    @schema Zoi.struct(
              __MODULE__,
              %{
                program: Zoi.string() |> Zoi.default("Program address") |> Zoi.optional(),
                discriminator:
                  Zoi.string() |> Zoi.default("Instruction discriminator") |> Zoi.optional(),
                description:
                  Zoi.string()
                  |> Zoi.default("Action description"),
                details: Zoi.map() |> Zoi.default("Additional details") |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:program, :discriminator, :description, :details]

    def to_human_readable(%__MODULE__{} = action) do
      "Unknown action: #{action.description}"
    end
  end

  defmodule TxnAction do
    @moduledoc """
    Generic transaction action wrapper.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                type:
                  Zoi.atom()
                  |> Zoi.default("Action type"),
                description:
                  Zoi.string()
                  |> Zoi.default("Human-readable description"),
                details: Zoi.map() |> Zoi.default("Additional details") |> Zoi.optional()
              },
              coerce: true
            )

    defstruct [:type, :description, :details]
  end
end
