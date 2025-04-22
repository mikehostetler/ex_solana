defmodule ExSolana.Program.Raydium.PoolV4 do
  @moduledoc false
  use ExSolana.ProgramBehaviour,
    idl_path: "priv/idl/raydium_amm.json",
    program_id: "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8",
    log_prefix: "Program log: ray_log: "

  use ExSolana.Util.DebugTools, debug_enabled: false

  alias ExSolana.Actions

  def analyze_ix(decoded_parsed_ix, confirmed_txn) do
    debug("Analyzing instruction",
      decoded_parsed_ix: decoded_parsed_ix,
      confirmed_txn: confirmed_txn
    )

    case decoded_parsed_ix.decoded_ix do
      {:swap_base_in, params} ->
        debug("Analyzing swap_base_in", params: params)
        analyze_swap(decoded_parsed_ix, confirmed_txn, :swap_base_in)

      {:swap_base_out, params} ->
        debug("Analyzing swap_base_out", params: params)
        analyze_swap(decoded_parsed_ix, confirmed_txn, :swap_base_out)

      unknown ->
        debug("Unknown instruction", instruction: unknown)
        {:error, :unknown_instruction}
    end
  end

  defp analyze_swap(decoded_parsed_ix, confirmed_txn, swap_type) do
    debug("Analyzing swap", swap_type: swap_type)

    with {:ok, owner} <- get_account_key(decoded_parsed_ix.ix.accounts, 17),
         {:ok, pool_address} <- get_account_key(decoded_parsed_ix.ix.accounts, 1),
         {:ok, token_balance_changes} <- get_token_balance_changes(confirmed_txn),
         {:ok, amount_in, amount_out} <- get_swap_amounts(decoded_parsed_ix.children, swap_type),
         {:ok, from_token, from_token_decimals} <-
           find_token(amount_in, token_balance_changes, :from),
         {:ok, to_token, to_token_decimals} <- find_token(amount_out, token_balance_changes, :to) do
      debug("Swap analysis successful",
        owner: owner,
        pool_address: pool_address,
        amount_in: amount_in,
        amount_out: amount_out,
        from_token: from_token,
        to_token: to_token
      )

      %Actions.TokenSwap{
        slot: confirmed_txn.slot,
        owner: owner,
        pool_address: pool_address,
        fee: confirmed_txn.additional.fee,
        amount_out: amount_out,
        amount_in: amount_in,
        to_token: to_token,
        to_token_decimals: to_token_decimals,
        from_token: from_token,
        from_token_decimals: from_token_decimals,
        price: calculate_price(amount_in, amount_out)
      }
    else
      error ->
        debug("Swap analysis failed", error: error)
        error
    end
  end

  defp get_account_key(accounts, index) do
    debug("Getting account key", index: index)

    case Enum.at(accounts, index) do
      %{key: key} when is_binary(key) ->
        debug("Account key found", key: key)
        {:ok, key}

      _ ->
        debug("Invalid account key", index: index)
        {:error, "Invalid account key at index #{index}"}
    end
  end

  defp get_token_balance_changes(%{additional: %{token_balance_changes: changes}}) when is_list(changes) do
    debug("Token balance changes found", changes: changes)
    {:ok, changes}
  end

  defp get_token_balance_changes(_) do
    debug("Invalid token balance changes")
    {:error, "Invalid token balance changes"}
  end

  defp get_swap_amounts(children, swap_type) do
    debug("Getting swap amounts", swap_type: swap_type)

    case {Enum.at(children, 0), Enum.at(children, 1)} do
      {%{action: %{amount: amount_out}}, %{action: %{amount: amount_in}}}
      when swap_type == :swap_base_in ->
        debug("Swap amounts found for swap_base_in", amount_in: amount_in, amount_out: amount_out)
        {:ok, amount_in, amount_out}

      {%{action: %{amount: amount_out}}, %{action: %{amount: amount_in}}}
      when swap_type == :swap_base_out ->
        debug("Swap amounts found for swap_base_out",
          amount_in: amount_in,
          amount_out: amount_out
        )

        {:ok, amount_in, amount_out}

      _ ->
        debug("Invalid swap amounts")
        {:error, "Invalid swap amounts"}
    end
  end

  defp find_token(amount, token_balance_changes, token_type) do
    debug("Finding token", amount: amount, token_type: token_type)
    change_amount = if token_type == :from, do: -amount, else: amount

    case Enum.find(token_balance_changes, fn change -> change.change == change_amount end) do
      %{token_mint_address: address, ui_amount_after: %{decimals: decimals}} ->
        debug("Token found", address: address, decimals: decimals)
        {:ok, address, decimals}

      _ ->
        debug("Token not found", amount: amount)
        {:error, "Token not found for amount #{amount}"}
    end
  end

  defp calculate_price(amount_in, amount_out) when is_number(amount_in) and is_number(amount_out) and amount_out != 0 do
    price = Decimal.div(Decimal.new(amount_in), Decimal.new(amount_out))
    debug("Price calculated", amount_in: amount_in, amount_out: amount_out, price: price)
    price
  end

  defp calculate_price(amount_in, amount_out) do
    debug("Invalid price calculation", amount_in: amount_in, amount_out: amount_out)
    Decimal.new(0)
  end
end
