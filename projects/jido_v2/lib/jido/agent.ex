defmodule Jido.Agent do
  @moduledoc """
  Jido 2.0 kernel: pure Agents that `think` given a state and a signal.

  > **Agents think. Servers act.**

  ## Core Contract

  Every Jido Agent implements one callback:

      @callback handle_signal(state :: t(), signal :: Jido.Signal.t()) ::
        {:ok, new_state :: t(), effects :: [Jido.Agent.Effect.t()]}
        | {:error, term()}

  This contract has three parts:

  | Part | Type | Description |
  |------|------|-------------|
  | `state` | Agent struct | Zoi-validated struct owned by the Agent module |
  | `signal` | `Jido.Signal.t()` | Universal message envelope—the only input |
  | `effects` | `[Effect.t()]` | Pure data describing side effects and orchestration |

  ## The Think/Act Mental Model

  **Think (Agent.handle_signal/2):**
  - Takes current `state` and a `signal`
  - Computes a **new state**
  - Returns a list of **Effects** describing what should happen next
  - **Never performs I/O**

  **Act (AgentServer + Actions):**
  - Runs inside `Jido.AgentServer` (not yet implemented)
  - Receives the Effects returned by `handle_signal/2`
  - Performs the **actual I/O**

  ## Usage

      defmodule MyApp.SupportAgent do
        use Jido.Agent,
          name: "support",
          schema: %{
            user_id: Zoi.integer(),
            history: Zoi.array(Zoi.any()) |> Zoi.default([]),
            status: Zoi.atom() |> Zoi.default(:idle)
          }

        alias Jido.Agent.Effect

        @impl true
        def handle_signal(state, %Jido.Signal{type: "user.message"} = signal) do
          text = signal.data["text"]
          new_history = [%{role: :user, content: text} | state.history]
          new_state = %{state | history: new_history, status: :thinking}

          effects = [
            %Effect.Run{action: MyApp.Actions.LookupFAQ, params: %{query: text}}
          ]

          {:ok, new_state, effects}
        end

        def handle_signal(state, _signal), do: {:ok, state, []}
      end

  ## Testing

  Because agents never do I/O, testing is deterministic:

      test "support agent transitions on user message" do
        {:ok, agent} = SupportAgent.new(%{id: "test-1", user_id: 42})
        signal = %Jido.Signal{type: "user.message", data: %{"text" => "Help!"}}

        {:ok, new_agent, effects} = SupportAgent.handle_signal(agent, signal)

        assert new_agent.status == :thinking
        assert length(new_agent.history) == 1
        assert %Effect.Run{action: MyApp.Actions.LookupFAQ} = hd(effects)
      end
  """

  alias Jido.Agent.Effect

  @typedoc "Effectful result of thinking about a signal."
  @type result(t) ::
          {:ok, new_state :: t, effects :: [Effect.t()]} | {:error, term()}

  @doc """
  Handle a signal and return new state with effects.

  This is the core contract that all agents must implement.
  Agents must never perform I/O in this callback - all work
  should be described via Effect structs.
  """
  @callback handle_signal(state :: struct(), signal :: Jido.Signal.t()) ::
              {:ok, new_state :: struct(), effects :: [Effect.t()]} | {:error, term()}

  @doc """
  `use Jido.Agent` macro.

  ## Options

  - `:name` - The agent name (required)
  - `:schema` - A map of field names to Zoi schemas (optional)

  ## What This Macro Does

  1. Sets up the agent behaviour
  2. Creates a Zoi struct with the provided schema (merged with base fields)
  3. Generates `new/1`, `new!/1`, `schema/0`, `name/0` functions
  4. Enforces the `handle_signal/2` callback

  ## Usage

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          schema: %{
            count: Zoi.integer() |> Zoi.default(0),
            status: Zoi.atom() |> Zoi.default(:idle)
          }

        @impl true
        def handle_signal(state, signal) do
          {:ok, state, []}
        end
      end
  """
  defmacro __using__(opts) do
    # Extract options - name is required, schema and runner are optional
    name =
      Keyword.get(opts, :name) ||
        raise ArgumentError, "use Jido.Agent requires a :name option"

    user_schema = Keyword.get(opts, :schema, quote(do: %{}))
    runner_opt = Keyword.get(opts, :runner, :simple)

    quote location: :keep do
      @behaviour Jido.Agent

      @name unquote(name)
      @runner_config unquote(runner_opt)

      # Base fields that all agents get - always includes id
      @base_schema %{
        id: Zoi.string() |> Zoi.optional()
      }

      # Merge base schema with user schema
      @schema Zoi.struct(
                __MODULE__,
                Map.merge(@base_schema, unquote(user_schema)),
                coerce: true
              )

      @enforce_keys Zoi.Struct.enforce_keys(@schema)
      defstruct Zoi.Struct.struct_fields(@schema)

      @type t :: %__MODULE__{}

      @doc "Agent name as configured in `use Jido.Agent, name: ...`."
      def name, do: @name

      @doc "Zoi schema for this agent's state struct."
      def schema, do: @schema

      @doc """
      Return the runner module for this agent.

      Normalizes the runner configuration and returns the module.
      Raises `Jido.Error.Invalid.RunnerConfig` if invalid.
      """
      @spec runner() :: module()
      def runner do
        case Jido.Agent.Runner.normalize(@runner_config) do
          {:ok, runner_mod} ->
            runner_mod

          {:error, reason} ->
            raise Jido.Error.Invalid.RunnerConfig.exception(
                    agent: __MODULE__,
                    runner: @runner_config,
                    reason: reason
                  )
        end
      end

      @doc "Return the raw runner configuration for this agent."
      def runner_config, do: @runner_config

      @doc """
      Construct a new agent state, validating against the Zoi schema.

      ## Parameters

      - `attrs` - A map of field values

      ## Returns

      - `{:ok, agent}` - Successfully created agent struct
      - `{:error, reason}` - Validation failed

      ## Example

          {:ok, agent} = MyAgent.new(%{id: "agent-1", user_id: 42})
      """
      @spec new(map()) :: {:ok, t()} | {:error, term()}
      def new(attrs \\ %{}) when is_map(attrs) do
        Zoi.parse(@schema, attrs)
      end

      @doc """
      Construct a new agent state, raising on validation failure.

      ## Parameters

      - `attrs` - A map of field values

      ## Returns

      - The agent struct

      ## Raises

      - `ArgumentError` if validation fails

      ## Example

          agent = MyAgent.new!(%{id: "agent-1", user_id: 42})
      """
      @spec new!(map()) :: t()
      def new!(attrs \\ %{}) do
        case new(attrs) do
          {:ok, agent} -> agent
          {:error, reason} -> raise ArgumentError, "Invalid #{@name} agent: #{inspect(reason)}"
        end
      end

      # Default implementation that raises - must be overridden
      @impl Jido.Agent
      def handle_signal(_state, _signal) do
        raise "handle_signal/2 not implemented for #{inspect(__MODULE__)}"
      end

      defoverridable handle_signal: 2
    end
  end
end
