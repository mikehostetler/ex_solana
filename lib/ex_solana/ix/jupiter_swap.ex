defmodule ExSolana.Ix.JupiterSwap do
  @moduledoc false
  alias ExSolana.Account
  alias ExSolana.Instruction
  alias ExSolana.Jup
  alias ExSolana.RPC
  alias ExSolana.RPC.Request
  alias ExSolana.Transaction.Builder

  # alias ExSolana.Transaction
  require IEx

  @doc """
  Integrates a Jupiter swap transaction into the builder.

  ## Parameters

  - `builder`: The current transaction builder
  - `swap_response`: The response from Jupiter's swap endpoint
  - `signer`: The keypair of the signer (usually the user's wallet)

  ## Returns

  Updated transaction builder with the swap transaction integrated.
  """
  def jupiter_swap(builder \\ Builder.new(), from_mint, to_mint, amount, slippage_bps, opts) do
    jup_client = Jup.client()

    {:ok, quote_response} = Jup.quote(jup_client, from_mint, to_mint, amount, slippage_bps)

    {:ok, swap_response} =
      Jup.swap_instructions(jup_client, quote_response, B58.encode58(builder.payer))

    address_lookups = Map.get(swap_response, "addressLookupTableAddresses", [])

    client = ExSolana.rpc_client()
    infos = RPC.send(client, Request.get_multiple_accounts(address_lookups))
    IEx.pry()

    compute_budget_instructions =
      swap_response
      |> Map.get("computeBudgetInstructions", [])
      |> Enum.map(&parse_instruction/1)

    setup_instructions =
      swap_response
      |> Map.get("setupInstructions", [])
      |> Enum.map(&parse_instruction/1)

    swap_instruction =
      swap_response
      |> Map.get("swapInstruction")
      |> parse_instruction()

    cleanup_instruction =
      swap_response
      |> Map.get("cleanupInstruction")
      |> parse_instruction()

    builder
    |> Builder.add_instructions(compute_budget_instructions)
    |> Builder.add_instructions(setup_instructions)
    |> Builder.add_instruction(swap_instruction)
    |> Builder.add_instruction(cleanup_instruction)
    |> Builder.add_address_lookup_tables(address_lookups)

    # address_lookup_table = Map.get(swap_response, "addressLookupTableAddresses", [])

    # builder
    # |> Builder.add_instruction(compute_budget_instruction)
    # |> Builder.add_instructions(swap_instructions)
    # |> Builder.add_signer(signer)

    # case decode_and_deserialize_swap_transaction(swap_response) do
    #   {:ok, instructions} ->
    #     builder
    #     |> add_instructions(instructions)
    #     |> add_signer(signer)

    #   {:error, reason} ->
    #     Logger.warning("Failed to decode Jupiter swap transaction: #{inspect(reason)}")
    #     builder
    # end
  end

  defp parse_instruction(instruction) do
    %Instruction{
      program: instruction["programId"],
      accounts:
        Enum.map(instruction["accounts"], fn account ->
          %Account{
            key: account["pubkey"],
            signer?: account["isSigner"],
            writable?: account["isWritable"]
          }
        end),
      data: instruction["data"]
    }
  end

  # defp decode_and_deserialize_swap_transaction(swap_response) do
  #   with {:ok, swap_transaction} <- Map.fetch(swap_response, "swapTransaction"),
  #        {:ok, decoded} <- Base.decode64(swap_transaction),
  #        {:ok, tx} <- ExSolana.Transaction.from_binary(decoded) do
  #     {:ok, tx.instructions}
  #   else
  #     :error -> {:error, "Missing swapTransaction in response"}
  #     {:error, reason} -> {:error, reason}
  #   end
  # end

  # defp add_instructions(builder, instructions) do
  #   Enum.reduce(instructions, builder, fn instruction, acc ->
  #     add_raw_instruction(acc, instruction)
  #   end)
  # end
end
