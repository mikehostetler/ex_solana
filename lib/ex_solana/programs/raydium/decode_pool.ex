defmodule ExSolana.Program.Raydium.DecodePool.V4 do
  @moduledoc false
  use ExSolana.Borsh,
    schema: [
      status: "u64",
      nonce: "u64",
      max_order: "u64",
      depth: "u64",
      base_decimal: "u64",
      quote_decimal: "u64",
      state: "u64",
      reset_flag: "u64",
      min_size: "u64",
      vol_max_cut_ratio: "u64",
      amount_wave_ratio: "u64",
      base_lot_size: "u64",
      quote_lot_size: "u64",
      min_price_multiplier: "u64",
      max_price_multiplier: "u64",
      system_decimal_value: "u64",
      min_separate_numerator: "u64",
      min_separate_denominator: "u64",
      trade_fee_numerator: "u64",
      trade_fee_denominator: "u64",
      pnl_numerator: "u64",
      pnl_denominator: "u64",
      swap_fee_numerator: "u64",
      swap_fee_denominator: "u64",
      base_need_take_pnl: "u64",
      quote_need_take_pnl: "u64",
      quote_total_pnl: "u64",
      base_total_pnl: "u64",
      pool_open_time: "u64",
      punish_pc_amount: "u64",
      punish_coin_amount: "u64",
      orderbook_to_init_time: "u64",
      swap_base_in_amount: "u128",
      swap_quote_out_amount: "u128",
      swap_base2quote_fee: "u64",
      swap_quote_in_amount: "u128",
      swap_base_out_amount: "u128",
      swap_quote2base_fee: "u64",
      base_vault: "pubkey",
      quote_vault: "pubkey",
      base_mint: "pubkey",
      quote_mint: "pubkey",
      lp_mint: "pubkey",
      open_orders: "pubkey",
      market_id: "pubkey",
      market_program_id: "pubkey",
      target_orders: "pubkey",
      withdraw_queue: "pubkey",
      lp_vault: "pubkey",
      owner: "pubkey",
      lp_reserve: "u64",
      padding: ["u64", 3]
    ]
end

defmodule ExSolana.Program.Raydium.DecodePool.V5 do
  @moduledoc false
  use ExSolana.Borsh,
    schema: [
      account_type: "u64",
      status: "u64",
      nonce: "u64",
      max_order: "u64",
      depth: "u64",
      base_decimal: "u64",
      quote_decimal: "u64",
      state: "u64",
      reset_flag: "u64",
      min_size: "u64",
      vol_max_cut_ratio: "u64",
      amount_wave_ratio: "u64",
      base_lot_size: "u64",
      quote_lot_size: "u64",
      min_price_multiplier: "u64",
      max_price_multiplier: "u64",
      system_decimals_value: "u64",
      abort_trade_factor: "u64",
      price_tick_multiplier: "u64",
      price_tick: "u64",
      min_separate_numerator: "u64",
      min_separate_denominator: "u64",
      trade_fee_numerator: "u64",
      trade_fee_denominator: "u64",
      pnl_numerator: "u64",
      pnl_denominator: "u64",
      swap_fee_numerator: "u64",
      swap_fee_denominator: "u64",
      base_need_take_pnl: "u64",
      quote_need_take_pnl: "u64",
      quote_total_pnl: "u64",
      base_total_pnl: "u64",
      pool_open_time: "u64",
      punish_pc_amount: "u64",
      punish_coin_amount: "u64",
      orderbook_to_init_time: "u64",
      swap_base_in_amount: "u128",
      swap_quote_out_amount: "u128",
      swap_quote_in_amount: "u128",
      swap_base_out_amount: "u128",
      swap_quote2base_fee: "u64",
      swap_base2quote_fee: "u64",
      base_vault: "pubkey",
      quote_vault: "pubkey",
      base_mint: "pubkey",
      quote_mint: "pubkey",
      lp_mint: "pubkey",
      model_data_account: "pubkey",
      open_orders: "pubkey",
      market_id: "pubkey",
      market_program_id: "pubkey",
      target_orders: "pubkey",
      owner: "pubkey",
      padding: ["u64", 64]
    ]
end

defmodule ExSolana.Program.Raydium.DecodePool do
  @moduledoc """
  Provides functionality to decode Raydium Pool V4 and V5 accounts.
  """

  alias ExSolana.Program.Raydium.DecodePool.V4
  alias ExSolana.Program.Raydium.DecodePool.V5

  @doc """
  Decodes the given binary data into a Raydium Pool V4 or V5 account struct.
  """
  @spec decode(binary()) :: {:ok, V4.t() | V5.t()} | {:error, String.t()}
  def decode(data) do
    case determine_version(data) do
      {:ok, :v4} -> V4.decode(data)
      {:ok, :v5} -> V5.decode(data)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Determines the version of the Raydium Pool based on the binary data.
  """
  @spec determine_version(binary()) :: {:ok, :v4 | :v5} | {:error, String.t()}
  def determine_version(data) do
    case ExSolana.Borsh.decode(data, account_type: "u64") do
      {:ok, {{:account_type, 0}, _rest}} -> {:ok, :v4}
      {:ok, {{:account_type, _non_zero}, _rest}} -> {:ok, :v5}
      {:error, _reason} -> {:error, "Failed to determine Raydium Pool version"}
    end
  end
end
