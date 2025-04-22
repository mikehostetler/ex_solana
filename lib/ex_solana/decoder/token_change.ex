defmodule ExSolana.Decoder.TokenChange do
  @moduledoc false
  alias ExSolana.Decoder.ProgramLookup
  alias ExSolana.Decoder.SolBalanceChange
  alias ExSolana.Decoder.TokenBalanceChange
  alias ExSolana.Transaction.Core.ConfirmedTransaction

  def compute_additional_data(%ConfirmedTransaction{} = decoded_transaction) do
    %{
      fee: get_fee(decoded_transaction),
      sol_balance_changes: compute_sol_balance_changes(decoded_transaction),
      token_balance_changes: compute_token_balance_changes(decoded_transaction)
    }
  end

  defp get_fee(%{transaction: %{meta: %{fee: fee}}}), do: fee

  defp compute_sol_balance_changes(%{transaction: %{meta: meta, transaction: %{message: message}}}) do
    account_keys = message.account_keys
    fee_payer = List.first(account_keys)

    meta.pre_balances
    |> Enum.zip(meta.post_balances)
    |> Enum.with_index()
    |> Enum.map(fn {{pre, post}, index} ->
      address = Enum.at(account_keys, index)
      change = post - pre

      %SolBalanceChange{
        address: address,
        name: ProgramLookup.get_program_name(address),
        writable?: is_writable?(message, index),
        signer?: is_signer?(message, index),
        fee_payer?: address == fee_payer,
        before: pre,
        after: post,
        change: change
      }
    end)
  end

  defp compute_token_balance_changes(%{transaction: %{meta: meta, transaction: %{message: message}}}) do
    pre_balances = Map.new(meta.pre_token_balances, &{&1.account_index, &1})
    post_balances = Map.new(meta.post_token_balances, &{&1.account_index, &1})

    all_account_indexes =
      MapSet.union(MapSet.new(Map.keys(pre_balances)), MapSet.new(Map.keys(post_balances)))

    all_account_indexes
    |> Enum.map(fn account_index ->
      pre = Map.get(pre_balances, account_index)
      post = Map.get(post_balances, account_index)
      address = Enum.at(message.account_keys, account_index)

      %TokenBalanceChange{
        owner: (pre && pre.owner) || (post && post.owner),
        address: address,
        before: (pre && pre.ui_token_amount.amount) || "0",
        after: (post && post.ui_token_amount.amount) || "0",
        change: compute_token_change(pre, post),
        token_mint_address: (pre && pre.mint) || (post && post.mint),
        ui_amount_before: pre && pre.ui_token_amount,
        ui_amount_after: post && post.ui_token_amount
      }
    end)
    |> Enum.sort_by(fn %{address: address} -> address end)
  end

  defp compute_token_change(nil, post), do: post.ui_token_amount.amount
  defp compute_token_change(pre, nil), do: "-#{pre.ui_token_amount.amount}"

  defp compute_token_change(pre, post) do
    pre_amount = String.to_integer(pre.ui_token_amount.amount)
    post_amount = String.to_integer(post.ui_token_amount.amount)
    post_amount - pre_amount
  end

  defp is_writable?(message, index) do
    num_readonly =
      message.header.num_readonly_signed_accounts + message.header.num_readonly_unsigned_accounts

    index < message.header.num_required_signatures || index >= num_readonly
  end

  defp is_signer?(message, index) do
    index < message.header.num_required_signatures
  end
end
