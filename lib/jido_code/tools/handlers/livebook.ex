defmodule JidoCode.Tools.Handlers.Livebook do
  @moduledoc """
  Handler modules for Livebook notebook tools.

  This module contains sub-modules that implement the execute/2 callback
  for Livebook notebook operations.

  ## Handler Modules

  - `EditCell` - Edit, insert, or delete notebook cells

  ## Usage

  These handlers are invoked by the Executor when the LLM calls livebook tools:

      Executor.execute(%{
        id: "call_123",
        name: "livebook_edit",
        arguments: %{
          "notebook_path" => "notebook.livemd",
          "cell_index" => 0,
          "new_source" => "IO.puts(:hello)"
        }
      })
  """

  alias JidoCode.Livebook.{Cell, Notebook, Parser, Serializer}
  alias JidoCode.Tools.HandlerHelpers

  @doc false
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  defdelegate validate_path(path, context), to: HandlerHelpers

  @doc false
  def format_error(:enoent, path), do: "Notebook not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"
  def format_error(:out_of_bounds, _path), do: "Cell index out of bounds"

  def format_error(:path_escapes_boundary, path),
    do: "Security error: path escapes project boundary: #{path}"

  def format_error(:path_outside_boundary, path),
    do: "Security error: path is outside project: #{path}"

  def format_error(reason, path) when is_atom(reason), do: "Livebook error (#{reason}): #{path}"
  def format_error(reason, _path) when is_binary(reason), do: reason
  def format_error(reason, path), do: "Error (#{inspect(reason)}): #{path}"

  # ============================================================================
  # EditCell Handler
  # ============================================================================

  defmodule EditCell do
    @moduledoc """
    Handler for the livebook_edit tool.

    Edits, inserts, or deletes cells in Livebook notebooks (.livemd files).

    ## Session Context

    Uses session-aware path validation when `session_id` is provided in context.
    Falls back to `project_root` for legacy compatibility.
    """

    alias JidoCode.Livebook.{Cell, Notebook, Parser, Serializer}
    alias JidoCode.Tools.Handlers.Livebook

    @doc """
    Edits a Livebook notebook cell.

    ## Arguments

    - `"notebook_path"` - Path to the .livemd file (relative to project root)
    - `"cell_index"` - Index of the cell to edit (0-based)
    - `"new_source"` - New content for the cell
    - `"cell_type"` - Cell type (optional, defaults to existing type or "elixir" for insert)
    - `"edit_mode"` - Operation mode: "replace" (default), "insert", or "delete"

    ## Context

    - `:session_id` - Session ID for path validation (preferred)
    - `:project_root` - Fallback project root for legacy compatibility

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(
          %{"notebook_path" => path, "cell_index" => cell_index, "new_source" => new_source} =
            args,
          context
        )
        when is_binary(path) and is_integer(cell_index) and is_binary(new_source) do
      edit_mode = Map.get(args, "edit_mode", "replace")
      cell_type = Map.get(args, "cell_type", nil)

      with {:ok, safe_path} <- Livebook.validate_path(path, context),
           {:ok, content} <- File.read(safe_path),
           {:ok, notebook} <- Parser.parse(content),
           {:ok, updated_notebook} <-
             apply_edit(notebook, cell_index, new_source, cell_type, edit_mode),
           new_content = Serializer.serialize(updated_notebook),
           :ok <- File.write(safe_path, new_content) do
        {:ok, format_success_message(edit_mode, cell_index, path)}
      else
        {:error, reason} -> {:error, Livebook.format_error(reason, path)}
      end
    end

    # Handle delete mode (new_source not required)
    def execute(
          %{"notebook_path" => path, "cell_index" => cell_index, "edit_mode" => "delete"},
          context
        )
        when is_binary(path) and is_integer(cell_index) do
      with {:ok, safe_path} <- Livebook.validate_path(path, context),
           {:ok, content} <- File.read(safe_path),
           {:ok, notebook} <- Parser.parse(content),
           {:ok, updated_notebook} <- Notebook.delete_cell(notebook, cell_index),
           new_content = Serializer.serialize(updated_notebook),
           :ok <- File.write(safe_path, new_content) do
        {:ok, "Successfully deleted cell #{cell_index} from #{path}"}
      else
        {:error, reason} -> {:error, Livebook.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "livebook_edit requires notebook_path, cell_index, and new_source arguments"}
    end

    defp apply_edit(notebook, cell_index, new_source, cell_type, "replace") do
      case Notebook.get_cell(notebook, cell_index) do
        {:ok, existing_cell} ->
          type = parse_cell_type(cell_type) || existing_cell.type
          new_cell = Cell.new(type, new_source, existing_cell.metadata)
          Notebook.replace_cell(notebook, cell_index, new_cell)

        {:error, _} = error ->
          error
      end
    end

    defp apply_edit(notebook, cell_index, new_source, cell_type, "insert") do
      type = parse_cell_type(cell_type) || :elixir
      new_cell = Cell.new(type, new_source)
      Notebook.insert_cell(notebook, cell_index, new_cell)
    end

    defp apply_edit(notebook, cell_index, _new_source, _cell_type, "delete") do
      Notebook.delete_cell(notebook, cell_index)
    end

    defp apply_edit(_notebook, _cell_index, _new_source, _cell_type, mode) do
      {:error, "Unknown edit_mode: #{mode}. Use 'replace', 'insert', or 'delete'."}
    end

    defp parse_cell_type(nil), do: nil
    defp parse_cell_type("elixir"), do: :elixir
    defp parse_cell_type("erlang"), do: :erlang
    defp parse_cell_type("markdown"), do: :markdown
    defp parse_cell_type("heex"), do: :heex
    defp parse_cell_type("sql"), do: :sql
    defp parse_cell_type(type), do: String.to_atom(type)

    defp format_success_message("replace", index, path) do
      "Successfully replaced cell #{index} in #{path}"
    end

    defp format_success_message("insert", index, path) do
      "Successfully inserted cell after index #{index} in #{path}"
    end

    defp format_success_message("delete", index, path) do
      "Successfully deleted cell #{index} from #{path}"
    end
  end
end
