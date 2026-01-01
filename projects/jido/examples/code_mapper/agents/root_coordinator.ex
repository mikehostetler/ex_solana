defmodule CodeMapper.RootCoordinator do
  @moduledoc """
  Root coordinator agent that orchestrates codebase mapping.
  Uses MapperStrategy for signal handling.
  """

  use Jido.Agent,
    name: "root_coordinator",
    strategy: CodeMapper.Strategy.MapperStrategy,
    schema: [
      root_path: [type: :string, default: ""],
      status: [type: :atom, default: :idle],
      all_files: [type: {:list, :string}, default: []],
      folders: [type: :map, default: %{}],
      folder_children: [type: :map, default: %{}],
      pending_folders: [type: {:list, :string}, default: []],
      folder_results: [type: {:list, :map}, default: []],
      report: [type: :string, default: ""],
      stats: [type: :map, default: %{}]
    ]
end
