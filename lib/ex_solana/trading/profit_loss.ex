defmodule ExSolana.Trading.ProfitLoss do
  @moduledoc """
  Provides functionality for calculating profit and loss for a wallet.
  """

  alias ExSolana.Actions.TokenSwap
  alias ExSolana.Token
  alias ExSolana.Wallet

  @type entry :: %{
          timestamp: DateTime.t(),
          token: Token.t(),
          amount: Decimal.t(),
          cost_basis: Decimal.t(),
          current_value: Decimal.t(),
          profit_loss: Decimal.t()
        }

  @doc """
  Calculates the profit and loss for a wallet based on its transaction history.
  """
  @spec calculate(Wallet.t()) :: [entry()]
  def calculate(wallet) do
    wallet.transactions
    |> Enum.flat_map(&extract_swaps/1)
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.reduce([], &process_swap/2)
  end

  defp extract_swaps(transaction) do
    Enum.filter(transaction.invocations, &match?(%TokenSwap{}, &1))
  end

  defp process_swap(swap, acc) do
    # This is a simplified implementation. In a real-world scenario,
    # you would need to handle various edge cases and implement a more
    # sophisticated algorithm for tracking cost basis and calculating P&L.
    entry = %{
      timestamp: swap.timestamp,
      token: swap.to_token,
      amount: swap.amount_out,
      cost_basis: Decimal.div(swap.amount_in, swap.amount_out),
      # This should be fetched from a price feed
      current_value: swap.amount_out,
      profit_loss: Decimal.sub(swap.amount_out, swap.amount_in)
    }

    [entry | acc]
  end
end
