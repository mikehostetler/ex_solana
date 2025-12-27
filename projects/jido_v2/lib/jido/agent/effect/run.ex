defmodule Jido.Agent.Effect.Run do
  @moduledoc """
  Request to run an Action module with params.

  This effect describes a request to execute work via an Action.
  The AgentServer will interpret this and call the actual Action.

  ## Fields

  - `action` - The Action module to execute (required)
  - `params` - Parameters to pass to the action (default: %{})

  ## Example

      %Effect.Run{
        action: MyApp.Actions.LookupFAQ,
        params: %{query: "how do I reset my password?"}
      }
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              action: Zoi.atom(),
              params: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Effect.Run"
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, effect} -> effect
      {:error, reason} -> raise ArgumentError, "Invalid Effect.Run: #{inspect(reason)}"
    end
  end
end
