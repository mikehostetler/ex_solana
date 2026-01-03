defmodule CodeMapper.FileAgent do
  @moduledoc """
  Agent that analyzes a single source file.
  Uses MapperStrategy for signal handling.
  """

  use Jido.Agent,
    name: "file_agent",
    strategy: CodeMapper.Strategy.MapperStrategy,
    schema: [
      path: [type: :string, default: ""],
      status: [type: :atom, default: :idle],
      file_result: [type: :map, default: %{}]
    ]
end
