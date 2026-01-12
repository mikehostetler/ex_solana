defmodule ExSolana.SPL.Token.MintTest do
  use ExUnit.Case, async: true

  import ExSolana.TestHelpers, only: [create_payer: 3]

  alias ExSolana.RPC
  alias ExSolana.SPL.Token
  alias ExSolana.Transaction

  @moduletag :solana
  setup_all do
    client = RPC.client(network: "localhost")
    tracker = ExSolana.tracker(client: client, t: 100)
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    [tracker: tracker, client: client, payer: payer]
  end

  describe "init/1" do
    test "initializes a new mint, with and without a freeze_authority", global do
      new = ExSolana.keypair()
      freeze = ExSolana.keypair()
      {_, auth_pk} = ExSolana.keypair()
      opts = [commitment: "confirmed"]
      space = Token.Mint.byte_size()

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(space, opts),
        RPC.Request.get_latest_blockhash(opts)
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(global.client, tx_reqs)

      tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: lamports,
            payer: ExSolana.pubkey!(global.payer),
            authority: auth_pk,
            new: ExSolana.pubkey!(new),
            decimals: 0
          ),
          Token.Mint.init(
            balance: lamports,
            payer: ExSolana.pubkey!(global.payer),
            authority: auth_pk,
            freeze_authority: auth_pk,
            new: ExSolana.pubkey!(freeze),
            decimals: 0
          )
        ],
        signers: [global.payer, new, freeze],
        blockhash: blockhash,
        payer: ExSolana.pubkey!(global.payer)
      }

      opts = [commitment: "confirmed", timeout: 5_000]
      {:ok, _signatures} = RPC.send_and_confirm(global.client, global.tracker, tx, opts)
      opts = [commitment: "confirmed", encoding: "jsonParsed"]

      assert {:ok, mint} =
               RPC.send(global.client, RPC.Request.get_account_info(ExSolana.pubkey!(new), opts))

      assert %Token.Mint{
               decimals: 0,
               authority: ^auth_pk,
               initialized?: true,
               freeze_authority: nil,
               supply: 0
             } = Token.Mint.from_account_info(mint)

      assert {:ok, freeze_mint} =
               RPC.send(
                 global.client,
                 RPC.Request.get_account_info(ExSolana.pubkey!(freeze), opts)
               )

      assert %Token.Mint{
               decimals: 0,
               authority: ^auth_pk,
               initialized?: true,
               freeze_authority: ^auth_pk,
               supply: 0
             } = Token.Mint.from_account_info(freeze_mint)
    end
  end
end
