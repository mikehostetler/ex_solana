# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Builder do
  @moduledoc false

  alias AshAi.Tool

  @type tool_def :: AshAi.Tool.t()
  @type opts :: %{
          optional(:actor) => any(),
          optional(:tenant) => any(),
          optional(:context) => map(),
          optional(:tool_callbacks) => map()
        }

  @doc """
  Build a {ReqLLM.Tool, callback} tuple from an AshAi.Tool DSL definition.

  The callback is a function/2 that takes (arguments, context) and delegates
  to AshAi.Tool.Execution.run/4.
  """
  @spec build(tool_def(), opts()) :: {ReqLLM.Tool.t(), function()}
  def build(%Tool{} = tool_def, _opts \\ %{}) do
    name = to_string(tool_def.name)
    description = build_description(tool_def)
    parameter_schema = build_parameter_schema(tool_def)
    callback = build_callback(tool_def, name)

    tool = build_req_llm_tool(name, description, parameter_schema)

    {tool, callback}
  end

  defp build_description(%Tool{description: description, action: action, resource: resource}) do
    String.trim(
      description || action.description ||
        "Call the #{action.name} action on the #{inspect(resource)} resource"
    )
  end

  defp build_parameter_schema(%Tool{
         resource: resource,
         action: action,
         action_parameters: action_parameters
       }) do
    Tool.Schema.for_action(resource, action, nil, action_parameters: action_parameters)
  end

  defp build_callback(%Tool{} = tool_def, name) do
    fn arguments, context ->
      callbacks = context[:tool_callbacks] || %{}

      if on_start = callbacks[:on_tool_start] do
        on_start.(%AshAi.ToolStartEvent{
          tool_name: name,
          action: tool_def.action.name,
          resource: tool_def.resource,
          arguments: arguments,
          actor: context[:actor],
          tenant: context[:tenant]
        })
      end

      exec_ctx = %{
        actor: context[:actor],
        tenant: context[:tenant],
        context: context[:context] || %{},
        tool_callbacks: callbacks,
        load: tool_def.load,
        identity: tool_def.identity,
        domain: tool_def.domain
      }

      result = Tool.Execution.run(tool_def.resource, tool_def.action, arguments, exec_ctx)

      if on_end = callbacks[:on_tool_end] do
        on_end.(%AshAi.ToolEndEvent{
          tool_name: name,
          result: result
        })
      end

      result
    end
  end

  defp build_req_llm_tool(name, description, parameter_schema) do
    ReqLLM.Tool.new!(
      name: name,
      description: description,
      parameter_schema: parameter_schema,
      callback: fn _args -> {:ok, "stub - should not be called"} end
    )
  end
end
