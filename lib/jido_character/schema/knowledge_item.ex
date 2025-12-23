defmodule Jido.Character.Schema.KnowledgeItem do
  @moduledoc "Permanent fact the character knows (no decay)."

  @schema Zoi.struct(
            __MODULE__,
            %{
              content: Zoi.string(min_length: 1),
              category: Zoi.string() |> Zoi.nullish(),
              importance: Zoi.float() |> Zoi.gte(0) |> Zoi.lte(1) |> Zoi.default(0.5)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for KnowledgeItem"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, item} -> item
      {:error, reason} -> raise ArgumentError, "Invalid knowledge item: #{inspect(reason)}"
    end
  end
end
