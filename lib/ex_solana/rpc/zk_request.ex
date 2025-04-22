defmodule ExSolana.RPC.ZKRequest do
  @moduledoc """
  Functions for creating Solana ZK Compression JSON-RPC API requests.
  """

  def get_compressed_account(_account, _opts \\ []), do: {:error, :not_implemented}
  def get_compressed_balance(_account, _opts \\ []), do: {:error, :not_implemented}
  def get_compressed_token_account_balance(_account, _opts \\ []), do: {:error, :not_implemented}
  def get_compressed_balance_by_owner(_owner, _opts \\ []), do: {:error, :not_implemented}
  def get_compressed_token_balances_by_owner(_owner, _opts \\ []), do: {:error, :not_implemented}
  def get_compressed_accounts_by_owner(_owner, _opts \\ []), do: {:error, :not_implemented}
  def get_multiple_compressed_accounts(_accounts, _opts \\ []), do: {:error, :not_implemented}
  def get_compressed_token_accounts_by_owner(_owner, _opts \\ []), do: {:error, :not_implemented}

  def get_compressed_token_accounts_by_delegate(_delegate, _opts \\ []), do: {:error, :not_implemented}

  def get_transaction_with_compression_info(_signature, _opts \\ []), do: {:error, :not_implemented}

  def get_compressed_account_proof(_account, _opts \\ []), do: {:error, :not_implemented}

  def get_multiple_compressed_account_proofs(_accounts, _opts \\ []), do: {:error, :not_implemented}

  def get_multiple_new_address_proofs(_addresses, _opts \\ []), do: {:error, :not_implemented}
  def get_validity_proof(_proof, _opts \\ []), do: {:error, :not_implemented}

  def get_compression_signatures_for_account(_account, _opts \\ []), do: {:error, :not_implemented}

  def get_compression_signatures_for_address(_address, _opts \\ []), do: {:error, :not_implemented}

  def get_compression_signatures_for_owner(_owner, _opts \\ []), do: {:error, :not_implemented}

  def get_compression_signatures_for_token_owner(_token_owner, _opts \\ []), do: {:error, :not_implemented}

  def get_latest_compression_signatures(_opts \\ []), do: {:error, :not_implemented}
  def get_latest_non_voting_signatures(_opts \\ []), do: {:error, :not_implemented}
  def get_indexer_slot(_opts \\ []), do: {:error, :not_implemented}
  def get_indexer_health(_opts \\ []), do: {:error, :not_implemented}
end
