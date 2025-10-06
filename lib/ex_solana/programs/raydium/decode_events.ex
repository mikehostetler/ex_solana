defmodule ExSolana.Program.Raydium.PoolV4.DecodeEvents do
  @moduledoc """
  Decodes events from Raydium V4 Pool
  """
  def decode_events(logs, log_events) do
    logs
    |> Enum.map(&decode_event(&1, log_events))
    |> Enum.filter(&(&1 != nil))
  end

  defp decode_event(log, log_events) do
    if String.starts_with?(log, "Program log: ray_log: ") do
      log_data = String.trim_leading(log, "Program log: ray_log: ")

      case Base.decode64(log_data) do
        {:ok, decoded_data} ->
          case decoded_data do
            <<discriminant::little-unsigned-integer-size(8), rest::binary>> ->
              decode_event_data(log_events[discriminant], rest)

            _ ->
              {:error, :invalid_log_data}
          end

        :error ->
          {:error, :invalid_base64}
      end
    end
  end

  defp decode_event_data(
         :init,
         <<time::little-64, pc_decimals, coin_decimals, pc_lot_size::little-64,
           coin_lot_size::little-64, pc_amount::little-64, coin_amount::little-64,
           market::binary-32>>
       ) do
    {:init,
     %{
       time: time,
       pc_decimals: pc_decimals,
       coin_decimals: coin_decimals,
       pc_lot_size: pc_lot_size,
       coin_lot_size: coin_lot_size,
       pc_amount: pc_amount,
       coin_amount: coin_amount,
       market: B58.encode58(market)
     }}
  end

  defp decode_event_data(
         :deposit,
         <<max_coin::little-64, max_pc::little-64, base::little-64, pool_coin::little-64,
           pool_pc::little-64, pool_lp::little-64, calc_pnl_x::little-128, calc_pnl_y::little-128,
           deduct_coin::little-64, deduct_pc::little-64, mint_lp::little-64>>
       ) do
    {:deposit,
     %{
       max_coin: max_coin,
       max_pc: max_pc,
       base: base,
       pool_coin: pool_coin,
       pool_pc: pool_pc,
       pool_lp: pool_lp,
       calc_pnl_x: calc_pnl_x,
       calc_pnl_y: calc_pnl_y,
       deduct_coin: deduct_coin,
       deduct_pc: deduct_pc,
       mint_lp: mint_lp
     }}
  end

  defp decode_event_data(
         :withdraw,
         <<withdraw_lp::little-64, user_lp::little-64, pool_coin::little-64, pool_pc::little-64,
           pool_lp::little-64, calc_pnl_x::little-128, calc_pnl_y::little-128,
           out_coin::little-64, out_pc::little-64>>
       ) do
    {:withdraw,
     %{
       withdraw_lp: withdraw_lp,
       user_lp: user_lp,
       pool_coin: pool_coin,
       pool_pc: pool_pc,
       pool_lp: pool_lp,
       calc_pnl_x: calc_pnl_x,
       calc_pnl_y: calc_pnl_y,
       out_coin: out_coin,
       out_pc: out_pc
     }}
  end

  defp decode_event_data(
         :swap_base_in,
         <<amount_in::little-64, minimum_amount_out::little-64, direction::little-64,
           user_source::little-64, pool_coin::little-64, pool_pc::little-64,
           out_amount::little-64>>
       ) do
    {:swap_base_in,
     %{
       amount_in: amount_in,
       minimum_amount_out: minimum_amount_out,
       direction: direction,
       user_source: user_source,
       pool_coin: pool_coin,
       pool_pc: pool_pc,
       out_amount: out_amount
     }}
  end

  defp decode_event_data(
         :swap_base_out,
         <<max_amount_in::little-64, amount_out::little-64, direction::little-64,
           user_source::little-64, pool_coin::little-64, pool_pc::little-64,
           deduct_in::little-64>>
       ) do
    {:swap_base_out,
     %{
       max_amount_in: max_amount_in,
       amount_out: amount_out,
       direction: direction,
       user_source: user_source,
       pool_coin: pool_coin,
       pool_pc: pool_pc,
       deduct_in: deduct_in
     }}
  end

  defp decode_event_data(_, _) do
    {:error, :unknown_log_event}
  end
end
