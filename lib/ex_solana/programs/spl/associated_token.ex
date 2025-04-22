defmodule ExSolana.SPL.AssociatedToken do
  @moduledoc """
  Functions for interacting with the [Associated Token Account
  Program](https://spl.solana.com/associated-token-account).

  An associated token account's address is derived from a user's main system
  account and the token mint, which means each user can only have one associated
  token account per token.
  """
  use ExSolana.ProgramBehaviour,
    idl_path: "priv/idl/spl_associated_token_account.json",
    program_id: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

  import ExSolana.Helpers

  alias ExSolana.Account
  alias ExSolana.Actions
  alias ExSolana.Instruction
  alias ExSolana.Key
  alias ExSolana.Native.SystemProgram
  alias ExSolana.SPL.Token
  alias ExSolana.Transaction.Core

  @doc """
  The Associated Token Account's Program ID
  """
  @impl true
  def id, do: ExSolana.pubkey!("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")

  @doc """
  Finds the token account address associated with a given owner and mint.

  This address will be unique to the mint/owner combination.
  """
  @spec find_address(mint :: ExSolana.key(), owner :: ExSolana.key()) ::
          {:ok, ExSolana.key()} | :error
  def find_address(mint, owner) do
    with true <- Ed25519.on_curve?(owner),
         {:ok, key, _} <- Key.find_address([owner, Token.id(), mint], id()) do
      {:ok, key}
    else
      _ -> :error
    end
  end

  @create_account_schema [
    payer: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "The account which will pay for the `new` account's creation"
    ],
    owner: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "The account which will own the `new` account"
    ],
    new: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Public key of the associated token account to create"
    ],
    mint: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "The mint of the `new` account"
    ]
  ]

  @doc """
  Creates an associated token account.

  This will be owned by the `owner` regardless of who actually creates it.

  ## Options

  #{NimbleOptions.docs(@create_account_schema)}
  """
  def create_account(opts) do
    case validate(opts, @create_account_schema) do
      {:ok, params} ->
        %Instruction{
          program: id(),
          accounts: [
            %Account{key: params.payer, writable?: true, signer?: true},
            %Account{key: params.new, writable?: true},
            %Account{key: params.owner},
            %Account{key: params.mint},
            %Account{key: SystemProgram.id()},
            %Account{key: Token.id()},
            %Account{key: ExSolana.rent()}
          ],
          data: Instruction.encode_data([0])
        }

      error ->
        error
    end
  end

  @impl true
  def analyze_invocation(%Core.Invocation{instruction: instruction_type} = invocation, confirmed_transaction) do
    case instruction_type do
      :create ->
        analyze_create(invocation, confirmed_transaction)

      :create_idempotent ->
        analyze_create_idempotent(invocation, confirmed_transaction)

      :recover_nested ->
        analyze_recover_nested(invocation, confirmed_transaction)

      _ ->
        {:unknown_action, %{}}
    end
  end

  defp analyze_create(invocation, _confirmed_transaction) do
    [
      %Actions.CreateAssociatedTokenAccount{
        funding_address: Enum.at(invocation.accounts, 0).key,
        associated_account_address: Enum.at(invocation.accounts, 1).key,
        wallet_address: Enum.at(invocation.accounts, 2).key,
        token_mint_address: Enum.at(invocation.accounts, 3).key
      }
    ]
  end

  defp analyze_create_idempotent(invocation, _confirmed_transaction) do
    [
      %Actions.CreateIdempotentAssociatedTokenAccount{
        funding_address: Enum.at(invocation.accounts, 0).key,
        associated_account_address: Enum.at(invocation.accounts, 1).key,
        wallet_address: Enum.at(invocation.accounts, 2).key,
        token_mint_address: Enum.at(invocation.accounts, 3).key
      }
    ]
  end

  defp analyze_recover_nested(invocation, _confirmed_transaction) do
    [
      %Actions.RecoverNestedAssociatedTokenAccount{
        nested_associated_account_address: Enum.at(invocation.accounts, 0).key,
        nested_token_mint_address: Enum.at(invocation.accounts, 1).key,
        destination_associated_account_address: Enum.at(invocation.accounts, 2).key,
        owner_associated_account_address: Enum.at(invocation.accounts, 3).key,
        owner_token_mint_address: Enum.at(invocation.accounts, 4).key,
        wallet_address: Enum.at(invocation.accounts, 5).key
      }
    ]
  end
end
