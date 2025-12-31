defmodule Jido.Skill do
  @moduledoc """
  A Skill is a composable capability that can be attached to an agent.

  Skills encapsulate:
  - A set of actions the agent can perform
  - State schema for skill-specific data
  - Configuration schema for per-agent customization
  - Signal patterns for routing
  - Optional process-layer callbacks for runtime behavior

  ## Core Pattern

  Skills are defined using the `use Jido.Skill` macro:

      defmodule MySkill do
        use Jido.Skill,
          name: "my_skill",
          state_key: :my_skill,
          actions: [MyAction],
          schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(0)})
      end

  The skill is attached to an agent and provides its spec via `skill_spec/1`:

      spec = MySkill.skill_spec(%{})

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

  ## Process-Layer Callbacks

  Skills can optionally implement process-layer callbacks for runtime behavior:

  - `mount/2` - Initialize skill state when attached to an agent
  - `router/1` - Return signal router for this skill
  - `handle_signal/2` - Handle incoming signals
  - `transform_result/3` - Transform action results before returning
  - `child_spec/1` - Return child spec for supervised processes
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
  Called when the skill is mounted to an agent.

  Use this to initialize skill-specific state. Returns the initial state
  that will be stored under the skill's `state_key`.

  ## Parameters

  - `agent` - The agent struct
  - `config` - Per-agent configuration for this skill

  ## Returns

  - `{:ok, initial_state}` - Success with initial state
  - `{:error, reason}` - Failure
  """
  @callback mount(agent :: term(), config :: map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Returns the signal router for this skill.

  The router determines how signals are routed to handlers.
  """
  @callback router(config :: map()) :: term()

  @doc """
  Handle an incoming signal.

  Called when a signal matches one of the skill's signal patterns.

  ## Parameters

  - `signal` - The incoming signal
  - `context` - Context including agent, config, etc.

  ## Returns

  - `{:ok, result}` - Success
  - `{:error, reason}` - Failure
  """
  @callback handle_signal(signal :: term(), context :: map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Transform an action result before returning.

  Called after an action completes to allow skills to modify the result.

  ## Parameters

  - `action` - The action module that was executed
  - `result` - The action result
  - `context` - Context including agent, config, etc.

  ## Returns

  The transformed result.
  """
  @callback transform_result(action :: module(), result :: term(), context :: map()) :: term()

  @doc """
  Returns a child specification for supervised processes.

  Use this when the skill needs to run supervised processes.
  """
  @callback child_spec(config :: map()) :: Supervisor.child_spec()

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
