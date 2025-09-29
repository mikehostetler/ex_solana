defmodule ExSolana.Program.PumpFunTest do
  use ExUnit.Case, async: true

  alias ExSolana.Program.PumpFun

  describe "ExSolana.Program.PumpFun instruction decoding" do
    test "correctly decodes a 'buy' instruction" do
      # From pump-fun.json IDL:
      # "name": "buy", "discriminator": [102, 6, 61, 18, 1, 218, 235, 234]
      # "args": [{ "name": "amount", "type": "u64" }, { "name": "maxSolCost", "type": "u64" }]
      discriminator = <<102, 6, 61, 18, 1, 218, 235, 234>>
      amount = 1_000_000
      max_sol_cost = 500_000

      # Construct the binary data: discriminator + amount (u64le) + max_sol_cost (u64le)
      buy_instruction_data =
        discriminator <>
          <<amount::little-unsigned-integer-size(64)>> <>
          <<max_sol_cost::little-unsigned-integer-size(64)>>

      expected_result = {:buy, %{amount: amount, max_sol_cost: max_sol_cost}}

      assert PumpFun.decode_ix(buy_instruction_data) == expected_result
    end

    test "correctly decodes a 'sell' instruction" do
      # From pump-fun.json IDL:
      # "name": "sell", "discriminator": [51, 230, 133, 164, 1, 127, 131, 173]
      # "args": [{ "name": "amount", "type": "u64" }, { "name": "minSolOutput", "type": "u64" }]
      discriminator = <<51, 230, 133, 164, 1, 127, 131, 173>>
      amount = 500_000_000
      min_sol_output = 200_000

      sell_instruction_data =
        discriminator <>
          <<amount::little-unsigned-integer-size(64)>> <>
          <<min_sol_output::little-unsigned-integer-size(64)>>

      expected_result = {:sell, %{amount: amount, min_sol_output: min_sol_output}}

      assert PumpFun.decode_ix(sell_instruction_data) == expected_result
    end

    test "returns :unknown_ix for an unrecognized instruction" do
      invalid_data = <<255, 1, 2, 3, 4, 5, 6, 7, 8>>
      assert {:unknown_ix, %{data: ^invalid_data}} = PumpFun.decode_ix(invalid_data)
    end
  end

  describe "ExSolana.Program.PumpFun account decoding" do
    test "correctly decodes a 'BondingCurve' account" do
      # From pump-fun.json IDL:
      # "name": "bondingCurve", "discriminator": [23, 183, 248, 55, 96, 216, 172, 96]
      discriminator = <<23, 183, 248, 55, 96, 216, 172, 96>>
      virtual_token_reserves = 1000
      virtual_sol_reserves = 2000
      real_token_reserves = 3000
      real_sol_reserves = 4000
      token_total_supply = 5000
      complete = true
      creator_pubkey_binary = :crypto.strong_rand_bytes(32)
      creator_pubkey_string = B58.encode58(creator_pubkey_binary)

      # Construct the binary data for the account
      # boolean true
      account_data =
        discriminator <>
          <<virtual_token_reserves::little-unsigned-integer-size(64)>> <>
          <<virtual_sol_reserves::little-unsigned-integer-size(64)>> <>
          <<real_token_reserves::little-unsigned-integer-size(64)>> <>
          <<real_sol_reserves::little-unsigned-integer-size(64)>> <>
          <<token_total_supply::little-unsigned-integer-size(64)>> <>
          <<1::unsigned-integer-size(8)>> <>
          creator_pubkey_binary

      {:ok, {decoded_type, decoded_struct}} = PumpFun.decode_account(account_data)

      assert decoded_type == :bonding_curve
      assert decoded_struct.virtual_token_reserves == virtual_token_reserves
      assert decoded_struct.virtual_sol_reserves == virtual_sol_reserves
      assert decoded_struct.real_token_reserves == real_token_reserves
      assert decoded_struct.real_sol_reserves == real_sol_reserves
      assert decoded_struct.token_total_supply == token_total_supply
      assert decoded_struct.complete == complete
      assert decoded_struct.creator == creator_pubkey_string
    end

    test "returns error for unrecognized account data" do
      invalid_data = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      assert {:error, :invalid_account_data} = PumpFun.decode_account(invalid_data)
    end
  end
end
