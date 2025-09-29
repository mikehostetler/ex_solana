alias ExSolana.TestValidator

# Automatic pump.fun program binary management
defmodule TestHelper.PumpProgram do
  @pump_program_id "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"
  @pump_program_path Path.join(["priv", "programs", "pump.so"])
  @pump_program_keypair_path Path.join(["priv", "programs", "pump-keypair.json"])

  def ensure_program_available do
    cond do
      File.exists?(@pump_program_path) and File.exists?(@pump_program_keypair_path) ->
        IO.puts("✓ pump.fun program binary found - full integration testing enabled")
        true

      should_download_automatically?() ->
        IO.puts("⬇ Downloading pump.fun program binary for testing...")
        download_program()

      true ->
        IO.puts("""

        Note: pump.fun program binary not found - integration tests will use unit testing only.

        To enable automatic download, set: PUMP_AUTO_DOWNLOAD=true
        Or manually place the program binary at: #{@pump_program_path}
        """)

        false
    end
  end

  defp should_download_automatically? do
    # Auto-download in development unless explicitly disabled
    System.get_env("PUMP_AUTO_DOWNLOAD") == "true" or
      System.get_env("CI") == "true" or
      System.get_env("PUMP_NO_AUTO_DOWNLOAD") != "true"
  end

  defp download_program do
    # Ensure directory exists
    Path.dirname(@pump_program_path) |> File.mkdir_p()

    case download_with_solana_cli() do
      :ok ->
        create_dummy_keypair()
        IO.puts("✓ Successfully downloaded pump.fun program binary")
        true

      :error ->
        IO.puts("⚠ Failed to download program binary - continuing with unit tests only")
        false
    end
  end

  defp download_with_solana_cli do
    case System.cmd(
           "solana",
           [
             "program",
             "dump",
             @pump_program_id,
             @pump_program_path,
             "--url",
             "mainnet-beta"
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {output, _} ->
        IO.puts("Solana CLI error: #{output}")
        :error
    end
  rescue
    _ ->
      IO.puts("Solana CLI not found - skipping automatic download")
      :error
  end

  defp create_dummy_keypair do
    # Create a dummy keypair file (not used in testing but required by test validator)
    # Dummy keypair data
    dummy_keypair = List.duplicate(0, 64)

    @pump_program_keypair_path
    |> File.write!(Jason.encode!(dummy_keypair))
  end

  def get_program_path, do: @pump_program_path
  def program_id, do: @pump_program_id

  def program_available?,
    do: File.exists?(@pump_program_path) and File.exists?(@pump_program_keypair_path)
end

# Attempt to ensure pump.fun program is available
pump_available = TestHelper.PumpProgram.ensure_program_available()

extra_programs =
  if pump_available do
    [["priv", "programs", "pump"]]
  else
    []
  end

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
        so_file_path = Enum.reverse([name <> ".so" | rest])

        # For pump.fun program, use the known program ID instead of reading from keypair
        id =
          if name == "pump" do
            TestHelper.PumpProgram.program_id()
          else
            ["deps" | keypair_file_path]
            |> Path.join()
            |> Path.expand()
            |> ExSolana.Key.pair_from_file()
            |> elem(1)
            |> ExSolana.pubkey!()
          end

        Enum.join([id, Path.expand(Path.join(so_file_path))], " ")
    end)
]

{:ok, validator} = TestValidator.start_link(opts)
ExUnit.after_suite(fn _ -> TestValidator.stop(validator) end)
ExUnit.start()
