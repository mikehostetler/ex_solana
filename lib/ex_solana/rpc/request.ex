defmodule ExSolana.RPC.Request do
  @moduledoc """
  Functions for creating Solana JSON-RPC API requests.

  This client implements the most common methods. If you need a method that's on the [full
  list](https://docs.solana.com/developing/clients/jsonrpc-api#json-rpc-api-reference)
  but is not implemented here, please open an issue or contact the maintainers.
  """

  import ExSolana.RPC.Request.Helpers

  @typedoc "JSON-RPC API request (pre-encoding)"
  @type t :: {String.t(), [String.t() | map()]}

  @typedoc "JSON-RPC API request (JSON encoding)"
  @type json :: %{
          jsonrpc: String.t(),
          id: term(),
          method: String.t(),
          params: list()
        }

  @doc """
  Encodes a `t:ExSolana.RPC.Request.t/0` (or a list of them) in the required format.
  """
  @spec encode(requests :: t() | [t()]) :: json() | [json()]
  def encode(requests) when is_list(requests) do
    requests
    |> Enum.with_index()
    |> Enum.map(&to_json_rpc/1)
  end

  def encode(request), do: to_json_rpc({request, 0})

  defdelegate get_account_info(account, opts \\ []), to: ExSolana.RPC.Request.GetAccountInfo
  defdelegate get_balance(account, opts \\ []), to: ExSolana.RPC.Request.GetBalance
  defdelegate get_block(slot, opts \\ []), to: ExSolana.RPC.Request.GetBlock
  defdelegate get_block_commitment(slot), to: ExSolana.RPC.Request.GetBlockCommitment
  defdelegate get_block_height(opts \\ []), to: ExSolana.RPC.Request.GetBlockHeight
  defdelegate get_block_production(opts \\ []), to: ExSolana.RPC.Request.GetBlockProduction
  defdelegate get_block_time(slot), to: ExSolana.RPC.Request.GetBlockTime
  defdelegate get_blocks(start_slot, end_slot, opts \\ []), to: ExSolana.RPC.Request.GetBlocks

  defdelegate get_blocks_with_limit(start_slot, limit, opts \\ []),
    to: ExSolana.RPC.Request.GetBlocksWithLimit

  defdelegate get_cluster_nodes(), to: ExSolana.RPC.Request.GetClusterNodes
  defdelegate get_epoch_info(opts \\ []), to: ExSolana.RPC.Request.GetEpochInfo
  defdelegate get_epoch_schedule(), to: ExSolana.RPC.Request.GetEpochSchedule

  # defdelegate get_fee_for_message(message, opts \\ []), to: ExSolana.RPC.Request.GetFeeForMessage

  # defdelegate get_first_available_block(opts \\ []),
  #   to: ExSolana.RPC.Request.GetFirstAvailableBlock

  # defdelegate get_genesis_hash(opts \\ []), to: ExSolana.RPC.Request.GetGenesisHash
  defdelegate get_health(), to: ExSolana.RPC.Request.GetHealth

  # defdelegate get_highest_snapshot_slot(opts \\ []),
  #   to: ExSolana.RPC.Request.GetHighestSnapshotSlot

  # defdelegate get_identity(opts \\ []), to: ExSolana.RPC.Request.GetIdentity
  # defdelegate get_inflation_governor(opts \\ []), to: ExSolana.RPC.Request.GetInflationGovernor
  # defdelegate get_inflation_rate(opts \\ []), to: ExSolana.RPC.Request.GetInflationRate

  # defdelegate get_inflation_reward(addresses, opts \\ []),
  #   to: ExSolana.RPC.Request.GetInflationReward

  # defdelegate get_largest_accounts(opts \\ []), to: ExSolana.RPC.Request.GetLargestAccounts

  # getRecentBlockhash is deprecated, use getLatestBlockhash instead, support for it will be removed in v0.16.0
  defdelegate get_recent_blockhash(opts \\ []), to: ExSolana.RPC.Request.GetRecentBlockhash
  defdelegate get_latest_blockhash(opts \\ []), to: ExSolana.RPC.Request.GetLatestBlockhash

  # defdelegate get_leader_schedule(opts \\ []), to: ExSolana.RPC.Request.GetLeaderSchedule
  # defdelegate get_max_retransmit_slot(opts \\ []), to: ExSolana.RPC.Request.GetMaxRetransmitSlot

  # defdelegate get_max_shred_insert_slot(opts \\ []),
  #   to: ExSolana.RPC.Request.GetMaxShredInsertSlot

  defdelegate get_minimum_balance_for_rent_exemption(space, opts \\ []),
    to: ExSolana.RPC.Request.GetMinimumBalanceForRentExemption

  defdelegate get_multiple_accounts(pubkeys, opts \\ []),
    to: ExSolana.RPC.Request.GetMultipleAccounts

  defdelegate get_program_accounts(pubkey, opts \\ []),
    to: ExSolana.RPC.Request.GetProgramAccounts

  defdelegate get_recent_performance_samples(opts \\ []),
    to: ExSolana.RPC.Request.GetRecentPerformanceSamples

  defdelegate get_recent_prioritization_fees(addresses \\ nil),
    to: ExSolana.RPC.Request.GetRecentPrioritizationFees

  defdelegate get_signature_statuses(signatures, opts \\ []),
    to: ExSolana.RPC.Request.GetSignatureStatuses

  defdelegate get_signatures_for_address(address, opts \\ []),
    to: ExSolana.RPC.Request.GetSignaturesForAddress

  defdelegate get_slot(opts \\ []), to: ExSolana.RPC.Request.GetSlot
  defdelegate get_slot_leader(opts \\ []), to: ExSolana.RPC.Request.GetSlotLeader

  # defdelegate get_slot_leaders(start_slot, limit, opts \\ []),
  #   to: ExSolana.RPC.Request.GetSlotLeaders

  # defdelegate get_stake_minimum_delegation(opts \\ []),
  #   to: ExSolana.RPC.Request.GetStakeMinimumDelegation

  defdelegate get_supply(opts \\ []), to: ExSolana.RPC.Request.GetSupply

  defdelegate get_token_account_balance(pubkey, opts \\ []),
    to: ExSolana.RPC.Request.GetTokenAccountBalance

  # defdelegate get_token_accounts_by_delegate(delegate, opts \\ []),
  #   to: ExSolana.RPC.Request.GetTokenAccountsByDelegate

  defdelegate get_token_accounts_by_owner(owner, opts \\ []),
    to: ExSolana.RPC.Request.GetTokenAccountsByOwner

  defdelegate get_token_largest_accounts(mint, opts \\ []),
    to: ExSolana.RPC.Request.GetTokenLargestAccounts

  defdelegate get_token_supply(mint, opts \\ []), to: ExSolana.RPC.Request.GetTokenSupply
  defdelegate get_transaction(signature, opts \\ []), to: ExSolana.RPC.Request.GetTransaction
  # defdelegate get_transaction_count(opts \\ []), to: ExSolana.RPC.Request.GetTransactionCount
  defdelegate get_version(), to: ExSolana.RPC.Request.GetVersion
  # defdelegate get_vote_accounts(opts \\ []), to: ExSolana.RPC.Request.GetVoteAccounts
  defdelegate is_blockhash_valid(blockhash, opts \\ []), to: ExSolana.RPC.Request.IsBlockhashValid
  # defdelegate minimum_ledger_slot(), to: ExSolana.RPC.Request.MinimumLedgerSlot

  defdelegate request_airdrop(pubkey, lamports, opts \\ []),
    to: ExSolana.RPC.Request.RequestAirdrop

  defdelegate send_transaction(transaction, opts \\ []), to: ExSolana.RPC.Request.SendTransaction

  defdelegate simulate_transaction(transaction, opts \\ []),
    to: ExSolana.RPC.Request.SimulateTransaction
end
