defmodule Jido.BehaviorTree.Skill do
  @moduledoc """
  A behavior tree skill that can be converted to AI-compatible tool definitions.

  This module allows behavior trees to be exposed as skills that can be executed
  by AI systems. The behavior tree is wrapped in a skill interface that provides
  parameter validation, execution, and result formatting.

  ## Features

  - Convert behavior trees to LLM-compatible tool definitions
  - Parameter validation and type checking
  - Automatic blackboard management
  - Execution result formatting
  - Error handling and reporting

  ## Example Usage

      # Create a behavior tree
      tree = Jido.BehaviorTree.Tree.new(root_node)
      
      # Create a skill from the tree
      skill = Jido.BehaviorTree.Skill.new(
        "process_user_data",
        tree,
        "Processes user data through a behavior tree",
        schema: [
          user_id: [type: :integer, required: true],
          data: [type: :map, required: true]
        ]
      )
      
      # Convert to tool format
      tool_def = skill.to_tool()
      
      # Execute the skill
      {:ok, result} = skill.run(%{user_id: 123, data: %{name: "John"}}, %{})
  """

  alias Jido.BehaviorTree.{Tree, Agent, Blackboard, Error}

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(description: "The name of the skill"),
              description: Zoi.string(description: "Description of what the skill does") |> Zoi.default(""),
              tree: Zoi.any(description: "The behavior tree to execute"),
              schema:
                Zoi.any(description: "Input parameter schema (NimbleOptions or Zoi)")
                |> Zoi.default([]),
              output_schema: Zoi.any(description: "Output validation schema") |> Zoi.default([]),
              timeout:
                Zoi.integer(description: "Execution timeout in milliseconds")
                |> Zoi.min(0)
                |> Zoi.default(30_000),
              auto_mode: Zoi.boolean(description: "Whether to run in automatic mode") |> Zoi.default(false),
              interval:
                Zoi.integer(description: "Tick interval for auto mode")
                |> Zoi.min(0)
                |> Zoi.default(1000)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @doc """
  Creates a new behavior tree skill.

  ## Options

  - `:schema` - NimbleOptions schema for input validation (default: [])
  - `:output_schema` - NimbleOptions schema for output validation (default: [])
  - `:timeout` - Execution timeout in milliseconds (default: 30_000)
  - `:auto_mode` - Whether to run in automatic mode (default: false)
  - `:interval` - Tick interval for auto mode in milliseconds (default: 1000)

  ## Examples

      skill = Jido.BehaviorTree.Skill.new(
        "data_processor",
        tree,
        "Processes data using behavior tree logic",
        schema: [
          input_data: [type: :map, required: true]
        ],
        timeout: 10_000
      )

  """
  @spec new(String.t(), Tree.t(), String.t(), keyword()) :: t()
  def new(name, tree, description \\ "", opts \\ []) do
    %__MODULE__{
      name: name,
      description: description,
      tree: tree,
      schema: Keyword.get(opts, :schema, []),
      output_schema: Keyword.get(opts, :output_schema, []),
      timeout: Keyword.get(opts, :timeout, 30_000),
      auto_mode: Keyword.get(opts, :auto_mode, false),
      interval: Keyword.get(opts, :interval, 1000)
    }
  end

  @doc """
  Converts the skill to an AI-compatible tool definition.

  Returns a map that can be used with LLM function calling systems
  like OpenAI's function calling.

  ## Examples

      tool_def = skill.to_tool()
      # %{
      #   "name" => "data_processor",
      #   "description" => "Processes data using behavior tree logic",
      #   "parameters" => %{
      #     "type" => "object",
      #     "properties" => %{...},
      #     "required" => [...]
      #   }
      # }

  """
  @spec to_tool(t()) :: map()
  def to_tool(%__MODULE__{} = skill) do
    %{
      "name" => skill.name,
      "description" => skill.description,
      "parameters" => Jido.Action.Schema.to_json_schema(skill.schema)
    }
  end

  @doc """
  Executes the behavior tree skill with the given parameters.

  This function starts a behavior tree agent, executes the tree with the
  provided parameters in the blackboard, and returns the final result.

  ## Parameters

  - `params` - Input parameters (will be validated against schema)
  - `context` - Execution context (currently unused but reserved for future use)

  ## Returns

  - `{:ok, result}` - Successful execution with result map
  - `{:error, reason}` - Execution failed with error reason

  ## Examples

      {:ok, result} = Jido.BehaviorTree.Skill.run(skill, %{input_data: %{id: 1}}, %{})

  """
  @spec run(t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run(%__MODULE__{} = skill, params, _context) do
    with {:ok, validated_params} <- validate_params(skill, params),
         {:ok, result} <- execute_tree(skill, validated_params) do
      validate_output(skill, result)
    end
  end

  ## Private Functions

  defp validate_params(%__MODULE__{schema: schema}, params) do
    case Jido.Action.Schema.validate(schema, params) do
      {:ok, validated} ->
        result = if is_struct(validated), do: Map.from_struct(validated), else: validated
        {:ok, result}

      {:error, error} ->
        formatted = Jido.Action.Schema.format_error(error, "Skill params", __MODULE__)
        {:error, formatted}
    end
  end

  defp execute_tree(%__MODULE__{} = skill, params) do
    initial_blackboard = Blackboard.new(params)

    agent_opts = [
      tree: skill.tree,
      blackboard: Blackboard.to_map(initial_blackboard),
      mode: if(skill.auto_mode, do: :auto, else: :manual),
      interval: skill.interval
    ]

    case Agent.start_link(agent_opts) do
      {:ok, agent} ->
        try do
          _result =
            if skill.auto_mode do
              execute_auto_mode(agent, skill.timeout)
            else
              execute_manual_mode(agent, skill.timeout)
            end

          final_blackboard = Agent.blackboard(agent)

          Agent.halt(agent)
          GenServer.stop(agent)

          {:ok, Blackboard.to_map(final_blackboard)}
        rescue
          error ->
            Agent.halt(agent)
            GenServer.stop(agent)
            {:error, Error.execution_error("Execution failed: #{Exception.message(error)}")}
        end

      {:error, reason} ->
        {:error, Error.execution_error("Failed to start agent", %{reason: reason})}
    end
  end

  defp execute_auto_mode(_agent, timeout) do
    Process.sleep(timeout)
    :ok
  end

  defp execute_manual_mode(agent, timeout) do
    end_time = System.monotonic_time(:millisecond) + timeout
    execute_manual_loop(agent, end_time)
  end

  defp execute_manual_loop(agent, end_time) do
    if System.monotonic_time(:millisecond) > end_time do
      {:error, Error.execution_error("Execution timed out")}
    else
      case Agent.tick(agent) do
        :success ->
          :ok

        :failure ->
          :ok

        {:error, reason} ->
          {:error, Error.execution_error("Behavior tree error", %{reason: reason})}

        :running ->
          Process.sleep(10)
          execute_manual_loop(agent, end_time)
      end
    end
  end

  defp validate_output(%__MODULE__{output_schema: schema}, result) do
    case Jido.Action.Schema.validate(schema, result) do
      {:ok, validated} ->
        output = if is_struct(validated), do: Map.from_struct(validated), else: validated
        {:ok, output}

      {:error, error} ->
        formatted = Jido.Action.Schema.format_error(error, "Skill output", __MODULE__)
        {:error, formatted}
    end
  end
end
