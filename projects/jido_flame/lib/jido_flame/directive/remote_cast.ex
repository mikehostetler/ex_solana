defmodule JidoFlame.Directive.RemoteCast do
  @moduledoc """
  Execute a function asynchronously on a remote FLAME runner (fire-and-forget).

  This directive wraps `FLAME.cast/3`, executing a 0-arity function on a
  remote node without waiting for a result.

  ## Fields

  - `pool` - FLAME.Pool name or pid (required)
  - `fun` - 0-arity function to execute remotely (required)
  - `opts` - Options for FLAME.cast/3 (default: [])
  - `tag` - Correlation tag (optional)

  ## Examples

      %RemoteCast{
        pool: MyApp.FlamePool,
        fun: fn -> background_cleanup() end,
        tag: :cleanup_batch
      }

  ## Notes

  Unlike `RemoteCall`, this directive does not emit result signals.
  Use for background work where you don't need confirmation.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              pool: Zoi.any(description: "FLAME.Pool name or pid"),
              fun: Zoi.any(description: "0-arity function to execute remotely"),
              opts: Zoi.any(description: "Options for FLAME.cast/3") |> Zoi.default([]),
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
  Creates a new RemoteCast directive struct from the given attributes.

  ## Examples

      iex> RemoteCast.new(%{pool: MyPool, fun: fn -> :ok end})
      {:ok, %JidoFlame.Directive.RemoteCast{...}}

      iex> RemoteCast.new(%{})
      {:error, %JidoFlame.Error.InvalidInputError{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, errors} ->
        message = "Invalid RemoteCast directive:\n" <> Error.format_zoi_error(errors)
        {:error, Error.validation_error(message, errors: errors)}
    end
  end

  def new(_), do: {:error, Error.validation_error("Attributes must be a map")}

  @doc "Creates a new RemoteCast directive, raising on error"
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, error} -> raise error
    end
  end
end
