defmodule Jido.Character.Schema.Personality do
  @moduledoc "Character personality - how the character behaves."

  alias Jido.Character.Schema.Trait

  @trait_schema Zoi.union([
                  Zoi.string(),
                  Trait.schema()
                ])

  @schema Zoi.struct(
            __MODULE__,
            %{
              traits: Zoi.array(@trait_schema, max_length: 10) |> Zoi.default([]),
              values: Zoi.array(Zoi.string(), max_length: 10) |> Zoi.default([]),
              quirks: Zoi.array(Zoi.string(), max_length: 10) |> Zoi.default([])
            },
            coerce: true
          )

  @type trait :: String.t() | Trait.t()
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Personality"
  def schema, do: @schema

  @doc "Returns the trait schema (string or Trait struct)"
  def trait_schema, do: @trait_schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, personality} -> personality
      {:error, reason} -> raise ArgumentError, "Invalid personality: #{inspect(reason)}"
    end
  end
end
