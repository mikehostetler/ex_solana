defmodule CodeMapper.FolderAgent do
  @moduledoc """
  Agent that manages analysis of files within a directory.
  Uses MapperStrategy for signal handling.
  """

  use Jido.Agent,
    name: "folder_agent",
    strategy: CodeMapper.Strategy.MapperStrategy,
    schema: [
      folder_path: [type: :string, default: ""],
      files: [type: {:list, :string}, default: []],
      pending_files: [type: {:list, :string}, default: []],
      file_results: [type: {:list, :map}, default: []],
      file_children: [type: :map, default: %{}],
      status: [type: :atom, default: :idle]
    ]
end
