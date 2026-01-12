# lib/ex_solana/programs/pump_fun.ex
defmodule ExSolana.Program.PumpFun do
  use ExSolana.ProgramBehaviour,
    idl_path: "priv/idl/pump_fun.json",
    program_id: "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"

  # The macro will automatically generate:
  # - decode_ix/1 for all instructions in the IDL.
  # - decode_account/1 for all accounts (`BondingCurve`, `Global`, etc.).
  # - decode_events/1 for all events (`CreateEvent`, `TradeEvent`, etc.).
  # - analyze_ix/2 stubs to be implemented.
end
