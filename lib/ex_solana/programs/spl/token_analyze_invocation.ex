defmodule ExSolana.Spl.Token.AnalyzeInvocation do
  @moduledoc false
  alias ExSolana.Actions

  require IEx

  def analyze_ix(decoded_parsed_ix, confirmed_transaction) do
    case decoded_parsed_ix.decoded_ix do
      {:initialize_mint, _params} ->
        analyze_initialize_mint(decoded_parsed_ix, confirmed_transaction)

      {:initialize_account, _params} ->
        analyze_initialize_account(decoded_parsed_ix, confirmed_transaction)

      {:transfer, _params} ->
        analyze_transfer(decoded_parsed_ix, confirmed_transaction)

      {:approve, _params} ->
        analyze_approve(decoded_parsed_ix, confirmed_transaction)

      {:revoke, _params} ->
        analyze_revoke(decoded_parsed_ix, confirmed_transaction)

      {:set_authority, _params} ->
        analyze_set_authority(decoded_parsed_ix, confirmed_transaction)

      {:mint_to, _params} ->
        analyze_mint_to(decoded_parsed_ix, confirmed_transaction)

      {:burn, _params} ->
        analyze_burn(decoded_parsed_ix, confirmed_transaction)

      {:close_account, _params} ->
        analyze_close_account(decoded_parsed_ix, confirmed_transaction)

      {:freeze_account, _params} ->
        analyze_freeze_account(decoded_parsed_ix, confirmed_transaction)

      {:thaw_account, _params} ->
        analyze_thaw_account(decoded_parsed_ix, confirmed_transaction)

      _ ->
        {:unknown_action, %{}}
    end
  end

  defp analyze_initialize_mint(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: mint}, %{key: _rent}, %{key: mint_authority}] = decoded_parsed_ix.ix.accounts
    %{decimals: decimals} = elem(decoded_parsed_ix.decoded_ix, 1)

    %Actions.InitializeMint{
      mint: mint,
      decimals: decimals,
      mint_authority: mint_authority,
      # Assuming freeze authority is not set in this instruction
      freeze_authority: nil
    }
  end

  defp analyze_initialize_account(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: account}, %{key: mint}, %{key: owner}, %{key: rent}] = decoded_parsed_ix.ix.accounts

    %Actions.InitializeAccount{
      account: account,
      mint: mint,
      owner: owner,
      rent: rent
    }
  end

  defp analyze_transfer(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: source}, %{key: destination}, %{key: authority}] = decoded_parsed_ix.ix.accounts
    %{amount: amount} = elem(decoded_parsed_ix.decoded_ix, 1)

    %Actions.TokenTransfer{
      amount: amount,
      source: source,
      destination: destination,
      authority: authority
    }
  end

  defp analyze_mint_to(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: mint}, %{key: account}, %{key: _owner}] = decoded_parsed_ix.ix.accounts
    %{amount: amount} = elem(decoded_parsed_ix.decoded_ix, 1)

    %Actions.MintTokens{
      amount: amount,
      token: mint,
      recipient: account
    }
  end

  defp analyze_burn(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: account}, %{key: mint}, %{key: _owner}] = decoded_parsed_ix.ix.accounts
    %{amount: amount} = elem(decoded_parsed_ix.decoded_ix, 1)

    %Actions.BurnTokens{
      amount: amount,
      token: mint,
      account: account
    }
  end

  defp analyze_close_account(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: account}, %{key: destination}, %{key: owner}] = decoded_parsed_ix.ix.accounts

    %Actions.CloseTokenAccount{
      account: account,
      destination: destination,
      owner: owner
    }
  end

  defp analyze_approve(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: source}, %{key: delegate}, %{key: owner}] = decoded_parsed_ix.ix.accounts
    %{amount: amount} = elem(decoded_parsed_ix.decoded_ix, 1)

    %Actions.ApproveTokenDelegate{
      amount: amount,
      token: source,
      owner: owner,
      delegate: delegate
    }
  end

  defp analyze_revoke(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: source}, %{key: owner}] = decoded_parsed_ix.ix.accounts

    %Actions.RevokeTokenDelegate{
      token: source,
      owner: owner
    }
  end

  defp analyze_set_authority(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: account}, %{key: _current_authority}] = decoded_parsed_ix.ix.accounts

    %{authority_type: authority_type, new_authority: new_authority} =
      elem(decoded_parsed_ix.decoded_ix, 1)

    %Actions.SetTokenAuthority{
      token: account,
      authority_type: authority_type,
      new_authority: new_authority
    }
  end

  defp analyze_freeze_account(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: account}, %{key: mint}, %{key: _authority}] = decoded_parsed_ix.ix.accounts

    %Actions.FreezeTokenAccount{
      account: account,
      token: mint
    }
  end

  defp analyze_thaw_account(decoded_parsed_ix, _confirmed_transaction) do
    [%{key: account}, %{key: mint}, %{key: _authority}] = decoded_parsed_ix.ix.accounts

    %Actions.ThawTokenAccount{
      account: account,
      token: mint
    }
  end
end
