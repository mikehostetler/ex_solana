defmodule Jido.Character.Schema.Identity do
  @moduledoc "Character identity - who the character is."

  @schema Zoi.struct(
            __MODULE__,
            %{
              age:
                Zoi.union([
                  Zoi.integer() |> Zoi.non_negative(),
                  Zoi.string()
                ])
                |> Zoi.nullish(),
              background: Zoi.string(max_length: 2000) |> Zoi.nullish(),
              role: Zoi.string(max_length: 200) |> Zoi.nullish(),
              facts: Zoi.array(Zoi.string()) |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Identity"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, identity} -> identity
      {:error, reason} -> raise ArgumentError, "Invalid identity: #{inspect(reason)}"
    end
  end
end
