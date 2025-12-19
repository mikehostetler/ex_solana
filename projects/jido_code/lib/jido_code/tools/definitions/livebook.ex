defmodule JidoCode.Tools.Definitions.Livebook do
  @moduledoc """
  Tool definitions for Livebook notebook operations.

  This module defines the tools for manipulating Elixir Livebook notebooks
  (.livemd files) that can be registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `livebook_edit` - Edit, insert, or delete notebook cells

  ## Usage

      # Register all livebook tools
      for tool <- Livebook.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      edit_tool = Livebook.livebook_edit()
      :ok = Registry.register(edit_tool)
  """

  alias JidoCode.Tools.Handlers.Livebook, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all livebook tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      livebook_edit()
    ]
  end

  @doc """
  Returns the livebook_edit tool definition.

  Edits, inserts, or deletes cells in Livebook notebooks (.livemd files).

  ## Parameters

  - `notebook_path` (required, string) - Path to the .livemd file relative to project root
  - `cell_index` (required, integer) - Index of the cell (0-based). For insert, cell is added after this index.
  - `new_source` (required for replace/insert, string) - New content for the cell
  - `cell_type` (optional, string) - Cell type: "elixir", "erlang", "markdown", "heex", "sql"
  - `edit_mode` (optional, string) - Operation: "replace" (default), "insert", or "delete"
  """
  @spec livebook_edit() :: Tool.t()
  def livebook_edit do
    Tool.new!(%{
      name: "livebook_edit",
      description:
        "Edit Elixir Livebook notebook (.livemd) cells. " <>
          "Can replace cell content, insert new cells, or delete cells. " <>
          "Livebook notebooks are interactive Elixir documents with code and markdown cells.",
      handler: Handlers.EditCell,
      parameters: [
        %{
          name: "notebook_path",
          type: :string,
          description: "Path to the .livemd file (relative to project root)",
          required: true
        },
        %{
          name: "cell_index",
          type: :integer,
          description:
            "Index of the cell to edit (0-based). For insert mode, the new cell is inserted after this index. Use -1 to insert at the beginning.",
          required: true
        },
        %{
          name: "new_source",
          type: :string,
          description: "New content for the cell (required for replace/insert modes)",
          required: false
        },
        %{
          name: "cell_type",
          type: :string,
          description:
            "Cell type: 'elixir', 'erlang', 'markdown', 'heex', 'sql'. Defaults to existing type for replace, 'elixir' for insert.",
          required: false
        },
        %{
          name: "edit_mode",
          type: :string,
          description:
            "Edit operation: 'replace' (default) replaces cell content, 'insert' adds a new cell after the index, 'delete' removes the cell.",
          required: false
        }
      ]
    })
  end
end
