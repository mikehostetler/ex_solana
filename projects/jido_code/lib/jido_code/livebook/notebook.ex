defmodule JidoCode.Livebook.Notebook do
  @moduledoc """
  Represents an Elixir Livebook notebook structure.

  A notebook contains an ordered list of cells (markdown and code)
  along with optional metadata.

  ## Fields

  - `cells` - List of `%Cell{}` structs in order
  - `metadata` - Map of notebook-level metadata (autosave interval, etc.)
  """

  alias JidoCode.Livebook.Cell

  @type t :: %__MODULE__{
          cells: [Cell.t()],
          metadata: map()
        }

  defstruct cells: [], metadata: %{}

  @doc """
  Creates a new empty notebook.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a notebook with the given cells.
  """
  @spec new([Cell.t()]) :: t()
  def new(cells) when is_list(cells) do
    %__MODULE__{cells: cells}
  end

  @doc """
  Returns the number of cells in the notebook.
  """
  @spec cell_count(t()) :: non_neg_integer()
  def cell_count(%__MODULE__{cells: cells}), do: length(cells)

  @doc """
  Gets a cell by index (0-based).

  Returns `{:ok, cell}` if found, `{:error, :out_of_bounds}` otherwise.
  """
  @spec get_cell(t(), non_neg_integer()) :: {:ok, Cell.t()} | {:error, :out_of_bounds}
  def get_cell(%__MODULE__{cells: cells}, index) when index >= 0 and index < length(cells) do
    {:ok, Enum.at(cells, index)}
  end

  def get_cell(%__MODULE__{}, _index), do: {:error, :out_of_bounds}

  @doc """
  Replaces a cell at the given index.

  Returns `{:ok, updated_notebook}` if successful, `{:error, :out_of_bounds}` otherwise.
  """
  @spec replace_cell(t(), non_neg_integer(), Cell.t()) :: {:ok, t()} | {:error, :out_of_bounds}
  def replace_cell(%__MODULE__{cells: cells} = notebook, index, cell)
      when index >= 0 and index < length(cells) do
    updated_cells = List.replace_at(cells, index, cell)
    {:ok, %{notebook | cells: updated_cells}}
  end

  def replace_cell(%__MODULE__{}, _index, _cell), do: {:error, :out_of_bounds}

  @doc """
  Inserts a cell after the given index.

  Use index -1 to insert at the beginning.
  Returns `{:ok, updated_notebook}` if successful.
  """
  @spec insert_cell(t(), integer(), Cell.t()) :: {:ok, t()} | {:error, :out_of_bounds}
  def insert_cell(%__MODULE__{cells: cells} = notebook, -1, cell) do
    {:ok, %{notebook | cells: [cell | cells]}}
  end

  def insert_cell(%__MODULE__{cells: cells} = notebook, index, cell)
      when index >= 0 and index < length(cells) do
    updated_cells = List.insert_at(cells, index + 1, cell)
    {:ok, %{notebook | cells: updated_cells}}
  end

  # Allow inserting at end (index == last cell index to append after it)
  def insert_cell(%__MODULE__{cells: cells} = notebook, index, cell)
      when index >= 0 and index == length(cells) do
    {:ok, %{notebook | cells: cells ++ [cell]}}
  end

  def insert_cell(%__MODULE__{}, _index, _cell), do: {:error, :out_of_bounds}

  @doc """
  Deletes a cell at the given index.

  Returns `{:ok, updated_notebook}` if successful, `{:error, :out_of_bounds}` otherwise.
  """
  @spec delete_cell(t(), non_neg_integer()) :: {:ok, t()} | {:error, :out_of_bounds}
  def delete_cell(%__MODULE__{cells: cells} = notebook, index)
      when index >= 0 and index < length(cells) do
    updated_cells = List.delete_at(cells, index)
    {:ok, %{notebook | cells: updated_cells}}
  end

  def delete_cell(%__MODULE__{}, _index), do: {:error, :out_of_bounds}

  @doc """
  Returns only code cells (elixir, erlang, etc.) from the notebook.
  """
  @spec code_cells(t()) :: [Cell.t()]
  def code_cells(%__MODULE__{cells: cells}) do
    Enum.filter(cells, &Cell.code_cell?/1)
  end

  @doc """
  Returns only markdown cells from the notebook.
  """
  @spec markdown_cells(t()) :: [Cell.t()]
  def markdown_cells(%__MODULE__{cells: cells}) do
    Enum.filter(cells, fn cell -> cell.type == :markdown end)
  end
end
