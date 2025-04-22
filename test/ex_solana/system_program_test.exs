defmodule ExSolana.Native.SystemProgramTest do
  use ExUnit.Case, async: true

  import ExSolana, only: [pubkey!: 1]
  import ExSolana.TestHelpers, only: [create_payer: 3]

  alias ExSolana.Native.SystemProgram
  alias ExSolana.RPC
  alias ExSolana.Transaction

  @moduletag :solana
  setup_all do
    client = RPC.client(network: "localhost")
    tracker = ExSolana.tracker(client: client, t: 100)
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed", amount: 1000)

    [tracker: tracker, client: client, payer: payer]
  end

  describe "create_account/1" do
    test "can create account", %{tracker: tracker, client: client, payer: payer} do
      new = ExSolana.keypair()

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(0, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new)
          )
        ],
        signers: [payer, new],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      assert {:ok, %{"lamports" => ^lamports}} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(new), commitment: "confirmed")
               )
    end

    test "can create an account with a seed", %{tracker: tracker, client: client, payer: payer} do
      {:ok, new} = ExSolana.Key.with_seed(pubkey!(payer), "create", SystemProgram.id())

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(0, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: new,
            base: pubkey!(payer),
            seed: "create"
          )
        ],
        signers: [payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      assert {:ok, %{"lamports" => ^lamports}} =
               RPC.send(client, RPC.Request.get_account_info(new, commitment: "confirmed"))
    end
  end

  describe "transfer/1" do
    test "can transfer lamports to an account", %{tracker: tracker, client: client, payer: payer} do
      new = ExSolana.keypair()
      space = 0

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(space, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: space,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new)
          ),
          SystemProgram.transfer(
            lamports: 1_000,
            from: pubkey!(payer),
            to: pubkey!(new)
          )
        ],
        signers: [payer, new],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      expected = 1000 + lamports

      assert {:ok, %{"lamports" => ^expected}} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(new),
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )
    end

    test "can transfer lamports to an account with a seed", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      {:ok, new} = ExSolana.Key.with_seed(pubkey!(payer), "transfer", SystemProgram.id())
      space = 0

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(space, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: 1_000 + lamports,
            space: space,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: new,
            base: pubkey!(payer),
            seed: "transfer"
          ),
          SystemProgram.transfer(
            lamports: 1_000,
            from: new,
            to: pubkey!(payer),
            base: pubkey!(payer),
            seed: "transfer",
            program_id: SystemProgram.id()
          )
        ],
        signers: [payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      assert {:ok, %{"lamports" => ^lamports}} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(new,
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )
    end
  end

  describe "batch_transfer/1" do
    test "can perform multiple transfers in a single transaction", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      new1 = ExSolana.keypair()
      new2 = ExSolana.keypair()
      transfer_amount = 1_000

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(0, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      # Create accounts
      create_accounts_tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new1)
          ),
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new2)
          )
        ],
        signers: [payer, new1, new2],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _} =
        RPC.send_and_confirm(client, tracker, create_accounts_tx,
          commitment: "confirmed",
          timeout: 5_000
        )

      # Perform batch transfer
      {:ok, %{"blockhash" => new_blockhash}} =
        RPC.send(client, RPC.Request.get_latest_blockhash(commitment: "confirmed"))

      {:ok, [transfer_instructions]} =
        SystemProgram.batch_transfer(
          transfers: [
            {pubkey!(payer), pubkey!(new1), transfer_amount},
            {pubkey!(payer), pubkey!(new2), transfer_amount}
          ]
        )

      transfer_tx = %Transaction{
        instructions: transfer_instructions,
        signers: [payer],
        blockhash: new_blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _} =
        RPC.send_and_confirm(client, tracker, transfer_tx,
          commitment: "confirmed",
          timeout: 5_000
        )

      # Verify transfers
      {:ok, %{"lamports" => balance1}} =
        RPC.send(client, RPC.Request.get_account_info(pubkey!(new1), commitment: "confirmed"))

      {:ok, %{"lamports" => balance2}} =
        RPC.send(client, RPC.Request.get_account_info(pubkey!(new2), commitment: "confirmed"))

      assert balance1 == lamports + transfer_amount
      assert balance2 == lamports + transfer_amount
    end

    test "respects max_instructions_per_transaction limit", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      new1 = ExSolana.keypair()
      new2 = ExSolana.keypair()
      new3 = ExSolana.keypair()
      transfer_amount = 1_000

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(0, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      # Create accounts
      create_accounts_tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new1)
          ),
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new2)
          ),
          SystemProgram.create_account(
            lamports: lamports,
            space: 0,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new3)
          )
        ],
        signers: [payer, new1, new2, new3],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _} =
        RPC.send_and_confirm(client, tracker, create_accounts_tx,
          commitment: "confirmed",
          timeout: 5_000
        )

      # Perform batch transfer with max_instructions_per_transaction set to 2
      {:ok, %{"blockhash" => new_blockhash}} =
        RPC.send(client, RPC.Request.get_latest_blockhash(commitment: "confirmed"))

      {:ok, [transfer_instructions1, transfer_instructions2]} =
        SystemProgram.batch_transfer(
          transfers: [
            {pubkey!(payer), pubkey!(new1), transfer_amount},
            {pubkey!(payer), pubkey!(new2), transfer_amount},
            {pubkey!(payer), pubkey!(new3), transfer_amount}
          ],
          max_instructions_per_transaction: 2
        )

      assert length(transfer_instructions1) == 2
      assert length(transfer_instructions2) == 1

      transfer_tx1 = %Transaction{
        instructions: transfer_instructions1,
        signers: [payer],
        blockhash: new_blockhash,
        payer: pubkey!(payer)
      }

      transfer_tx2 = %Transaction{
        instructions: transfer_instructions2,
        signers: [payer],
        blockhash: new_blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _} =
        RPC.send_and_confirm(client, tracker, transfer_tx1,
          commitment: "confirmed",
          timeout: 5_000
        )

      {:ok, _} =
        RPC.send_and_confirm(client, tracker, transfer_tx2,
          commitment: "confirmed",
          timeout: 5_000
        )

      # Verify transfers
      {:ok, %{"lamports" => balance1}} =
        RPC.send(client, RPC.Request.get_account_info(pubkey!(new1), commitment: "confirmed"))

      {:ok, %{"lamports" => balance2}} =
        RPC.send(client, RPC.Request.get_account_info(pubkey!(new2), commitment: "confirmed"))

      {:ok, %{"lamports" => balance3}} =
        RPC.send(client, RPC.Request.get_account_info(pubkey!(new3), commitment: "confirmed"))

      assert balance1 == lamports + transfer_amount
      assert balance2 == lamports + transfer_amount
      assert balance3 == lamports + transfer_amount
    end

    test "can perform 15 transfers in multiple transactions", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      num_transfers = 15
      transfer_amount = 1_000
      max_instructions_per_transaction = 5

      # Create 15 new accounts
      new_accounts = Enum.map(1..num_transfers, fn _ -> ExSolana.keypair() end)

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(0, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      # Create accounts one by one
      Enum.each(new_accounts, fn new_account ->
        create_account_tx = %Transaction{
          instructions: [
            SystemProgram.create_account(
              lamports: lamports,
              space: 0,
              program_id: SystemProgram.id(),
              from: pubkey!(payer),
              new: pubkey!(new_account)
            )
          ],
          signers: [payer, new_account],
          blockhash: blockhash,
          payer: pubkey!(payer)
        }

        {:ok, _} =
          RPC.send_and_confirm(client, tracker, create_account_tx,
            commitment: "confirmed",
            timeout: 5_000
          )
      end)

      # Prepare batch transfer
      {:ok, %{"blockhash" => new_blockhash}} =
        RPC.send(client, RPC.Request.get_latest_blockhash(commitment: "confirmed"))

      transfers =
        Enum.map(new_accounts, fn new_account ->
          {pubkey!(payer), pubkey!(new_account), transfer_amount}
        end)

      {:ok, chunked_instructions} =
        SystemProgram.batch_transfer(
          transfers: transfers,
          max_instructions_per_transaction: max_instructions_per_transaction
        )

      # Create and send transfer transactions
      transfer_txs =
        Enum.map(chunked_instructions, fn instructions ->
          %Transaction{
            instructions: instructions,
            signers: [payer],
            blockhash: new_blockhash,
            payer: pubkey!(payer)
          }
        end)

      Enum.each(transfer_txs, fn tx ->
        {:ok, _} =
          RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)
      end)

      # Verify transfers
      Enum.each(new_accounts, fn new_account ->
        {:ok, %{"lamports" => balance}} =
          RPC.send(
            client,
            RPC.Request.get_account_info(pubkey!(new_account), commitment: "confirmed")
          )

        assert balance == lamports + transfer_amount
      end)

      # Verify the number of transactions created
      expected_num_transactions = ceil(num_transfers / max_instructions_per_transaction)
      assert length(transfer_txs) == expected_num_transactions
    end
  end

  describe "assign/1" do
    test "can assign a new program ID to an account", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      new = ExSolana.keypair()
      space = 0
      new_program_id = pubkey!("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(space, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: space,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new)
          ),
          SystemProgram.assign(
            account: pubkey!(new),
            program_id: new_program_id
          )
        ],
        signers: [payer, new],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      {:ok, account_info} =
        RPC.send(
          client,
          RPC.Request.get_account_info(pubkey!(new),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      assert account_info["owner"] == new_program_id
    end

    test "can assign a new program ID to an account with a seed", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      new_program_id = pubkey!("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
      {:ok, new} = ExSolana.Key.with_seed(pubkey!(payer), "assign", new_program_id)
      space = 0

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(space, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: space,
            program_id: new_program_id,
            from: pubkey!(payer),
            new: new,
            base: pubkey!(payer),
            seed: "assign"
          ),
          SystemProgram.assign(
            account: new,
            program_id: new_program_id,
            base: pubkey!(payer),
            seed: "assign"
          )
        ],
        signers: [payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      {:ok, account_info} =
        RPC.send(
          client,
          RPC.Request.get_account_info(new,
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      assert account_info["owner"] == new_program_id
    end
  end

  describe "allocate/1" do
    test "can allocate space to an account", %{tracker: tracker, client: client, payer: payer} do
      new = ExSolana.keypair()
      space = 0
      new_space = 10

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(new_space, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: space,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: pubkey!(new)
          ),
          SystemProgram.allocate(
            account: pubkey!(new),
            space: new_space
          )
        ],
        signers: [payer, new],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      {:ok, %{"data" => [data, "base64"]}} =
        RPC.send(
          client,
          RPC.Request.get_account_info(pubkey!(new),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      assert byte_size(Base.decode64!(data)) == new_space
    end

    test "can allocate space to an account with a seed", %{
      tracker: tracker,
      client: client,
      payer: payer
    } do
      {:ok, new} = ExSolana.Key.with_seed(pubkey!(payer), "allocate", SystemProgram.id())
      space = 0
      new_space = 10

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(new_space, commitment: "confirmed"),
        RPC.Request.get_latest_blockhash(commitment: "confirmed")
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(client, tx_reqs)

      tx = %Transaction{
        instructions: [
          SystemProgram.create_account(
            lamports: lamports,
            space: space,
            program_id: SystemProgram.id(),
            from: pubkey!(payer),
            new: new,
            base: pubkey!(payer),
            seed: "allocate"
          ),
          SystemProgram.allocate(
            account: new,
            space: new_space,
            program_id: SystemProgram.id(),
            base: pubkey!(payer),
            seed: "allocate"
          )
        ],
        signers: [payer],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, tx, commitment: "confirmed", timeout: 5_000)

      {:ok, %{"data" => [data, "base64"]}} =
        RPC.send(
          client,
          RPC.Request.get_account_info(new,
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        )

      assert byte_size(Base.decode64!(data)) == new_space
    end
  end
end
