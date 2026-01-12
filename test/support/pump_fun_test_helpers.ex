defmodule ExSolana.PumpFunTestHelpers do
  @moduledoc """
  Test helpers for pump.fun integration testing.
  Supports both local test validator and testnet/mainnet configurations.
  """

  alias ExSolana.RPC

  @pump_program_id "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"
  @testnet_url "https://api.testnet.solana.com"
  @mainnet_url "https://api.mainnet-beta.solana.com"
  @devnet_url "https://api.devnet.solana.com"

  def pump_program_id, do: @pump_program_id

  @doc """
  Creates an RPC client for the specified network.
  Supports: :local, :testnet, :devnet, :mainnet
  """
  def rpc_client(network \\ :local) do
    case network do
      :local -> RPC.client(network: "localhost")
      :testnet -> RPC.client(base_url: @testnet_url)
      :devnet -> RPC.client(base_url: @devnet_url)
      :mainnet -> RPC.client(base_url: @mainnet_url)
    end
  end

  @doc """
  Checks if the pump.fun program is available on the specified network.
  """
  def program_available?(client) do
    case RPC.send(client, RPC.Request.get_account_info(@pump_program_id)) do
      {:ok, %{"executable" => true}} -> true
      _ -> false
    end
  end

  @doc """
  Derives the bonding curve PDA for a given mint.
  Note: This is a placeholder implementation for testing.
  """
  def bonding_curve_pda(mint_pubkey) do
    # For testing purposes, generate a deterministic address
    :crypto.hash(:sha256, "bonding-curve" <> mint_pubkey)
    |> binary_part(0, 32)
    |> B58.encode58()
  end

  @doc """
  Derives the global PDA for pump.fun.
  Note: This is a placeholder implementation for testing.
  """
  def global_pda do
    # For testing purposes, use a fixed address
    "11111111111111111111111111111111"
  end

  @doc """
  Derives the creator vault PDA for a given creator.
  Note: This is a placeholder implementation for testing.
  """
  def creator_vault_pda(creator_pubkey) do
    # For testing purposes, generate a deterministic address
    :crypto.hash(:sha256, "creator-vault" <> creator_pubkey)
    |> binary_part(0, 32)
    |> B58.encode58()
  end

  @doc """
  Waits for a transaction to be confirmed and returns the result.
  """
  def wait_for_confirmation(client, signature, max_attempts \\ 30) do
    Enum.reduce_while(1..max_attempts, :not_found, fn attempt, _acc ->
      case RPC.send(client, RPC.Request.get_signature_statuses([signature])) do
        {:ok, %{"value" => [%{"confirmationStatus" => status}]}}
        when status in ["confirmed", "finalized"] ->
          {:halt, :confirmed}

        {:ok, %{"value" => [%{"err" => error}]}} ->
          {:halt, {:error, error}}

        _ ->
          if attempt == max_attempts do
            {:halt, :timeout}
          else
            Process.sleep(1000)
            {:cont, :not_found}
          end
      end
    end)
  end

  @doc """
  Checks if we're running in a test environment with the test validator.
  """
  def using_test_validator? do
    # Check if we're using localhost RPC
    case System.get_env("SOLANA_RPC_URL") do
      # Default to test validator
      nil -> true
      "http://localhost:8899" -> true
      "http://127.0.0.1:8899" -> true
      _ -> false
    end
  end

  @doc """
  Gets the network configuration based on environment variables or defaults to local.
  """
  def get_network_config do
    case System.get_env("PUMP_TEST_NETWORK") do
      "testnet" -> :testnet
      "devnet" -> :devnet
      "mainnet" -> :mainnet
      _ -> :local
    end
  end

  # Private helper functions for instruction data encoding

  @doc """
  Encodes create instruction data for testing.
  """
  def encode_create_instruction_data(name, symbol, uri, creator) do
    # From IDL: discriminator [24, 30, 200, 40, 5, 28, 7, 119]
    discriminator = <<24, 30, 200, 40, 5, 28, 7, 119>>

    # Handle both binary and base58 string formats
    creator_binary =
      if is_binary(creator) and byte_size(creator) == 32 do
        creator
      else
        B58.decode58!(creator)
      end

    # String encoding: u32 length + utf8 bytes
    name_data = <<byte_size(name)::little-unsigned-integer-size(32)>> <> name
    symbol_data = <<byte_size(symbol)::little-unsigned-integer-size(32)>> <> symbol
    uri_data = <<byte_size(uri)::little-unsigned-integer-size(32)>> <> uri

    discriminator <> name_data <> symbol_data <> uri_data <> creator_binary
  end

  @doc """
  Encodes buy instruction data for testing.
  """
  def encode_buy_instruction_data(amount, max_sol_cost) do
    # From IDL: discriminator [102, 6, 61, 18, 1, 218, 235, 234]
    discriminator = <<102, 6, 61, 18, 1, 218, 235, 234>>

    discriminator <>
      <<amount::little-unsigned-integer-size(64)>> <>
      <<max_sol_cost::little-unsigned-integer-size(64)>>
  end

  @doc """
  Encodes sell instruction data for testing.
  """
  def encode_sell_instruction_data(amount, min_sol_output) do
    # From IDL: discriminator [51, 230, 133, 164, 1, 127, 131, 173]
    discriminator = <<51, 230, 133, 164, 1, 127, 131, 173>>

    discriminator <>
      <<amount::little-unsigned-integer-size(64)>> <>
      <<min_sol_output::little-unsigned-integer-size(64)>>
  end
end
