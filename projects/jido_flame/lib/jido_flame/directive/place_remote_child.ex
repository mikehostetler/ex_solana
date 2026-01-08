defmodule JidoFlame.Directive.PlaceRemoteChild do
  @moduledoc """
  Place a generic child process on a remote FLAME runner.

  This is a low-level directive wrapping `FLAME.place_child/3` for non-agent
  processes (Tasks, GenServers, etc.). For spawning Jido agents, prefer
  `SpawnRemoteAgent` which provides full hierarchy tracking.

  ## Fields

  - `pool` - FLAME.Pool name or pid (required)
  - `child_spec` - Supervisor child_spec (required)
  - `opts` - Options for FLAME.place_child/3 (default: [])
  - `tag` - Correlation/tracking tag (optional)
  - `track?` - Whether to track in parent's children map (default: false)

  ## Examples

      # Fire-and-forget remote process
      %PlaceRemoteChild{
        pool: MyApp.FlamePool,
        child_spec: {MyWorker, arg: value}
      }

      # Tracked remote process
      %PlaceRemoteChild{
        pool: MyApp.FlamePool,
        child_spec: {LongRunningTask, config},
        tag: :background_job,
        track?: true
      }

  ## Tracking

  When `track?` is true:
  - Process is added to parent's children map under `tag`
  - Process is monitored; exit triggers `jido.agent.child.exit` signal
  - Marked with `remote?: true` in children metadata

  When `track?` is false (default):
  - Fire-and-forget; parent doesn't track the process
  - No exit signals to parent
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              pool: Zoi.any(description: "FLAME.Pool name or pid"),
              child_spec: Zoi.any(description: "Supervisor child_spec"),
              opts: Zoi.any(description: "Options for FLAME.place_child/3") |> Zoi.default([]),
              tag: Zoi.any(description: "Correlation/tracking tag") |> Zoi.optional(),
              track?: Zoi.boolean(description: "Track in parent's children map") |> Zoi.default(false)
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
  Creates a new PlaceRemoteChild directive struct from the given attributes.

  ## Examples

      iex> PlaceRemoteChild.new(%{pool: MyPool, child_spec: {MyWorker, []}})
      {:ok, %JidoFlame.Directive.PlaceRemoteChild{...}}

      iex> PlaceRemoteChild.new(%{})
      {:error, %JidoFlame.Error.InvalidInputError{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, errors} ->
        message = "Invalid PlaceRemoteChild directive:\n" <> Error.format_zoi_error(errors)
        {:error, Error.validation_error(message, errors: errors)}
    end
  end

  def new(_), do: {:error, Error.validation_error("Attributes must be a map")}

  @doc "Creates a new PlaceRemoteChild directive, raising on error"
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, error} -> raise error
    end
  end
end
