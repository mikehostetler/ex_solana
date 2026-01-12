defmodule ExSolana do
  @moduledoc """
  ExSolana - Solana library for Elixir (v0.2.0)

  Modernized core package with RPC, WebSocket, IDL, and transaction support.

  ## Features

  - **RPC Client**: JSON-RPC communication with Solana nodes
  - **WebSocket**: Real-time subscriptions and updates
  - **Key Management**: Keypair generation, encoding, and decoding
  - **Transactions**: Build, sign, and submit transactions
  - **IDL**: Parse and generate interface definitions
  - **Decoder**: Decode transactions and instructions
  - **Error Handling**: Structured errors with Splode

  ## Quick Start

      # Create RPC client
      client = ExSolana.RPC.client(network: :mainnet_beta)

      # Get account balance
      {:ok, balance} = ExSolana.RPC.get_balance(client, pubkey)

      # Build and send transaction
      tx = ExSolana.Ix.transfer(keypair, recipient, lamports: 1000)
      {:ok, signature} = ExSolana.RPC.send_transaction(client, tx)

  ## Error Handling

  ExSolana uses structured errors via `ExSolana.Error`:

      case ExSolana.Key.decode(pubkey) do
        {:ok, key} -> key
        {:error, %ExSolana.Error.InvalidKeyError{} = error} ->
          handle_error(error)
      end

  ## Configuration

  Configure the RPC client and default settings:

      config :ex_solana,
        network: :mainnet_beta,
        rpc_url: "https://api.mainnet-beta.solana.com"

  ## Migration from v0.1.0

  See the [Migration Guide](guides/migration.md) for details on upgrading from
  the legacy ex_solana_v1 package.

  ## Error Classes

  All errors inherit from `ExSolana.Error` and are organized by class:

  - `ExSolana.Error.InvalidKeyError` - Invalid keys or signatures
  - `ExSolana.Error.RPCError` - RPC communication failures
  - `ExSolana.Error.TransactionError` - Transaction operation failures
  - `ExSolana.Error.IDLError` - IDL processing failures
  - `ExSolana.Error.ValidationError` - General validation failures

  See `ExSolana.Error` for more details.
  """

  @type pubkey :: String.t()
  @type signature :: String.t()
  @type lamports :: non_neg_integer()

  # Core type aliases for convenience
  alias ExSolana.Key
  alias ExSolana.Account
  alias ExSolana.RPC
  alias ExSolana.Error
end
