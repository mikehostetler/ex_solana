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
  alias ExSolana.Mnemonic
  alias ExSolana.Transaction
  alias ExSolana.Signature
  alias ExSolana.Block
  alias ExSolana.RPC
  alias ExSolana.Error

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  @doc """
  Generates a new random keypair.

  ## Examples

      keypair = ExSolana.keypair()

  """
  @spec keypair() :: Key.Keypair.t()
  defdelegate keypair, to: Key.Keypair, as: :generate

  @doc """
  Extracts the public key from a keypair.

  For a keypair tuple or struct, returns the public key.
  For an encoded public key string, decodes and validates it.

  ## Examples

      ExSolana.pubkey!(keypair)
      #=> <<binary_public_key>>

      ExSolana.pubkey!("7mfY3uUuQoJLoQV3wYnTkn6H3Y3NQYjWXxZHFUkgHqE")
      #=> <<decoded_key>>

  """
  @spec pubkey!(Key.Keypair.t() | String.t()) :: Key.t()
  def pubkey!(%Key.Keypair{pubkey: pubkey}), do: pubkey

  def pubkey!(encoded) when is_binary(encoded) do
    case Key.decode(encoded) do
      {:ok, pubkey} -> pubkey
      {:error, _error} -> raise ArgumentError, "Invalid public key: #{encoded}"
    end
  end

  @doc """
  Common Solana system program addresses.
  """

  @spec sol() :: Key.t()
  def sol, do: pubkey!("So11111111111111111111111111111111111111112")

  @spec rent() :: Key.t()
  def rent, do: pubkey!("SysvarRent111111111111111111111111111111111")

  @spec recent_blockhashes() :: Key.t()
  def recent_blockhashes,
    do: pubkey!("SysvarRecentB1ockHashes11111111111111111111")

  @spec clock() :: Key.t()
  def clock, do: pubkey!("SysvarC1ock11111111111111111111111111111111")

  @spec bpf_loader() :: Key.t()
  def bpf_loader, do: pubkey!("BPFLoaderUpgradeab1e11111111111111111111111")
end
