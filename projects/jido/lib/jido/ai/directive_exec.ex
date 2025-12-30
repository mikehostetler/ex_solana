defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMStream do
  @moduledoc """
  DirectiveExec implementation for LLMStream directive.

  Spawns an async task to stream an LLM response and sends the result back
  to the agent as an `ai.llm_result` signal.

  Error handling: If the LLM call raises an exception, the error is caught
  and sent back as an error result to prevent the agent from getting stuck.
  """

  alias Jido.AI.{LLMBackend, Signal}

  def exec(directive, _input_signal, state) do
    %{id: call_id, model: model, context: context, tools: tools} = directive
    agent_pid = self()

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      result =
        try do
          LLMBackend.stream(model, context, tools)
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason)}}
        end

      signal = Signal.llm_result!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ToolExec do
  @moduledoc """
  DirectiveExec implementation for ToolExec directive.

  Spawns an async task to execute a Jido.Action and sends the result back
  to the agent as an `ai.tool_result` signal.

  ## Argument Normalization

  LLM tool calls return arguments with string keys (from JSON). This implementation
  normalizes arguments using the action's schema before execution:
  - Converts string keys to atom keys
  - Parses string numbers to integers/floats based on schema type

  This ensures consistent argument semantics whether tools are called via
  DirectiveExec or any other path.

  ## Error Handling

  If the action raises an exception, the error is caught and sent back as an
  error result to prevent the agent from getting stuck in an awaiting state.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      action_module: action_module,
      arguments: arguments,
      context: context
    } = directive

    agent_pid = self()

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      result =
        try do
          normalized_args = normalize_arguments(action_module, arguments)

          case Jido.Exec.run(action_module, normalized_args, context) do
            {:ok, output} -> {:ok, output}
            {:error, reason} -> {:error, reason}
          end
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason)}}
        end

      signal =
        Signal.tool_result!(%{
          call_id: call_id,
          tool_name: tool_name,
          result: result
        })

      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp normalize_arguments(action_module, arguments) do
    schema = action_module.schema()
    Jido.Action.Tool.convert_params_using_schema(arguments, schema)
  end
end
