#!/bin/bash

# Function to create a file for each RPC call
create_rpc_file() {
    local rpc_name=$1
    local file_name="new/$(echo $rpc_name | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:upper:]' '[:lower:]').ex"
    local module_name=$(echo $rpc_name | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:lower:]' '[:upper:]')

    mkdir -p "$(dirname "$file_name")"
    touch "$file_name"

    cat > "$file_name" <<EOF
defmodule ExSolana.RPC.Request.$module_name do
  @moduledoc """
  Functions for creating a $rpc_name request.
  """

  alias ExSolana.RPC.Request
  import ExSolana.RPC.Request.Helpers

  @${rpc_name}_options commitment_options() ++
                       encoding_options()

  @doc """
  Returns information for the $rpc_name request.

  ## Options

  #{NimbleOptions.docs(@${rpc_name}_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#${rpc_name}).
  """
  @spec ${rpc_name}(keyword()) :: Request.t() | {:error, String.t()}
  def ${rpc_name}(opts \\\\ []) do
    with {:ok, validated_opts} <- Request.validate(opts, @${rpc_name}_options) do
      {"$rpc_name", [Request.encode_opts(validated_opts)]}
    end
  end
end
EOF

    echo "Created file: $file_name"
}

# List of RPC calls
rpc_calls=(
    getAccountInfo
    getBalance
    getBlock
    getBlockCommitment
    getBlockHeight
    getBlockProduction
    getBlockTime
    getBlocks
    getBlocksWithLimit
    getClusterNodes
    getEpochInfo
    getEpochSchedule
    getFeeForMessage
    getFirstAvailableBlock
    getGenesisHash
    getHealth
    getHighestSnapshotSlot
    getIdentity
    getInflationGovernor
    getInflationRate
    getInflationReward
    getLargestAccounts
    getLatestBlockhash
    getLeaderSchedule
    getMaxRetransmitSlot
    getMaxShredInsertSlot
    getMinimumBalanceForRentExemption
    getMultipleAccounts
    getProgramAccounts
    getRecentPerformanceSamples
    getRecentPrioritizationFees
    getSignatureStatuses
    getSignaturesForAddress
    getSlot
    getSlotLeader
    getSlotLeaders
    getStakeActivation
    getStakeMinimumDelegation
    getSupply
    getTokenAccountBalance
    getTokenAccountsByDelegate
    getTokenAccountsByOwner
    getTokenLargestAccounts
    getTokenSupply
    getTransaction
    getTransactionCount
    getVersion
    getVoteAccounts
    isBlockhashValid
    minimumLedgerSlot
    requestAirdrop
    sendTransaction
    simulateTransaction
)

# Create files for each RPC call
for rpc_call in "${rpc_calls[@]}"; do
    create_rpc_file "$rpc_call"
done

echo "All RPC request files have been created."
