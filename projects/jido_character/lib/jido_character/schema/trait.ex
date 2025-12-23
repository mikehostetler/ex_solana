defmodule Jido.Character.Schema.Trait do
  @moduledoc "Personality trait with optional intensity (0.0-1.0)."

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(min_length: 1),
              intensity: Zoi.float() |> Zoi.gte(0) |> Zoi.lte(1) |> Zoi.default(0.5)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Trait"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, trait} -> trait
      {:error, reason} -> raise ArgumentError, "Invalid trait: #{inspect(reason)}"
    end
  end
end
