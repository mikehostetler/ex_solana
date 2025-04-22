defmodule ExSolana.Program.Raydium.PoolV4.DecodeInstruction do
  @moduledoc """
  Raydium V4 Pool
  """
  def decode_instruction(data, instructions) do
    case data do
      <<discriminant::little-unsigned-integer-size(8), rest::binary>> ->
        instruction_type = instructions[discriminant]
        decode_instruction_data(instruction_type, rest)

      _ ->
        {:error, :invalid_instruction_data}
    end
  end

  defp decode_instruction_data(:initialize, <<nonce, open_time::little-64, _rest::binary>>) do
    {:initialize, %{nonce: nonce, open_time: open_time}}
  end

  defp decode_instruction_data(
         :initialize2,
         <<nonce, open_time::little-64, init_pc_amount::little-64, init_coin_amount::little-64, _rest::binary>>
       ) do
    {:initialize2,
     %{
       nonce: nonce,
       open_time: open_time,
       init_pc_amount: init_pc_amount,
       init_coin_amount: init_coin_amount
     }}
  end

  defp decode_instruction_data(
         :monitor_step,
         <<plan_order_limit::little-16, place_order_limit::little-16, cancel_order_limit::little-16, _rest::binary>>
       ) do
    {:monitor_step,
     %{
       plan_order_limit: plan_order_limit,
       place_order_limit: place_order_limit,
       cancel_order_limit: cancel_order_limit
     }}
  end

  defp decode_instruction_data(
         :deposit,
         <<max_coin_amount::little-64, max_pc_amount::little-64, base_side::little-64, _rest::binary>>
       ) do
    {:deposit,
     %{
       max_coin_amount: max_coin_amount,
       max_pc_amount: max_pc_amount,
       base_side: base_side
     }}
  end

  defp decode_instruction_data(:withdraw, <<amount::little-64, _rest::binary>>) do
    {:withdraw, %{amount: amount}}
  end

  defp decode_instruction_data(:migrate_to_open_book, <<>>) do
    {:migrate_to_open_book, %{}}
  end

  defp decode_instruction_data(:set_params, <<param::8, rest::binary>>) do
    case decode_set_params_data(param, rest) do
      {:ok, params} -> {:set_params, params}
      error -> error
    end
  end

  defp decode_instruction_data(:withdraw_pnl, <<>>) do
    {:withdraw_pnl, %{}}
  end

  defp decode_instruction_data(:withdraw_srm, <<amount::little-64, _rest::binary>>) do
    {:withdraw_srm, %{amount: amount}}
  end

  defp decode_instruction_data(:swap_base_in, <<amount_in::little-64, minimum_amount_out::little-64, _rest::binary>>) do
    {:swap_base_in, %{amount_in: amount_in, minimum_amount_out: minimum_amount_out}}
  end

  defp decode_instruction_data(:pre_initialize, <<nonce, _rest::binary>>) do
    {:pre_initialize, %{nonce: nonce}}
  end

  defp decode_instruction_data(:swap_base_out, <<max_amount_in::little-64, amount_out::little-64, _rest::binary>>) do
    {:swap_base_out, %{max_amount_in: max_amount_in, amount_out: amount_out}}
  end

  defp decode_instruction_data(:simulate_info, <<param::8, rest::binary>>) do
    case decode_simulate_info_data(param, rest) do
      {:ok, params} -> {:simulate_info, params}
      error -> error
    end
  end

  defp decode_instruction_data(:admin_cancel_orders, <<limit::little-16, _rest::binary>>) do
    {:admin_cancel_orders, %{limit: limit}}
  end

  defp decode_instruction_data(:create_config_account, <<>>) do
    {:create_config_account, %{}}
  end

  defp decode_instruction_data(:update_config_account, <<param::8, owner::binary-32, _rest::binary>>) do
    {:update_config_account, %{param: param, owner: B58.encode58(owner)}}
  end

  defp decode_instruction_data(_, _) do
    {:error, :unknown_instruction}
  end

  defp decode_set_params_data(param, <<value::little-64, rest::binary>>) do
    case param do
      0 -> {:ok, %{param: param, value: value}}
      1 -> decode_set_params_pubkey(param, rest)
      2 -> decode_set_params_fees(param, rest)
      3 -> decode_set_params_last_order_distance(param, rest)
      4 -> decode_set_params_need_take(param, rest)
      _ -> {:error, :invalid_set_params}
    end
  end

  defp decode_set_params_pubkey(param, <<pubkey::binary-32, _rest::binary>>) do
    {:ok, %{param: param, new_pubkey: B58.encode58(pubkey)}}
  end

  defp decode_set_params_fees(
         param,
         <<min_separate_numerator::little-64, min_separate_denominator::little-64, trade_fee_numerator::little-64,
           trade_fee_denominator::little-64, pnl_numerator::little-64, pnl_denominator::little-64,
           swap_fee_numerator::little-64, swap_fee_denominator::little-64, _rest::binary>>
       ) do
    {:ok,
     %{
       param: param,
       fees: %{
         min_separate_numerator: min_separate_numerator,
         min_separate_denominator: min_separate_denominator,
         trade_fee_numerator: trade_fee_numerator,
         trade_fee_denominator: trade_fee_denominator,
         pnl_numerator: pnl_numerator,
         pnl_denominator: pnl_denominator,
         swap_fee_numerator: swap_fee_numerator,
         swap_fee_denominator: swap_fee_denominator
       }
     }}
  end

  defp decode_set_params_last_order_distance(
         param,
         <<last_order_numerator::little-64, last_order_denominator::little-64, _rest::binary>>
       ) do
    {:ok,
     %{
       param: param,
       last_order_distance: %{
         last_order_numerator: last_order_numerator,
         last_order_denominator: last_order_denominator
       }
     }}
  end

  defp decode_set_params_need_take(param, <<need_take_pc::little-64, need_take_coin::little-64, _rest::binary>>) do
    {:ok,
     %{
       param: param,
       need_take: %{
         need_take_pc: need_take_pc,
         need_take_coin: need_take_coin
       }
     }}
  end

  defp decode_simulate_info_data(param, rest) do
    case param do
      0 -> {:ok, %{param: param}}
      1 -> decode_simulate_info_swap_base_in(rest)
      2 -> decode_simulate_info_swap_base_out(rest)
      _ -> {:error, :invalid_simulate_info}
    end
  end

  defp decode_simulate_info_swap_base_in(<<amount_in::little-64, minimum_amount_out::little-64, _rest::binary>>) do
    {:ok,
     %{
       param: 1,
       swap_base_in_value: %{amount_in: amount_in, minimum_amount_out: minimum_amount_out}
     }}
  end

  defp decode_simulate_info_swap_base_out(<<max_amount_in::little-64, amount_out::little-64, _rest::binary>>) do
    {:ok, %{param: 2, swap_base_out_value: %{max_amount_in: max_amount_in, amount_out: amount_out}}}
  end
end
