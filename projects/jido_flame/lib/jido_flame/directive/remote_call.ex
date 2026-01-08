defmodule JidoFlame.Directive.RemoteCall do
  @moduledoc """
  Execute a function synchronously on a remote FLAME runner.

  This directive wraps `FLAME.call/3`, executing a 0-arity function on a
  remote node and optionally signaling the result back.

  ## Fields

  - `pool` - FLAME.Pool name or pid (required)
  - `fun` - 0-arity function to execute remotely (required)
  - `opts` - Options for FLAME.call/3 (default: [])
  - `result_type` - CloudEvents type for result signal (optional)
  - `result_dispatch` - Dispatch config for result signal (optional)
  - `tag` - Correlation tag (optional)

  ## Examples

      %RemoteCall{
        pool: MyApp.FlamePool,
        fun: fn -> expensive_computation() end,
        result_type: "compute.completed",
        tag: :batch_42
      }

  ## Lifecycle Signals

  If `result_type` is set:
  - Success: Signal with type `result_type` and data containing the result
  - Failure: Signal with type `jido.flame.call.failed`
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              pool: Zoi.any(description: "FLAME.Pool name or pid"),
              fun: Zoi.any(description: "0-arity function to execute remotely"),
              opts: Zoi.any(description: "Options for FLAME.call/3") |> Zoi.default([]),
              result_type: Zoi.string(description: "CloudEvents type for result signal") |> Zoi.optional(),
              result_dispatch: Zoi.any(description: "Dispatch config for result signal") |> Zoi.optional(),
              tag: Zoi.any(description: "Correlation tag") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  alias JidoFlame.Error

  @doc "Returns the Zoi schema for this directive"
  def schema, do: @schema

  @doc """
  Creates a new RemoteCall directive struct from the given attributes.

  ## Examples

      iex> RemoteCall.new(%{pool: MyPool, fun: fn -> :ok end})
      {:ok, %JidoFlame.Directive.RemoteCall{...}}

      iex> RemoteCall.new(%{})
      {:error, %JidoFlame.Error.InvalidInputError{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, errors} ->
        message = "Invalid RemoteCall directive:\n" <> Error.format_zoi_error(errors)
        {:error, Error.validation_error(message, errors: errors)}
    end
  end

  def new(_), do: {:error, Error.validation_error("Attributes must be a map")}

  @doc "Creates a new RemoteCall directive, raising on error"
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, error} -> raise error
    end
  end
end
