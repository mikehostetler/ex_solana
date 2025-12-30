defmodule Jido.AI.ToolSpec do
  @moduledoc """
  Converts Jido Actions into schema-only tool specifications for LLM consumption.

  This module lives in jido_ai (which depends on ReqLLM) and builds ReqLLM.Tool
  structs that contain only schema information—no execution callbacks.

  ## Dependency Tree

      req_llm (no deps)
           ↓
      jido_ai (depends on req_llm)  ← THIS MODULE
           ↓
      jido (depends on jido_ai)
           ↓
      jido_action, jido_signal (depend on jido)

  ## Design

  - **Schema-only**: Tools have `callback: nil`; Jido owns execution via `Directive.ToolExec`
  - **No jido_action coupling**: Uses only `Jido.Action` behaviour callbacks (name/0, description/0, schema/0)
  - **Consistent with ReAct**: Tools are descriptions for the model, not execution entry points

  ## Usage

      # Convert action modules to ReqLLM tools
      tools = Jido.AI.ToolSpec.from_actions([
        MyApp.Actions.Calculator,
        MyApp.Actions.Search
      ])

      # Use in LLM call
      ReqLLM.stream_text(model, messages, tools: tools)
  """

  @doc """
  Converts a list of Jido.Action modules into schema-only ReqLLM.Tool structs.

  The returned tools have no callbacks—they're purely for describing available
  actions to the LLM. Actual execution happens via `Jido.AI.Directive.ToolExec`.

  ## Arguments

    * `action_modules` - List of modules implementing the `Jido.Action` behaviour

  ## Returns

    A list of `ReqLLM.Tool` structs with `callback: nil`

  ## Example

      iex> tools = Jido.AI.ToolSpec.from_actions([MyApp.Actions.Add, MyApp.Actions.Search])
      [%ReqLLM.Tool{name: "add", callback: nil, ...}, ...]

  """
  @spec from_actions([module()]) :: [ReqLLM.Tool.t()]
  def from_actions(action_modules) when is_list(action_modules) do
    Enum.map(action_modules, &from_action/1)
  end

  @doc """
  Converts a single Jido.Action module into a schema-only ReqLLM.Tool struct.

  ## Arguments

    * `action_module` - A module implementing the `Jido.Action` behaviour

  ## Returns

    A `ReqLLM.Tool` struct with `callback: nil`
  """
  @spec from_action(module()) :: ReqLLM.Tool.t()
  def from_action(action_module) when is_atom(action_module) do
    ReqLLM.Tool.new!(
      name: action_module.name(),
      description: action_module.description(),
      parameter_schema: build_json_schema(action_module.schema()),
      callback: nil
    )
  end

  defp build_json_schema(schema) do
    Jido.Action.Schema.to_json_schema(schema)
  end
end
