defmodule ExSolana.Program.JupiterSwap do
  @moduledoc false
  use ExSolana.ProgramBehaviour,
    idl_path: "priv/idl/jupiter.json",
    program_id: "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4"
end
