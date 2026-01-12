defmodule ExSolana.Actions do
  @moduledoc false
  defmodule Behaviour do
    @moduledoc false
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
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:units, non_neg_integer(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Requested #{action.units} units"
    end
  end

  defmodule SetComputeUnitLimit do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:units, non_neg_integer(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Set compute unit limit to #{action.units}"
    end
  end

  defmodule SetComputeUnitPrice do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:micro_lamports, non_neg_integer(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Set compute unit price to #{action.micro_lamports} micro-lamports"
    end
  end

  defmodule CreateAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:lamports, non_neg_integer(), enforce: true)
      field(:space, non_neg_integer(), enforce: true)
      field(:owner, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Created account with #{action.lamports} lamports"
    end
  end

  defmodule GetAccountDataSize do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:account, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Retrieved account data size for #{action.account}"
    end
  end

  defmodule TokenTransfer do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:source, String.t(), enforce: true)
      field(:destination, String.t(), enforce: true)
      field(:authority, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = transfer) do
      "Transferred #{transfer.amount} tokens from #{transfer.source} to #{transfer.destination} by authority #{transfer.authority}"
    end
  end

  defmodule CreateAssociatedTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:funding_address, String.t(), enforce: true)
      field(:associated_account_address, String.t(), enforce: true)
      field(:wallet_address, String.t(), enforce: true)
      field(:token_mint_address, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Created Associated Token Account #{action.associated_account_address} " <>
        "for wallet #{action.wallet_address} and token mint #{action.token_mint_address}, " <>
        "funded by #{action.funding_address}"
    end
  end

  defmodule CreateIdempotentAssociatedTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:funding_address, String.t(), enforce: true)
      field(:associated_account_address, String.t(), enforce: true)
      field(:wallet_address, String.t(), enforce: true)
      field(:token_mint_address, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Created or verified Associated Token Account #{action.associated_account_address} " <>
        "for wallet #{action.wallet_address} and token mint #{action.token_mint_address}, " <>
        "funded by #{action.funding_address}"
    end
  end

  defmodule RecoverNestedAssociatedTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:nested_associated_account_address, String.t(), enforce: true)
      field(:nested_token_mint_address, String.t(), enforce: true)
      field(:destination_associated_account_address, String.t(), enforce: true)
      field(:owner_associated_account_address, String.t(), enforce: true)
      field(:owner_token_mint_address, String.t(), enforce: true)
      field(:wallet_address, String.t(), enforce: true)
    end

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
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:sender, String.t(), enforce: true)
      field(:recipient, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = transfer) do
      "Sent #{transfer.amount} SOL from #{transfer.sender} to #{transfer.recipient}"
    end
  end

  defmodule TokenSwap do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:slot, non_neg_integer(), enforce: true)
      field(:owner, String.t(), enforce: true)
      field(:from_token, String.t(), enforce: true)
      field(:from_token_decimals, non_neg_integer(), enforce: true)
      field(:to_token, String.t(), enforce: true)
      field(:to_token_decimals, non_neg_integer(), enforce: true)
      field(:pool_address, String.t(), enforce: true)
      field(:amount_in, Decimal.t(), enforce: true)
      field(:amount_out, Decimal.t(), enforce: true)
      field(:price, Decimal.t(), enforce: true)
      field(:fee, Decimal.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = swap) do
      # Convert Decimal values to strings safely
      # require IEx
      # IEx.pry()
      # amount_in = Decimal.to_string(swap.amount_in)
      # amount_out = Decimal.to_string(swap.amount_out)
      # price = Decimal.to_string(swap.price)
      # fee = Decimal.to_string(swap.fee)

      "Owner #{swap.owner} swapped #{swap.amount_in} #{swap.from_token} for #{swap.amount_out} #{swap.to_token} " <>
        "on #{swap.pool_address} with a price of #{swap.price} and a fee of #{swap.fee}"
    end
  end

  defmodule LiquidityProvision do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount1, Decimal.t(), enforce: true)
      field(:token1, String.t(), enforce: true)
      field(:amount2, Decimal.t(), enforce: true)
      field(:token2, String.t(), enforce: true)
      field(:pool, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = provision) do
      "Added liquidity: #{Decimal.to_string(provision.amount1)} #{provision.token1} and #{Decimal.to_string(provision.amount2)} #{provision.token2} to #{provision.pool}"
    end
  end

  defmodule LiquidityRemoval do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:pool, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = removal) do
      "Removed liquidity: #{Decimal.to_string(removal.amount)} LP tokens from #{removal.pool}"
    end
  end

  defmodule StakeSol do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:validator, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = stake) do
      "Staked #{Decimal.to_string(stake.amount)} SOL to validator #{stake.validator}"
    end
  end

  defmodule UnstakeSol do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:validator, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = unstake) do
      "Unstaked #{Decimal.to_string(unstake.amount)} SOL from validator #{unstake.validator}"
    end
  end

  defmodule CreateTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token, String.t(), enforce: true)
      field(:owner, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = create) do
      "Created new token account for #{create.token} owned by #{create.owner}"
    end
  end

  defmodule CloseTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:account, String.t(), enforce: true)
      field(:destination, String.t(), enforce: true)
      field(:owner, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = close) do
      "Closed token account #{close.account} owned by #{close.owner} and transferred to #{close.destination}"
    end
  end

  defmodule MintTokens do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:token, String.t(), enforce: true)
      field(:recipient, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = mint) do
      "Minted #{Decimal.to_string(mint.amount)} #{mint.token} to #{mint.recipient}"
    end
  end

  defmodule BurnTokens do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:token, String.t(), enforce: true)
      field(:account, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = burn) do
      "Burned #{Decimal.to_string(burn.amount)} #{burn.token} from #{burn.account}"
    end
  end

  defmodule CreateNft do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token_id, String.t(), enforce: true)
      field(:collection, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = create) do
      "Created NFT #{create.token_id} in collection #{create.collection}"
    end
  end

  defmodule ListNftForSale do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token_id, String.t(), enforce: true)
      field(:price, Decimal.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = list) do
      "Listed NFT #{list.token_id} for sale at #{Decimal.to_string(list.price)} SOL"
    end
  end

  defmodule BuyNft do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token_id, String.t(), enforce: true)
      field(:price, Decimal.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = buy) do
      "Purchased NFT #{buy.token_id} for #{Decimal.to_string(buy.price)} SOL"
    end
  end

  defmodule CancelNftListing do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token_id, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = cancel) do
      "Cancelled listing for NFT #{cancel.token_id}"
    end
  end

  defmodule DelegateStake do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:delegate, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = delegate) do
      "Delegated #{Decimal.to_string(delegate.amount)} stake to #{delegate.delegate}"
    end
  end

  defmodule CreateProgramAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:program, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = create) do
      "Created program account for #{create.program}"
    end
  end

  defmodule UpgradeProgram do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:program, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = upgrade) do
      "Upgraded program #{upgrade.program} to new version"
    end
  end

  defmodule Vote do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:validator, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = vote) do
      "Submitted vote for validator #{vote.validator}"
    end
  end

  defmodule CreateMultisig do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:signers, non_neg_integer(), enforce: true)
      field(:required_signatures, non_neg_integer(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = create) do
      "Created multisig wallet with #{create.signers} signers and #{create.required_signatures} required signatures"
    end
  end

  defmodule ApproveTokenDelegate do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:amount, Decimal.t(), enforce: true)
      field(:token, String.t(), enforce: true)
      field(:owner, String.t(), enforce: true)
      field(:delegate, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = approve) do
      "Approved #{Decimal.to_string(approve.amount)} #{approve.token} to be spent by delegate #{approve.delegate} on behalf of #{approve.owner}"
    end
  end

  defmodule RevokeTokenDelegate do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token, String.t(), enforce: true)
      field(:owner, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = revoke) do
      "Revoked delegation for #{revoke.token} owned by #{revoke.owner}"
    end
  end

  defmodule SetTokenAuthority do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:token, String.t(), enforce: true)
      field(:authority_type, atom(), enforce: true)
      field(:new_authority, String.t())
    end

    def to_human_readable(%__MODULE__{} = set_authority) do
      "Set #{set_authority.authority_type} authority for #{set_authority.token} to #{set_authority.new_authority || "None"}"
    end
  end

  defmodule FreezeTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:account, String.t(), enforce: true)
      field(:token, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = freeze) do
      "Froze token account #{freeze.account} for #{freeze.token}"
    end
  end

  defmodule ThawTokenAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:account, String.t(), enforce: true)
      field(:token, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = thaw) do
      "Thawed token account #{thaw.account} for #{thaw.token}"
    end
  end

  defmodule InitializeMint do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:mint, String.t(), enforce: true)
      field(:decimals, non_neg_integer(), enforce: true)
      field(:mint_authority, String.t(), enforce: true)
      field(:freeze_authority, String.t())
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Initialized mint #{action.mint} with #{action.decimals} decimals, " <>
        "mint authority #{action.mint_authority}" <>
        if action.freeze_authority,
          do: " and freeze authority #{action.freeze_authority}",
          else: ""
    end
  end

  defmodule InitializeAccount do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:account, String.t(), enforce: true)
      field(:mint, String.t(), enforce: true)
      field(:owner, String.t(), enforce: true)
      field(:rent, String.t(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Initialized token account #{action.account} for mint #{action.mint}, owned by #{action.owner}"
    end
  end

  defmodule InitializeMultisig do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:multisig, String.t(), enforce: true)
      field(:m, non_neg_integer(), enforce: true)
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Initialized multisig account #{action.multisig} requiring #{action.m} signatures"
    end
  end

  defmodule Unknown do
    @moduledoc false
    use TypedStruct
    use ExSolana.Actions.Behaviour

    typedstruct do
      field(:program, String.t(), default: "unknown")
      field(:discriminator, String.t(), default: nil)
      field(:description, String.t(), default: "")
      field(:details, map(), default: %{})
    end

    def to_human_readable(%__MODULE__{} = action) do
      "Unknown action: #{action.description}"
    end
  end
end
