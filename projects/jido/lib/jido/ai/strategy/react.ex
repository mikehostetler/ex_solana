defmodule Jido.AI.Strategy.ReAct do
  @moduledoc """
  Generic ReAct (Reason-Act) execution strategy for Jido agents.

  This strategy implements a multi-step reasoning loop:
  1. User query arrives → Start LLM call with tools
  2. LLM response → Either tool calls or final answer
  3. Tool results → Continue with next LLM call
  4. Repeat until final answer or max iterations

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_react_agent",
        strategy: {
          Jido.AI.Strategy.ReAct,
          tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
          system_prompt: "You are a helpful assistant...",
          model: "anthropic:claude-haiku-4-5",
          max_iterations: 10
        }

  ### Options

  - `:tools` (required) - List of Jido.Action modules to use as tools
  - `:system_prompt` (optional) - Custom system prompt for the LLM
  - `:model` (optional) - Model identifier, defaults to agent's `:model` state or "anthropic:claude-haiku-4-5"
  - `:max_iterations` (optional) - Maximum reasoning iterations, defaults to 10

  ## Signal Routing

  Agents using this strategy should route signals to these actions:

      alias Jido.AI.Strategy.ReAct, as: ReActStrategy

      def handle_signal(agent, %Jido.Signal{type: "react.user_query", data: data}) do
        cmd(agent, {ReActStrategy.start_action(), data})
      end

      def handle_signal(agent, %Jido.Signal{type: "ai.llm_result", data: data}) do
        cmd(agent, {ReActStrategy.llm_result_action(), data})
      end

      def handle_signal(agent, %Jido.Signal{type: "ai.tool_result", data: data}) do
        cmd(agent, {ReActStrategy.tool_result_action(), data})
      end

  ## State

  State is stored under `agent.state.__strategy__` with the following shape:

      %{
        status: :idle | :awaiting_llm | :awaiting_tool | :completed | :error,
        iteration: non_neg_integer(),
        conversation: [ReqLLM.Message.t()],
        pending_tool_calls: [%{id: String.t(), name: String.t(), arguments: map(), result: term()}],
        final_answer: String.t() | nil,
        current_llm_call_id: String.t() | nil,
        termination_reason: :final_answer | :max_iterations | :error | nil,
        config: config()
      }
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.{Directive, LLMBackend, LLMContext, ToolSpec}

  @type config :: %{
          tools: [module()],
          reqllm_tools: [ReqLLM.Tool.t()],
          actions_by_name: %{String.t() => module()},
          system_prompt: String.t(),
          model: String.t(),
          max_iterations: pos_integer()
        }

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10

  @start :react_start
  @llm_result :react_llm_result
  @tool_result :react_tool_result

  @doc "Returns the action atom for starting a ReAct conversation."
  @spec start_action() :: :react_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :react_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling tool results."
  @spec tool_result_action() :: :react_tool_result
  def tool_result_action, do: @tool_result

  @impl true
  def action_spec(@start) do
    %{
      schema: Zoi.object(%{query: Zoi.string()}),
      doc: "Start a new ReAct conversation with a user query",
      name: "react.start"
    }
  end

  def action_spec(@llm_result) do
    %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response (tool calls or final answer)",
      name: "react.llm_result"
    }
  end

  def action_spec(@tool_result) do
    %{
      schema: Zoi.object(%{call_id: Zoi.string(), tool_name: Zoi.string(), result: Zoi.any()}),
      doc: "Handle tool execution result",
      name: "react.tool_result"
    }
  end

  def action_spec(_), do: nil

  @impl true
  def signal_routes(_ctx) do
    [
      {"react.user_query", {:strategy_cmd, @start}},
      {"ai.llm_result", {:strategy_cmd, @llm_result}},
      {"ai.tool_result", {:strategy_cmd, @tool_result}}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})

    status =
      case state[:status] do
        :completed -> :success
        :error -> :failure
        :idle -> :idle
        _ -> :running
      end

    done? = status in [:success, :failure]

    %Jido.Agent.Strategy.Public{
      status: status,
      done?: done?,
      result: state[:result],
      meta:
        %{
          phase: state[:status],
          iteration: state[:iteration],
          termination_reason: state[:termination_reason]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    }
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)

    state = %{
      status: :idle,
      iteration: 0,
      conversation: [],
      pending_tool_calls: [],
      result: nil,
      current_llm_call_id: nil,
      termination_reason: nil,
      config: config
    }

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    Enum.reduce(instructions, {agent, []}, fn instr, {acc_agent, acc_dirs} ->
      %Jido.Instruction{action: action, params: params} = instr

      {new_agent, new_dirs} =
        case normalize_action(action) do
          @start -> handle_start(acc_agent, params, ctx)
          @llm_result -> handle_llm_result(acc_agent, params, ctx)
          @tool_result -> handle_tool_result(acc_agent, params, ctx)
          _other -> {acc_agent, []}
        end

      {new_agent, acc_dirs ++ new_dirs}
    end)
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp get_state(agent), do: StratState.get(agent, %{})
  defp put_state(agent, state), do: StratState.put(agent, state)

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    tools_modules =
      case Keyword.fetch(opts, :tools) do
        {:ok, mods} when is_list(mods) ->
          mods

        :error ->
          raise ArgumentError,
                "Jido.AI.Strategy.ReAct requires :tools option (list of Jido.Action modules)"
      end

    actions_by_name =
      tools_modules
      |> Enum.map(fn mod -> {mod.name(), mod} end)
      |> Map.new()

    reqllm_tools = ToolSpec.from_actions(tools_modules)

    %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      system_prompt: Keyword.get(opts, :system_prompt, default_system_prompt()),
      model: Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model)),
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations)
    }
  end

  defp default_system_prompt do
    """
    You are a helpful AI assistant using the ReAct (Reason-Act) pattern.
    When you need to perform an action, use the available tools.
    When you have enough information to answer, provide your final answer directly.
    Think step by step and explain your reasoning.
    """
  end

  defp handle_start(agent, %{query: query}, _ctx) do
    state = get_state(agent)
    config = state.config

    system_msg = LLMContext.system_message(config.system_prompt)
    user_msg = LLMContext.user_message(query)

    state =
      state
      |> Map.put(:status, :awaiting_llm)
      |> Map.put(:iteration, 1)
      |> Map.put(:conversation, [system_msg, user_msg])
      |> Map.put(:pending_tool_calls, [])
      |> Map.put(:result, nil)
      |> Map.put(:termination_reason, nil)

    call_id = LLMBackend.generate_call_id()
    state = Map.put(state, :current_llm_call_id, call_id)
    agent = put_state(agent, state)

    directive =
      Directive.LLMStream.new!(%{
        id: call_id,
        model: config.model,
        context: state.conversation,
        tools: config.reqllm_tools
      })

    {agent, [directive]}
  end

  defp handle_llm_result(agent, %{call_id: call_id, result: result}, _ctx) do
    state = get_state(agent)

    if call_id != state.current_llm_call_id do
      {agent, []}
    else
      handle_llm_response(agent, state, result)
    end
  end

  defp handle_llm_response(agent, state, {:error, reason}) do
    state =
      state
      |> Map.put(:status, :error)
      |> Map.put(:termination_reason, :error)
      |> Map.put(:result, "Error: #{inspect(reason)}")

    agent = put_state(agent, state)
    {agent, []}
  end

  defp handle_llm_response(agent, state, {:ok, result}) do
    case result.type do
      :tool_calls -> handle_tool_calls(agent, state, result.tool_calls)
      :final_answer -> handle_final_answer(agent, state, result.text)
    end
  end

  defp handle_tool_calls(agent, state, tool_calls) do
    config = state.config
    assistant_msg = LLMContext.assistant_tool_calls(tool_calls)

    pending =
      Enum.map(tool_calls, fn tc ->
        %{id: tc.id, name: tc.name, arguments: tc.arguments, result: nil}
      end)

    state =
      state
      |> Map.put(:status, :awaiting_tool)
      |> Map.update(:conversation, [assistant_msg], &(&1 ++ [assistant_msg]))
      |> Map.put(:pending_tool_calls, pending)

    agent = put_state(agent, state)

    directives =
      tool_calls
      |> Enum.map(fn tc ->
        case config.actions_by_name[tc.name] do
          nil ->
            nil

          action_module ->
            Directive.ToolExec.new!(%{
              id: tc.id,
              tool_name: tc.name,
              action_module: action_module,
              arguments: tc.arguments
            })
        end
      end)
      |> Enum.reject(&is_nil/1)

    {agent, directives}
  end

  defp handle_final_answer(agent, state, answer) do
    assistant_msg = LLMContext.assistant_message(answer)

    state =
      state
      |> Map.put(:status, :completed)
      |> Map.put(:termination_reason, :final_answer)
      |> Map.update(:conversation, [assistant_msg], &(&1 ++ [assistant_msg]))
      |> Map.put(:result, answer)

    agent = put_state(agent, state)
    {agent, []}
  end

  defp handle_tool_result(agent, %{call_id: call_id, result: result}, _ctx) do
    state = get_state(agent)
    config = state.config

    {state, all_complete?} = record_tool_result(state, call_id, result)

    if all_complete? do
      state =
        state
        |> append_all_tool_results()
        |> inc_iteration()

      cond do
        state.iteration > config.max_iterations ->
          state =
            state
            |> Map.put(:status, :completed)
            |> Map.put(:termination_reason, :max_iterations)
            |> Map.put_new(:result, "Maximum iterations reached without a final answer.")

          agent = put_state(agent, state)
          {agent, []}

        true ->
          call_id = LLMBackend.generate_call_id()
          state = Map.put(state, :current_llm_call_id, call_id)
          agent = put_state(agent, state)

          directive =
            Directive.LLMStream.new!(%{
              id: call_id,
              model: config.model,
              context: state.conversation,
              tools: config.reqllm_tools
            })

          {agent, [directive]}
      end
    else
      agent = put_state(agent, state)
      {agent, []}
    end
  end

  defp record_tool_result(state, call_id, result) do
    pending =
      Enum.map(state.pending_tool_calls, fn tc ->
        if tc.id == call_id, do: %{tc | result: result}, else: tc
      end)

    all_complete? = Enum.all?(pending, &(&1.result != nil))
    {Map.put(state, :pending_tool_calls, pending), all_complete?}
  end

  defp append_all_tool_results(state) do
    tool_msgs = LLMContext.tool_result_messages(state.pending_tool_calls)

    state
    |> Map.put(:status, :awaiting_llm)
    |> Map.update(:conversation, tool_msgs, &(&1 ++ tool_msgs))
    |> Map.put(:pending_tool_calls, [])
  end

  defp inc_iteration(state), do: Map.update!(state, :iteration, &(&1 + 1))
end
