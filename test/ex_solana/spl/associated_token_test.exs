defmodule ExSolana.SPL.AssociatedTokenTest do
  use ExUnit.Case, async: true

  import ExSolana, only: [pubkey!: 1]
  import ExSolana.TestHelpers, only: [create_payer: 3, keypairs: 1]

  alias ExSolana.RPC
  alias ExSolana.SPL.AssociatedToken
  alias ExSolana.SPL.Token
  alias ExSolana.Transaction

  @moduletag :solana
  setup_all do
    client = RPC.client(network: "localhost")
    tracker = ExSolana.tracker(client: client, t: 100)
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    [tracker: tracker, client: client, payer: payer]
  end

  describe "find_address/2" do
    test "fails if the owner is invalid" do
      assert :error =
               AssociatedToken.find_address(
                 ExSolana.pubkey!("7o36UsWR1JQLpZ9PE2gn9L4SQ69CNNiWAXd4Jt7rqz9Z"),
                 ExSolana.pubkey!("DShWnroshVbeUp28oopA3Pu7oFPDBtC1DBmPECXXAQ9n")
               )
    end

    test "finds the associated token address for a given owner and mint" do
      expected = ExSolana.pubkey!("DShWnroshVbeUp28oopA3Pu7oFPDBtC1DBmPECXXAQ9n")

      assert {:ok, ^expected} =
               AssociatedToken.find_address(
                 ExSolana.pubkey!("7o36UsWR1JQLpZ9PE2gn9L4SQ69CNNiWAXd4Jt7rqz9Z"),
                 ExSolana.pubkey!("B8UwBUUnKwCyKuGMbFKWaG7exYdDk2ozZrPg72NyVbfj")
               )
    end
  end

  describe "create_account/1" do
    test "creates an associated token account", %{client: client, tracker: tracker, payer: payer} do
      [mint, auth, owner] = keypairs(3)

      {:ok, associated_token} = AssociatedToken.find_address(pubkey!(mint), pubkey!(owner))

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, balance}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: balance,
            payer: pubkey!(payer),
            authority: pubkey!(auth),
            new: pubkey!(mint),
            decimals: 0
          ),
          AssociatedToken.create_account(
            payer: pubkey!(payer),
            owner: pubkey!(owner),
            new: associated_token,
            mint: pubkey!(mint)
          )
        ],
        signers: [payer, mint],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx,
          commitment: "confirmed",
          timeout: 5_000
        )

      assert {:ok, associated_token_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(associated_token,
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )

      assert %Token{
               owner: pubkey!(owner),
               mint: pubkey!(mint),
               initialized?: true,
               frozen?: false,
               native?: false,
               amount: 0
             } == Token.from_account_info(associated_token_info)
    end
  end
end
