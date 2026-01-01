defmodule Jido.Skill do
  @moduledoc """
  A Skill is a composable capability that can be attached to an agent.

  Skills encapsulate:
  - A set of actions the agent can perform
  - State schema for skill-specific data (nested under `state_key`)
  - Configuration schema for per-agent customization
  - Signal routing rules
  - Optional lifecycle hooks and child processes

  ## Lifecycle

  1. **Compile-time**: Skill is declared in agent's `skills:` option
  2. **Agent.new/1**: `mount/2` is called to initialize skill state (pure)
  3. **AgentServer.init/1**: `child_spec/1` processes are started and monitored
  4. **Signal processing**: `handle_signal/2` runs before routing, can override or abort
  5. **After cmd/2 (call path)**: `transform_result/3` wraps call results

  ## Example Skill

      defmodule MyApp.ChatSkill do
        use Jido.Skill,
          name: "chat",
          state_key: :chat,
          actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
          schema: Zoi.object(%{
            messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
            model: Zoi.string() |> Zoi.default("gpt-4")
          }),
          signal_patterns: ["chat.*"]

        @impl Jido.Skill
        def mount(agent, config) do
          # Custom initialization beyond schema defaults
          {:ok, %{initialized_at: DateTime.utc_now()}}
        end

        @impl Jido.Skill
        def router(config) do
          [
            {"chat.send", MyApp.Actions.SendMessage},
            {"chat.history", MyApp.Actions.ListHistory}
          ]
        end
      end

  ## Using Skills

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          skills: [
            MyApp.ChatSkill,
            {MyApp.DatabaseSkill, %{pool_size: 5}}
          ]
      end

  ## Configuration Options

  - `name` - Required. The skill name (letters, numbers, underscores).
  - `state_key` - Required. Atom key for skill state in agent.
  - `actions` - Required. List of action modules.
  - `description` - Optional description.
  - `category` - Optional category.
  - `vsn` - Optional version string.
  - `schema` - Optional Zoi schema for skill state.
  - `config_schema` - Optional Zoi schema for per-agent config.
  - `signal_patterns` - List of signal pattern strings (default: []).
  - `tags` - List of tag strings (default: []).
  """

  alias Jido.Skill.Spec

  @skill_config_schema Zoi.object(
                         %{
                           name:
                             Zoi.string(
                               description:
                                 "The name of the Skill. Must contain only letters, numbers, and underscores."
                             )
                             |> Zoi.refine({Jido.Util, :validate_name, []}),
                           state_key:
                             Zoi.atom(description: "The key for skill state in agent state."),
                           actions:
                             Zoi.list(Zoi.atom(), description: "List of action modules.")
                             |> Zoi.refine({Jido.Util, :validate_actions, []}),
                           description:
                             Zoi.string(description: "A description of what the Skill does.")
                             |> Zoi.optional(),
                           category:
                             Zoi.string(description: "The category of the Skill.")
                             |> Zoi.optional(),
                           vsn:
                             Zoi.string(description: "Version")
                             |> Zoi.optional(),
                           schema:
                             Zoi.any(description: "Zoi schema for skill state.")
                             |> Zoi.optional(),
                           config_schema:
                             Zoi.any(description: "Zoi schema for per-agent configuration.")
                             |> Zoi.optional(),
                           signal_patterns:
                             Zoi.list(Zoi.string(), description: "Signal patterns for routing.")
                             |> Zoi.default([]),
                           tags:
                             Zoi.list(Zoi.string(), description: "Tags for categorization.")
                             |> Zoi.default([])
                         },
                         coerce: true
                       )

  @doc false
  def config_schema, do: @skill_config_schema

  # Callbacks

  @doc """
  Returns the skill specification with optional per-agent configuration.

  This is the primary interface for getting skill metadata and configuration.
  """
  @callback skill_spec(config :: map()) :: Spec.t()

  @doc """
  Called when the skill is mounted to an agent during `Agent.new/1`.

  Use this to initialize skill-specific state beyond schema defaults.
  This is a pure function - no side effects allowed.

  ## Parameters

  - `agent` - The agent struct (with state from previously mounted skills)
  - `config` - Per-agent configuration for this skill

  ## Returns

  - `{:ok, skill_state}` - Map to merge into skill's state slice
  - `{:ok, nil}` - No additional state (schema defaults only)
  - `{:error, reason}` - Raises during agent creation

  ## Example

      def mount(_agent, config) do
        {:ok, %{initialized_at: DateTime.utc_now(), api_key: config[:api_key]}}
      end
  """
  @callback mount(agent :: term(), config :: map()) :: {:ok, map() | nil} | {:error, term()}

  @doc """
  Returns the signal router for this skill.

  The router determines how signals are routed to handlers.
  """
  @callback router(config :: map()) :: term()

  @doc """
  Pre-routing hook called before signal routing in AgentServer.

  Can inspect, log, or override which action runs for a signal.

  ## Parameters

  - `signal` - The incoming `Jido.Signal` struct
  - `context` - Map with `:agent`, `:agent_module`, `:skill`, `:skill_spec`, `:config`

  ## Returns

  - `{:ok, nil}` or `{:ok, :continue}` - Continue to normal routing
  - `{:ok, {:override, action_spec}}` - Bypass router, use this action instead
  - `{:error, reason}` - Abort signal processing with error

  ## Example

      def handle_signal(signal, _context) do
        if signal.type == "admin.override" do
          {:ok, {:override, MyApp.AdminAction}}
        else
          {:ok, :continue}
        end
      end
  """
  @callback handle_signal(signal :: term(), context :: map()) ::
              {:ok, term()} | {:ok, {:override, term()}} | {:error, term()}

  @doc """
  Transform the agent returned from `AgentServer.call/3`.

  Called after signal processing on the synchronous call path only.
  Does not affect `cast/2` or internal state - only the returned agent.

  ## Parameters

  - `action` - The signal type or action module that was executed
  - `result` - The agent struct to transform
  - `context` - Map with `:agent`, `:agent_module`, `:skill`, `:skill_spec`, `:config`

  ## Returns

  The transformed agent struct (or original if no transformation needed).

  ## Example

      def transform_result(_action, agent, _context) do
        # Add metadata to returned agent
        new_state = Map.put(agent.state, :last_call_at, DateTime.utc_now())
        %{agent | state: new_state}
      end
  """
  @callback transform_result(action :: module() | String.t(), result :: term(), context :: map()) ::
              term()

  @doc """
  Returns child specification(s) for supervised processes.

  Called during `AgentServer.init/1`. Returned processes are
  monitored by the AgentServer and tracked in its state.

  ## Parameters

  - `config` - Per-agent configuration for this skill

  ## Return Values

  - `nil` - No child processes needed
  - `Supervisor.child_spec()` - Single child process
  - `[Supervisor.child_spec()]` - Multiple child processes

  ## Example

      def child_spec(config) do
        %{
          id: MyWorker,
          start: {MyWorker, :start_link, [config]}
        }
      end
  """
  @callback child_spec(config :: map()) ::
              nil | Supervisor.child_spec() | [Supervisor.child_spec()]

  @optional_callbacks [mount: 2, router: 1, handle_signal: 2, transform_result: 3, child_spec: 1]

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Skill

      alias Jido.Skill
      alias Jido.Skill.Spec

      # Validate config at compile time
      @validated_opts (case Zoi.parse(Skill.config_schema(), Map.new(unquote(opts))) do
                         {:ok, validated} ->
                           validated

                         {:error, errors} ->
                           message =
                             "Invalid Skill configuration for #{inspect(__MODULE__)}: #{inspect(errors)}"

                           raise CompileError,
                             description: message,
                             file: __ENV__.file,
                             line: __ENV__.line
                       end)

      # Validate actions exist at compile time
      @validated_opts.actions
      |> Enum.each(fn action_module ->
        case Code.ensure_compiled(action_module) do
          {:module, _} ->
            unless function_exported?(action_module, :__action_metadata__, 0) do
              raise CompileError,
                description:
                  "Action #{inspect(action_module)} does not implement Jido.Action behavior",
                file: __ENV__.file,
                line: __ENV__.line
            end

          {:error, reason} ->
            raise CompileError,
              description:
                "Action #{inspect(action_module)} could not be compiled: #{inspect(reason)}",
              file: __ENV__.file,
              line: __ENV__.line
        end
      end)

      # Metadata accessors
      def name, do: @validated_opts.name
      def state_key, do: @validated_opts.state_key
      def actions, do: @validated_opts.actions
      def description, do: @validated_opts[:description]
      def category, do: @validated_opts[:category]
      def vsn, do: @validated_opts[:vsn]
      def schema, do: @validated_opts[:schema]
      def config_schema, do: @validated_opts[:config_schema]
      def signal_patterns, do: @validated_opts[:signal_patterns] || []
      def tags, do: @validated_opts[:tags] || []

      @doc """
      Returns the skill specification with optional per-agent configuration.

      ## Examples

          spec = #{inspect(__MODULE__)}.skill_spec(%{})
          spec = #{inspect(__MODULE__)}.skill_spec(%{custom_option: true})
      """
      @impl Jido.Skill
      def skill_spec(config \\ %{}) do
        %Spec{
          module: __MODULE__,
          name: name(),
          state_key: state_key(),
          description: description(),
          category: category(),
          vsn: vsn(),
          schema: schema(),
          config_schema: config_schema(),
          config: config,
          signal_patterns: signal_patterns(),
          tags: tags(),
          actions: actions()
        }
      end

      # Default implementations for optional callbacks

      @doc false
      @impl Jido.Skill
      def mount(_agent, _config), do: {:ok, %{}}

      @doc false
      @impl Jido.Skill
      def router(_config), do: nil

      @doc false
      @impl Jido.Skill
      def handle_signal(_signal, _context), do: {:ok, nil}

      @doc false
      @impl Jido.Skill
      def transform_result(_action, result, _context), do: result

      @doc false
      @impl Jido.Skill
      def child_spec(_config), do: nil

      defoverridable mount: 2,
                     router: 1,
                     handle_signal: 2,
                     transform_result: 3,
                     child_spec: 1,
                     name: 0,
                     state_key: 0,
                     actions: 0,
                     description: 0,
                     category: 0,
                     vsn: 0,
                     schema: 0,
                     config_schema: 0,
                     signal_patterns: 0,
                     tags: 0
    end
  end
end
