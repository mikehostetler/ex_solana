defmodule ExSolana.Program.Raydium.PriceCalculator do
  @moduledoc """
  Calculates the price and other metrics for a Raydium liquidity pool.
  """

  alias ExSolana.Program.OpenOrders
  alias ExSolana.RPC.Request

  require IEx

  @native_mint "So11111111111111111111111111111111111111112"

  defmodule Tick do
    @moduledoc """
    Represents a price tick with associated pool information.
    """
    defstruct [:base_mint, :quote_mint, :base, :quote, :price, :pool_size_in_sol]
  end

  @doc """
  Calculates the price and other metrics for a Raydium liquidity pool.
  """
  def calculate_price(pool_state) do
    client = ExSolana.rpc_client()

    base_decimal = Decimal.from_float(:math.pow(10, pool_state.base_decimal))
    quote_decimal = Decimal.from_float(:math.pow(10, pool_state.quote_decimal))

    {:ok, base_token_amount} =
      ExSolana.RPC.send(
        client,
        Request.get_token_account_balance(pool_state.base_vault,
          commitment: "confirmed",
          encode_account: false
        )
      )

    {:ok, quote_token_amount} =
      ExSolana.RPC.send(
        client,
        Request.get_token_account_balance(pool_state.quote_vault,
          commitment: "confirmed",
          encode_account: false
        )
      )

    {:ok, open_orders_info} =
      ExSolana.RPC.send(
        client,
        Request.get_account_info(pool_state.open_orders,
          encoding: "base64",
          commitment: "confirmed",
          encode_account: false
        )
      )

    [data, "base64"] = open_orders_info["data"]
    {:ok, decoded_data} = Base.decode64(data)
    {:ok, open_orders} = OpenOrders.decode(decoded_data)

    base_pnl = Decimal.div(Decimal.new(pool_state.base_need_take_pnl), base_decimal)
    quote_pnl = Decimal.div(Decimal.new(pool_state.quote_need_take_pnl), quote_decimal)

    open_orders_base_token_total =
      Decimal.div(Decimal.new(open_orders.base_token_total), base_decimal)

    open_orders_quote_token_total =
      Decimal.div(Decimal.new(open_orders.quote_token_total), quote_decimal)

    base_amt =
      (base_token_amount["uiAmount"] || 0)
      |> Decimal.from_float()
      |> Decimal.add(open_orders_base_token_total)
      |> Decimal.sub(base_pnl)

    quote_amt =
      (quote_token_amount["uiAmount"] || 0)
      |> Decimal.from_float()
      |> Decimal.add(open_orders_quote_token_total)
      |> Decimal.sub(quote_pnl)

    {price_in_sol, pool_size_in_sol} =
      cond do
        pool_state.base_mint == @native_mint ->
          price = Decimal.div(base_amt, quote_amt)
          pool_size = Decimal.add(base_amt, Decimal.mult(quote_amt, price))
          {price, pool_size}

        pool_state.quote_mint == @native_mint ->
          price = Decimal.div(quote_amt, base_amt)
          pool_size = Decimal.add(quote_amt, Decimal.mult(base_amt, price))
          {price, pool_size}

        true ->
          {nil, nil}
      end

    %Tick{
      base_mint: pool_state.base_mint,
      quote_mint: pool_state.quote_mint,
      base: Decimal.to_string(base_amt),
      quote: Decimal.to_string(quote_amt),
      price: Decimal.to_string(price_in_sol),
      pool_size_in_sol: Decimal.to_string(pool_size_in_sol)
    }
  end
end
