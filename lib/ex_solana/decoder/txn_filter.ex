defmodule ExSolana.Decoder.TxnFilter do
  @moduledoc """
  Defines filter structures for Solana transaction actions and implements filtering for token swaps.
  """

  alias ExSolana.Actions.TokenSwap

  defmodule TokenSwapFilter do
    @moduledoc false
    @type t :: %__MODULE__{
            owner: String.t() | nil,
            from_token: String.t() | nil,
            to_token: String.t() | nil,
            min_amount_in: Decimal.t() | nil,
            max_amount_in: Decimal.t() | nil,
            min_amount_out: Decimal.t() | nil,
            max_amount_out: Decimal.t() | nil,
            min_price: Decimal.t() | nil,
            max_price: Decimal.t() | nil
          }

    defstruct [
      :owner,
      :from_token,
      :to_token,
      :min_amount_in,
      :max_amount_in,
      :min_amount_out,
      :max_amount_out,
      :min_price,
      :max_price
    ]
  end

  @type t :: %__MODULE__{
          token_swap: TokenSwapFilter.t()
        }

  defstruct [:token_swap]

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
