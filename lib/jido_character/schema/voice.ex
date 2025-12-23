defmodule Jido.Character.Schema.Voice do
  @moduledoc "Character voice - how the character communicates."

  @schema Zoi.struct(
            __MODULE__,
            %{
              tone:
                Zoi.enum([
                  :formal,
                  :casual,
                  :playful,
                  :serious,
                  :warm,
                  :cold,
                  :professional,
                  :friendly
                ])
                |> Zoi.default(:casual),
              style: Zoi.string(max_length: 500) |> Zoi.nullish(),
              vocabulary:
                Zoi.enum([:simple, :technical, :academic, :conversational, :poetic])
                |> Zoi.nullish(),
              expressions: Zoi.array(Zoi.string(), max_length: 20) |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Voice"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, voice} -> voice
      {:error, reason} -> raise ArgumentError, "Invalid voice: #{inspect(reason)}"
    end
  end
end
