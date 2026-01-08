defmodule JidoFlame.Directive.StopRemoteAgent do
  @moduledoc """
  Stop a remote child agent that was spawned via `SpawnRemoteAgent`.

  This directive coordinates shutdown of a remote child by looking up the
  child's pid from the parent's children map and stopping it gracefully.

  ## Fields

  - `tag` - Child's tag in parent's children map (required)
  - `reason` - Shutdown reason (default: :normal)

  ## Examples

      %StopRemoteAgent{tag: :worker_1}
      %StopRemoteAgent{tag: :processor, reason: :shutdown}

  ## Behavior

  1. Runtime looks up child info from parent's children map using `tag`
  2. If found and `remote?: true`, sends stop to the remote process
  3. Child exits, triggering normal `jido.agent.child.exit` signal
  4. Parent's children map is updated (child removed)

  ## Notes

  - If child is not found or already stopped, this is a no-op
  - Works for any remote child with `remote?: true` in metadata
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              tag: Zoi.any(description: "Child's tag in parent's children map"),
              reason: Zoi.any(description: "Shutdown reason") |> Zoi.default(:normal)
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
  Creates a new StopRemoteAgent directive struct from the given attributes.

  ## Examples

      iex> StopRemoteAgent.new(%{tag: :worker_1})
      {:ok, %JidoFlame.Directive.StopRemoteAgent{...}}

      iex> StopRemoteAgent.new(%{})
      {:error, %JidoFlame.Error.InvalidInputError{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, errors} ->
        message = "Invalid StopRemoteAgent directive:\n" <> Error.format_zoi_error(errors)
        {:error, Error.validation_error(message, errors: errors)}
    end
  end

  def new(_), do: {:error, Error.validation_error("Attributes must be a map")}

  @doc "Creates a new StopRemoteAgent directive, raising on error"
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, error} -> raise error
    end
  end
end
