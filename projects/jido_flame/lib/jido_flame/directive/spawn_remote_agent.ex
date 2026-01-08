defmodule JidoFlame.Directive.SpawnRemoteAgent do
  @moduledoc """
  Spawn a child Jido agent on a remote FLAME runner.

  This is the primary directive for distributed agent hierarchies. It spawns
  a child agent on a FLAME runner while maintaining parent-child semantics:

  - Parent tracks child by tag in its children map
  - Parent monitors child process (works across distributed Erlang)
  - Child gets a `__parent__` ParentRef pointing to parent
  - `Directive.emit_to_parent/3` works unchanged

  ## Fields

  - `pool` - FLAME.Pool name (required)
  - `agent` - Agent module or pre-built struct (required)
  - `tag` - Tracking tag in parent's children map (required)
  - `opts` - Options passed to child AgentServer (default: %{})
  - `meta` - Metadata passed via ParentRef (default: %{})
  - `jido` - Jido instance name on remote node (optional)
  - `flame_opts` - Options for FLAME.place_child/3 (default: [])

  ## Examples

      # Simple spawn
      %SpawnRemoteAgent{
        pool: MyApp.FlamePool,
        agent: WorkerAgent,
        tag: :worker_1
      }

      # With options and metadata
      %SpawnRemoteAgent{
        pool: MyApp.FlamePool,
        agent: ProcessorAgent,
        tag: :batch_processor,
        opts: %{initial_state: %{batch_size: 100}},
        meta: %{assigned_topic: "events.user"}
      }

  ## Parent Children Map

  After successful spawn, parent's children map contains:

      %{
        worker_1: %{
          pid: #PID<12345.678.0>,
          node: :"myapp_flame@10.0.0.5",
          agent: WorkerAgent,
          remote?: true,
          pool: MyApp.FlamePool,
          meta: %{}
        }
      }

  ## Lifecycle Signals

  - `jido.flame.remote.agent.started` - Emitted on successful spawn
  - `jido.flame.remote.agent.failed` - Emitted on spawn failure
  - `jido.agent.child.exit` - Emitted when child exits (with `remote?: true`)
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              pool: Zoi.any(description: "FLAME.Pool name"),
              agent: Zoi.any(description: "Agent module or pre-built struct"),
              tag: Zoi.any(description: "Tracking tag in parent's children map"),
              opts: Zoi.any(description: "Options passed to child AgentServer") |> Zoi.default(%{}),
              meta: Zoi.any(description: "Metadata passed via ParentRef") |> Zoi.default(%{}),
              jido: Zoi.any(description: "Jido instance name on remote node") |> Zoi.optional(),
              flame_opts: Zoi.any(description: "Options for FLAME.place_child/3") |> Zoi.default([])
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
  Creates a new SpawnRemoteAgent directive struct from the given attributes.

  ## Examples

      iex> SpawnRemoteAgent.new(%{pool: MyPool, agent: WorkerAgent, tag: :worker_1})
      {:ok, %JidoFlame.Directive.SpawnRemoteAgent{...}}

      iex> SpawnRemoteAgent.new(%{})
      {:error, %JidoFlame.Error.InvalidInputError{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, struct} ->
        {:ok, struct}

      {:error, errors} ->
        message = "Invalid SpawnRemoteAgent directive:\n" <> Error.format_zoi_error(errors)
        {:error, Error.validation_error(message, errors: errors)}
    end
  end

  def new(_), do: {:error, Error.validation_error("Attributes must be a map")}

  @doc "Creates a new SpawnRemoteAgent directive, raising on error"
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, error} -> raise error
    end
  end
end
