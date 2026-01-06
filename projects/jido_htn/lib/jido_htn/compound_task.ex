defmodule Jido.HTN.CompoundTask do
  @moduledoc """
  Represents a compound task in the HTN planning system.
  """

  alias Jido.HTN.Method

  @schema Zoi.struct(
            __MODULE__,
            %{
              name:
                Zoi.string(description: "Compound task name"),
              methods:
                Zoi.list(
                  # We use Zoi.any() here because Methods may not always be fully validated structs
                  # during construction. The builder will ensure they're valid Methods.
                  Zoi.any(description: "Decomposition methods"),
                  description: "List of methods for decomposing this task"
                )
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc """
  Creates a new compound task with the given name and optional list of methods.
  """
  @spec new(String.t(), [Method.t()]) :: {:ok, t()} | {:error, term()}
  def new(name, methods \\ []) when is_binary(name) do
    Zoi.parse(@schema, %{name: name, methods: methods})
  end

  @spec new!(String.t(), [Method.t()]) :: t()
  def new!(name, methods \\ []) when is_binary(name) do
    case new(name, methods) do
      {:ok, task} -> task
      {:error, reason} -> raise ArgumentError, "Invalid CompoundTask: #{inspect(reason)}"
    end
  end

  @doc """
  Adds a method to the compound task.
  """
  @spec add_method(t(), Method.t()) :: t()
  def add_method(%__MODULE__{methods: methods} = task, method) do
    %{task | methods: methods ++ [method]}
  end
end
