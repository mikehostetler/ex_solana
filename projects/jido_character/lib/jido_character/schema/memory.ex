defmodule Jido.Character.Schema.Memory do
  @moduledoc "Character memory with entries and capacity limit."

  alias Jido.Character.Schema.MemoryEntry

  @schema Zoi.struct(
            __MODULE__,
            %{
              entries: Zoi.array(MemoryEntry.schema()) |> Zoi.default([]),
              capacity: Zoi.integer() |> Zoi.positive() |> Zoi.default(100)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Memory"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, memory} -> memory
      {:error, reason} -> raise ArgumentError, "Invalid memory: #{inspect(reason)}"
    end
  end
end
