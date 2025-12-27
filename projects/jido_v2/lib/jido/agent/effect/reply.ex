defmodule Jido.Agent.Effect.Reply do
  @moduledoc """
  Request to send a response signal (e.g. back to caller).

  This effect describes a response that should be sent to a target.
  The AgentServer will interpret this and deliver the signal.

  ## Fields

  - `to` - The target for the reply (optional, defaults to signal source)
  - `signal` - The response signal to send (required)

  ## Example

      %Effect.Reply{
        to: caller_pid,
        signal: %Jido.Signal{type: "response", data: %{result: "success"}}
      }
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              to: Zoi.any() |> Zoi.optional(),
              signal: Zoi.any()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Effect.Reply"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, effect} -> effect
      {:error, reason} -> raise ArgumentError, "Invalid Effect.Reply: #{inspect(reason)}"
    end
  end
end
