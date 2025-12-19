defmodule JidoCode.Livebook.Cell do
  @moduledoc """
  Represents a single cell in an Elixir Livebook notebook.

  Cells can be:
  - `:markdown` - Markdown text content
  - `:elixir` - Elixir code cell
  - `:erlang` - Erlang code cell
  - `:metadata` - Livebook metadata comment (not rendered)
  - `:smart` - Smart cell with special metadata

  ## Fields

  - `type` - The cell type atom
  - `content` - The cell content as a string
  - `metadata` - Map of cell-specific metadata
  """

  @code_types [:elixir, :erlang, :heex, :sql]

  @type cell_type :: :markdown | :elixir | :erlang | :heex | :sql | :metadata | :smart
  @type t :: %__MODULE__{
          type: cell_type(),
          content: String.t(),
          metadata: map()
        }

  defstruct type: :markdown, content: "", metadata: %{}

  @doc """
  Creates a new markdown cell with the given content.
  """
  @spec markdown(String.t()) :: t()
  def markdown(content) when is_binary(content) do
    %__MODULE__{type: :markdown, content: content}
  end

  @doc """
  Creates a new Elixir code cell with the given content.
  """
  @spec elixir(String.t()) :: t()
  def elixir(content) when is_binary(content) do
    %__MODULE__{type: :elixir, content: content}
  end

  @doc """
  Creates a new Erlang code cell with the given content.
  """
  @spec erlang(String.t()) :: t()
  def erlang(content) when is_binary(content) do
    %__MODULE__{type: :erlang, content: content}
  end

  @doc """
  Creates a new cell with the given type and content.
  """
  @spec new(cell_type(), String.t(), map()) :: t()
  def new(type, content, metadata \\ %{}) do
    %__MODULE__{type: type, content: content, metadata: metadata}
  end

  @doc """
  Returns true if this is a code cell (elixir, erlang, etc.)
  """
  @spec code_cell?(t()) :: boolean()
  def code_cell?(%__MODULE__{type: type}) do
    type in @code_types
  end

  @doc """
  Returns the language string for the cell type.
  """
  @spec language(t()) :: String.t() | nil
  def language(%__MODULE__{type: :elixir}), do: "elixir"
  def language(%__MODULE__{type: :erlang}), do: "erlang"
  def language(%__MODULE__{type: :heex}), do: "heex"
  def language(%__MODULE__{type: :sql}), do: "sql"
  def language(%__MODULE__{}), do: nil
end
