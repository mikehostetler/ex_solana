alias ExSolana.TestValidator

extra_programs = [
  # {ExSolana.SPL.TokenSwap, ["solana-program-library", "target", "deploy", "spl_token_swap.so"]}
  # ["solana-program-library", "target", "deploy", "spl_governance"]
  # {ExSolana.Raydium.AMM, ["priv", "programs", "raydium_amm.so"]}
  # ["raydium-amm", "priv", "programs", "raydium_amm.so"]
]

# extra_programs = []

opts = [
  ledger: "/tmp/test-ledger",
  bpf_program:
    Enum.map(extra_programs, fn
      {mod, path} ->
        # [B58.encode58(mod.id()), Path.expand(Path.join(["deps" | path]))]
        Enum.join([B58.encode58(mod.id()), Path.expand(Path.join(path))], " ")

      path ->
        [name | rest] = Enum.reverse(path)
        keypair_file_path = Enum.reverse([name <> "-keypair.json" | rest])

        id =
          ["deps" | keypair_file_path]
          |> Path.join()
          |> Path.expand()
          |> ExSolana.Key.pair_from_file()
          |> elem(1)
          |> ExSolana.pubkey!()

        path = Enum.reverse([name <> ".so" | rest])

        Enum.join([B58.encode58(id), Path.expand(Path.join(["deps" | path]))], " ")
    end)
]

{:ok, validator} = TestValidator.start_link(opts)
ExUnit.after_suite(fn _ -> TestValidator.stop(validator) end)
ExUnit.start()
