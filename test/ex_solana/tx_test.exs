defmodule ExSolana.TransactionTest do
  use ExUnit.Case, async: true

  import ExSolana, only: [pubkey!: 1]
  import ExUnit.CaptureLog

  alias ExSolana.Account
  alias ExSolana.Instruction
  alias ExSolana.Transaction

  describe "to_binary/1" do
    test "fails if there's no blockhash" do
      payer = ExSolana.keypair()
      program = pubkey!(ExSolana.keypair())

      ix = %Instruction{
        program: program,
        accounts: [
          %Account{signer?: true, writable?: true, key: pubkey!(payer)}
        ]
      }

      tx = %Transaction{payer: pubkey!(payer), instructions: [ix], signers: [payer]}
      assert Transaction.to_binary(tx) == {:error, :no_blockhash}
    end

    test "fails if there's no payer" do
      blockhash = pubkey!(ExSolana.keypair())
      program = pubkey!(ExSolana.keypair())

      ix = %Instruction{
        program: program,
        accounts: [
          %Account{key: blockhash}
        ]
      }

      tx = %Transaction{instructions: [ix], blockhash: blockhash}
      assert Transaction.to_binary(tx) == {:error, :no_payer}
    end

    test "fails if there's no instructions" do
      payer = ExSolana.keypair()
      blockhash = pubkey!(ExSolana.keypair())
      tx = %Transaction{payer: pubkey!(payer), blockhash: blockhash}
      assert Transaction.to_binary(tx) == {:error, :no_instructions}
    end

    test "fails if an instruction doesn't have a program" do
      blockhash = pubkey!(ExSolana.keypair())
      payer = ExSolana.keypair()

      ix = %Instruction{
        accounts: [
          %Account{key: pubkey!(payer), writable?: true, signer?: true}
        ]
      }

      tx = %Transaction{
        payer: pubkey!(payer),
        instructions: [ix],
        blockhash: blockhash,
        signers: [payer]
      }

      assert capture_log(fn -> Transaction.to_binary(tx) end) =~ "index 0"
    end

    test "fails if a signer is missing or if there's unnecessary signers" do
      blockhash = pubkey!(ExSolana.keypair())
      program = pubkey!(ExSolana.keypair())
      payer = ExSolana.keypair()
      signer = ExSolana.keypair()

      ix = %Instruction{
        program: program,
        accounts: [
          %Account{key: pubkey!(payer), writable?: true, signer?: true}
        ]
      }

      tx = %Transaction{payer: pubkey!(payer), instructions: [ix], blockhash: blockhash}
      assert Transaction.to_binary(tx) == {:error, :mismatched_signers}

      assert Transaction.to_binary(%{tx | signers: [payer, signer]}) ==
               {:error, :mismatched_signers}
    end

    # test "places accounts in order (payer first)" do
    #   payer = ExSolana.keypair()
    #   signer = ExSolana.keypair()
    #   read_only = ExSolana.keypair()
    #   program = pubkey!(ExSolana.keypair())
    #   blockhash = pubkey!(ExSolana.keypair())

    #   ix = %Instruction{
    #     program: program,
    #     accounts: [
    #       %Account{signer?: true, key: pubkey!(read_only)},
    #       %Account{signer?: true, writable?: true, key: pubkey!(signer)},
    #       %Account{signer?: true, writable?: true, key: pubkey!(payer)}
    #     ]
    #   }

    #   tx = %Transaction{
    #     payer: pubkey!(payer),
    #     instructions: [ix],
    #     blockhash: blockhash,
    #     signers: [payer, signer, read_only]
    #   }

    #   {:ok, tx_bin} = Transaction.to_binary(tx)
    #   {_, extras} = Transaction.parse(tx_bin)

    #   IO.inspect(extras)

    #   assert [pubkey!(payer), pubkey!(signer), pubkey!(read_only)] ==
    #            extras
    #            |> Keyword.get(:accounts)
    #            |> Enum.map(& &1.key)
    #            |> Enum.take(3)
    # end

    #   test "payer is writable and a signer" do
    #     payer = ExSolana.keypair()
    #     read_only = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [%Account{key: pubkey!(payer)}, %Account{key: pubkey!(read_only)}]
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: [ix],
    #       blockhash: blockhash,
    #       signers: [payer]
    #     }

    #     {:ok, tx_bin} = Transaction.to_binary(tx)
    #     {_, extras} = Transaction.parse(tx_bin)

    #     [actual_payer | _] = Keyword.get(extras, :accounts)

    #     assert actual_payer.key == pubkey!(payer)
    #     assert actual_payer.writable?
    #     assert actual_payer.signer?
    #   end

    #   test "sets up the header correctly" do
    #     payer = ExSolana.keypair()
    #     writable = ExSolana.keypair()
    #     signer = ExSolana.keypair()
    #     read_only = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{key: pubkey!(read_only)},
    #         %Account{writable?: true, key: pubkey!(writable)},
    #         %Account{signer?: true, key: pubkey!(signer)},
    #         %Account{signer?: true, writable?: true, key: pubkey!(payer)}
    #       ]
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: [ix],
    #       blockhash: blockhash,
    #       signers: [payer, signer]
    #     }

    #     {:ok, tx_bin} = Transaction.to_binary(tx)
    #     {_, extras} = Transaction.parse(tx_bin)

    #     # 2 signers, one read-only signer, 2 read-only non-signers (read_only and
    #     # program)
    #     assert Keyword.get(extras, :header) == <<2, 1, 2>>
    #   end

    #   test "dedups signatures and accounts" do
    #     from = ExSolana.keypair()
    #     to = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{key: pubkey!(to)},
    #         %Account{signer?: true, writable?: true, key: pubkey!(from)}
    #       ]
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(from),
    #       instructions: [ix, ix],
    #       blockhash: blockhash,
    #       signers: [from]
    #     }

    #     {:ok, tx_bin} = Transaction.to_binary(tx)
    #     {_, extras} = Transaction.parse(tx_bin)

    #     assert [_] = Keyword.get(extras, :signatures)
    #     assert length(Keyword.get(extras, :accounts)) == 3
    #   end
    # end

    # describe "parse/1" do
    #   test "cannot parse an empty string" do
    #     assert :error = Transaction.parse("")
    #   end

    #   test "cannot parse an improperly encoded transaction" do
    #     payer = ExSolana.keypair()
    #     signer = ExSolana.keypair()
    #     read_only = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{signer?: true, key: pubkey!(read_only)},
    #         %Account{signer?: true, writable?: true, key: pubkey!(signer)},
    #         %Account{signer?: true, writable?: true, key: pubkey!(payer)}
    #       ]
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: [ix],
    #       blockhash: blockhash,
    #       signers: [payer, signer, read_only]
    #     }

    #     {:ok, <<_::8, clipped_tx::binary>>} = Transaction.to_binary(tx)
    #     assert :error = Transaction.parse(clipped_tx)
    #   end

    #   test "can parse a properly encoded tranaction" do
    #     from = ExSolana.keypair()
    #     to = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{key: pubkey!(to)},
    #         %Account{signer?: true, writable?: true, key: pubkey!(from)}
    #       ],
    #       data: <<1, 2, 3>>
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(from),
    #       instructions: [ix, ix],
    #       blockhash: blockhash,
    #       signers: [from]
    #     }

    #     {:ok, tx_bin} = Transaction.to_binary(tx)
    #     {actual, extras} = Transaction.parse(tx_bin)

    #     assert [_signature] = Keyword.get(extras, :signatures)

    #     assert actual.payer == pubkey!(from)
    #     assert actual.instructions == [ix, ix]
    #     assert actual.blockhash == blockhash
    #   end
    # end

    # describe "decode/1" do
    #   test "fails for signatures which are too short" do
    #     encoded = B58.encode58(Enum.into(1..63, <<>>, &<<&1::8>>))
    #     assert {:error, _} = Transaction.decode(encoded)
    #     assert {:error, _} = Transaction.decode("12345")
    #   end

    #   test "fails for signatures which are too long" do
    #     encoded = B58.encode58(<<3, 0::64*8>>)
    #     assert {:error, _} = Transaction.decode(encoded)
    #   end

    #   test "fails for signatures which aren't base58-encoded" do
    #     assert {:error, _} =
    #              Transaction.decode(
    #                "0x300000000000000000000000000000000000000000000000000000000000000000000"
    #              )

    #     assert {:error, _} =
    #              Transaction.decode(
    #                "0x300000000000000000000000000000000000000000000000000000000000000"
    #              )

    #     assert {:error, _} =
    #              Transaction.decode(
    #                "135693854574979916511997248057056142015550763280047535983739356259273198796800000"
    #              )
    #   end

    #   test "works for regular signatures" do
    #     assert {:ok, <<3, 0::63*8>>} =
    #              Transaction.decode(
    #                "4Umk1E47BhUNBHJQGJto6i5xpATqVs8UxW11QjpoVnBmiv7aZJyG78yVYj99SrozRa9x7av8p3GJmBuzvhpUHDZ"
    #              )
    #   end
    # end

    # describe "decode!/1" do
    #   test "throws for signatures which aren't base58-encoded" do
    #     assert_raise ArgumentError, fn ->
    #       Transaction.decode!(
    #         "0x300000000000000000000000000000000000000000000000000000000000000000000"
    #       )
    #     end

    #     assert_raise ArgumentError, fn ->
    #       Transaction.decode!("0x300000000000000000000000000000000000000000000000000000000000000")
    #     end

    #     assert_raise ArgumentError, fn ->
    #       Transaction.decode!(
    #         "135693854574979916511997248057056142015550763280047535983739356259273198796800000"
    #       )
    #     end
    #   end

    #   test "works for regular signatures" do
    #     assert <<3, 0::63*8>> ==
    #              Transaction.decode!(
    #                "4Umk1E47BhUNBHJQGJto6i5xpATqVs8UxW11QjpoVnBmiv7aZJyG78yVYj99SrozRa9x7av8p3GJmBuzvhpUHDZ"
    #              )
    #   end
    # end

    # describe "transaction limits" do
    #   test "max_transaction_size/0 returns the correct value" do
    #     assert Transaction.max_transaction_size() == 1232
    #   end

    #   test "max_instructions/0 returns the correct value" do
    #     assert Transaction.max_instructions() == 19
    #   end

    #   test "max_accounts/0 returns the correct value" do
    #     assert Transaction.max_accounts() == 32
    #   end

    #   test "max_signers/0 returns the correct value" do
    #     assert Transaction.max_signers() == 8
    #   end

    #   test "fails when exceeding max instructions" do
    #     payer = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{signer?: true, writable?: true, key: pubkey!(payer)}
    #       ]
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: List.duplicate(ix, Transaction.max_instructions() + 1),
    #       blockhash: blockhash,
    #       signers: [payer]
    #     }

    #     assert {:error, :too_many_instructions} = Transaction.to_binary(tx)
    #   end

    #   test "fails when exceeding max accounts" do
    #     payer = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     accounts =
    #       Enum.map(1..Transaction.max_accounts(), fn _ ->
    #         %Account{key: pubkey!(ExSolana.keypair())}
    #       end)

    #     ix = %Instruction{
    #       program: program,
    #       accounts: accounts
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: [ix],
    #       blockhash: blockhash,
    #       signers: [payer]
    #     }

    #     assert {:error, :too_many_accounts} = Transaction.to_binary(tx)
    #   end

    #   test "fails when exceeding max signers" do
    #     payer = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     signers = Enum.map(1..Transaction.max_signers(), fn _ -> ExSolana.keypair() end)

    #     ix = %Instruction{
    #       program: program,
    #       accounts:
    #         Enum.map(signers, fn signer ->
    #           %Account{signer?: true, writable?: true, key: pubkey!(signer)}
    #         end)
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: [ix],
    #       blockhash: blockhash,
    #       signers: [payer | signers]
    #     }

    #     assert {:error, :too_many_signers} = Transaction.to_binary(tx)
    #   end

    #   test "succeeds when at max limits" do
    #     payer = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{signer?: true, writable?: true, key: pubkey!(payer)}
    #       ]
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       instructions: List.duplicate(ix, Transaction.max_instructions()),
    #       blockhash: blockhash,
    #       signers: [payer]
    #     }

    #     assert {:ok, _binary} = Transaction.to_binary(tx)
    #   end

    #   test "fails when transaction size is too large" do
    #     payer = ExSolana.keypair()
    #     program = pubkey!(ExSolana.keypair())
    #     blockhash = pubkey!(ExSolana.keypair())

    #     # Create multiple instructions with large data payloads
    #     large_data = :crypto.strong_rand_bytes(500)

    #     ix = %Instruction{
    #       program: program,
    #       accounts: [
    #         %Account{signer?: true, writable?: true, key: pubkey!(payer)}
    #       ],
    #       data: large_data
    #     }

    #     tx = %Transaction{
    #       payer: pubkey!(payer),
    #       # Use multiple instructions to exceed the size limit
    #       instructions: List.duplicate(ix, 3),
    #       blockhash: blockhash,
    #       signers: [payer]
    #     }

    #     assert {:error, :transaction_too_large} = Transaction.to_binary(tx)
    #   end
  end
end
