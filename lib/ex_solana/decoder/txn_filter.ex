defmodule ExSolana.Decoder.TxnFilter do
  @moduledoc """
  Defines filter structures for Solana transaction actions and implements filtering for token swaps.
  """

  use TypedStruct

  alias ExSolana.Actions.TokenSwap

  typedstruct module: TokenSwapFilter do
    field(:owner, String.t())
    field(:from_token, String.t())
    field(:to_token, String.t())
    field(:min_amount_in, Decimal.t())
    field(:max_amount_in, Decimal.t())
    field(:min_amount_out, Decimal.t())
    field(:max_amount_out, Decimal.t())
    field(:min_price, Decimal.t())
    field(:max_price, Decimal.t())
  end

  typedstruct do
    field(:token_swap, TokenSwapFilter.t())
  end

  @doc """
  Filters a list of actions based on the provided filters.

  Returns `{:ok, filtered_actions}` or `{:error, reason}`.
  """
  @spec filter(list(), t()) :: {:ok, list()} | {:error, atom()}
  def filter(actions, %__MODULE__{token_swap: token_swap_filter} = _filters)
      when is_list(actions) do
    filtered_actions = Enum.filter(actions, &action_matches_filter?(&1, token_swap_filter))

    case filtered_actions do
      [] -> {:error, :no_matching_actions}
      actions -> {:ok, actions}
    end
  end

  def filter(_, _), do: {:error, :invalid_input}

  defp action_matches_filter?(%TokenSwap{} = action, %TokenSwapFilter{} = filter) do
    owner_match?(action, filter) and
      token_match?(action, filter) and
      amount_in_range?(action, filter) and
      amount_out_range?(action, filter) and
      price_range?(action, filter)
  end

  defp action_matches_filter?(_, _), do: false

  defp owner_match?(%TokenSwap{owner: owner}, %TokenSwapFilter{owner: filter_owner}) do
    is_nil(filter_owner) or owner == filter_owner
  end

  defp token_match?(%TokenSwap{from_token: from, to_token: to}, %TokenSwapFilter{
         from_token: filter_from,
         to_token: filter_to
       }) do
    (is_nil(filter_from) or from == filter_from) and
      (is_nil(filter_to) or to == filter_to)
  end

  defp amount_in_range?(%TokenSwap{amount_in: amount}, %TokenSwapFilter{
         min_amount_in: min,
         max_amount_in: max
       }) do
    (is_nil(min) or Decimal.compare(amount, min) in [:gt, :eq]) and
      (is_nil(max) or Decimal.compare(amount, max) in [:lt, :eq])
  end

  defp amount_out_range?(%TokenSwap{amount_out: amount}, %TokenSwapFilter{
         min_amount_out: min,
         max_amount_out: max
       }) do
    (is_nil(min) or Decimal.compare(amount, min) in [:gt, :eq]) and
      (is_nil(max) or Decimal.compare(amount, max) in [:lt, :eq])
  end

  defp price_range?(%TokenSwap{price: price}, %TokenSwapFilter{min_price: min, max_price: max}) do
    (is_nil(min) or Decimal.compare(price, min) in [:gt, :eq]) and
      (is_nil(max) or Decimal.compare(price, max) in [:lt, :eq])
  end
end
