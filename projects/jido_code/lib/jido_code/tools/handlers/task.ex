defmodule JidoCode.Tools.Handlers.Task do
  @moduledoc """
  Handler for the spawn_task tool.

  Enables spawning specialized sub-agents for complex tasks, leveraging the
  Jido framework's agent architecture for isolated execution and result aggregation.

  ## Security

  Sub-agents inherit the same security constraints as the parent agent:
  - File system operations are sandboxed to project root
  - Shell commands must be in the allowlist
  - Web requests are subject to domain allowlist

  ## Usage

  The handler is invoked by the Executor when the LLM calls the spawn_task tool:

      Executor.execute(%{
        id: "call_123",
        name: "spawn_task",
        arguments: %{
          "description" => "Search for API patterns",
          "prompt" => "Find all REST API endpoints in the codebase"
        }
      })
  """

  require Logger

  alias JidoCode.Agents.TaskAgent
  alias JidoCode.AgentSupervisor

  @default_timeout 60_000
  @max_timeout 300_000

  @doc """
  Spawns a sub-agent to execute a task and waits for the result.

  ## Arguments

  - `"description"` - Short task description (required)
  - `"prompt"` - Detailed task instructions (required)
  - `"subagent_type"` - Agent specialization hint (optional, for future use)
  - `"model"` - Override model for sub-agent (optional)
  - `"timeout"` - Task timeout in ms (optional, default 60000, max 300000)

  ## Returns

  - `{:ok, result}` - Task completed with result string
  - `{:error, reason}` - Task failed or timed out
  """
  def execute(%{"description" => description, "prompt" => prompt} = args, context)
      when is_binary(description) and is_binary(prompt) do
    # Validate inputs
    with :ok <- validate_description(description),
         :ok <- validate_prompt(prompt),
         {:ok, timeout} <- parse_timeout(args) do
      task_id = generate_task_id()

      # Build agent spec
      agent_spec = build_agent_spec(task_id, description, prompt, args, context)

      # Execute task
      execute_task(task_id, agent_spec, timeout)
    end
  end

  def execute(_args, _context) do
    {:error, "spawn_task requires 'description' and 'prompt' arguments"}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp validate_description(description) do
    cond do
      byte_size(description) == 0 ->
        {:error, "description cannot be empty"}

      byte_size(description) > 200 ->
        {:error, "description must be 200 characters or less"}

      true ->
        :ok
    end
  end

  defp validate_prompt(prompt) do
    cond do
      byte_size(prompt) == 0 ->
        {:error, "prompt cannot be empty"}

      byte_size(prompt) > 10_000 ->
        {:error, "prompt must be 10000 characters or less"}

      true ->
        :ok
    end
  end

  defp parse_timeout(args) do
    timeout = Map.get(args, "timeout", @default_timeout)

    cond do
      not is_integer(timeout) ->
        {:error, "timeout must be an integer"}

      timeout < 1000 ->
        {:error, "timeout must be at least 1000ms"}

      timeout > @max_timeout ->
        {:ok, @max_timeout}

      true ->
        {:ok, timeout}
    end
  end

  defp generate_task_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
    |> then(&"task_#{&1}")
  end

  defp build_agent_spec(task_id, description, prompt, args, context) do
    base_spec = [
      task_id: task_id,
      description: description,
      prompt: prompt,
      timeout: Map.get(args, "timeout", @default_timeout)
    ]

    # Add optional model override
    spec =
      if model = Map.get(args, "model") do
        Keyword.put(base_spec, :model, model)
      else
        base_spec
      end

    # Add session context if available
    if session_id = Map.get(context, :session_id) do
      Keyword.put(spec, :session_id, session_id)
    else
      spec
    end
  end

  defp execute_task(task_id, agent_spec, timeout) do
    # Generate unique agent name
    agent_name = String.to_atom(task_id)

    # Start agent via supervisor
    case start_task_agent(agent_name, agent_spec) do
      {:ok, pid} ->
        # Execute and wait for result
        result = run_with_cleanup(pid, agent_name, timeout)

        # Emit telemetry
        emit_telemetry(task_id, result)

        result

      {:error, reason} ->
        Logger.error("Failed to start TaskAgent #{task_id}: #{inspect(reason)}")
        {:error, "Failed to spawn task agent: #{inspect(reason)}"}
    end
  end

  defp start_task_agent(agent_name, agent_spec) do
    AgentSupervisor.start_agent(%{
      name: agent_name,
      module: TaskAgent,
      args: agent_spec
    })
  end

  defp run_with_cleanup(pid, agent_name, timeout) do
    try do
      TaskAgent.execute(pid, timeout: timeout)
    after
      # Clean up agent after execution
      cleanup_agent(agent_name)
    end
  end

  defp cleanup_agent(agent_name) do
    case AgentSupervisor.stop_agent(agent_name) do
      :ok ->
        :ok

      {:error, :not_found} ->
        # Agent already stopped or never started properly
        :ok

      {:error, reason} ->
        Logger.warning("Failed to cleanup TaskAgent #{agent_name}: #{inspect(reason)}")
        :ok
    end
  end

  defp emit_telemetry(task_id, result) do
    success = match?({:ok, _}, result)

    :telemetry.execute(
      [:jido_code, :tools, :spawn_task],
      %{system_time: System.system_time()},
      %{task_id: task_id, success: success}
    )
  end
end
