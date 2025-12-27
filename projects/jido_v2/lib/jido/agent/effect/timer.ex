defmodule Jido.Agent.Effect.Timer do
  @moduledoc """
  Request to schedule a future signal.

  This effect describes a delayed signal that should be delivered
  to the agent after a specified duration.

  ## Fields

  - `in` - Delay in milliseconds (required)
  - `signal` - The signal to deliver after the delay (required)
  - `key` - Optional key for cancellation (default: nil)

  ## Example

      %Effect.Timer{
        in: 5000,
        signal: %Jido.Signal{type: "reminder", data: %{message: "follow up"}},
        key: :reminder_timer
      }
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              in: Zoi.integer() |> Zoi.non_negative(),
              signal: Zoi.any(),
              key: Zoi.any() |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Effect.Timer"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, effect} -> effect
      {:error, reason} -> raise ArgumentError, "Invalid Effect.Timer: #{inspect(reason)}"
    end
  end
end
