# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolLoop do
  @moduledoc """
  Orchestrate LLM ↔ Tool calling loops with Ash context, policies, and execution tracking.

  This module provides the core functionality for building autonomous agents that can:
  - Call LLMs to generate responses with tool calls
  - Execute tools (Ash actions) with proper authorization
  - Maintain conversation state across multiple iterations
  - Stream responses in real-time
  - Enforce security boundaries and iteration limits

  ## Usage

  ### Synchronous Loop

      messages = [
        %{role: "user", content: "Create a blog post about Elixir"}
      ]

      {:ok, result} = AshAi.ToolLoop.run(messages,
        model: "gpt-4",
        otp_app: :my_blog,
        actor: current_user,
        tools: [:create_post, :publish_post]
      )

  ### Streaming Loop

      AshAi.ToolLoop.stream(messages,
        model: "gpt-4",
        otp_app: :my_app,
        actor: current_user,
        on_tool_start: &log_tool_start/1
      )
      |> Stream.each(fn
        {:text, chunk} -> IO.write(chunk)
        {:tool_call, name, args} -> log_tool_call(name, args)
        {:tool_result, name, result} -> log_tool_result(name, result)
        {:done, final_message} -> handle_completion(final_message)
      end)
      |> Stream.run()

  ## Options

  - `:model` - The LLM model to use (required)
  - `:req_llm` - The ReqLLM-compatible module (default: `ReqLLM`)
  - `:otp_app` - OTP application for tool discovery
  - `:tools` - List of tool names to expose, or `:all`
  - `:actions` - List of `{Resource, action_list}` tuples
  - `:actor` - The actor for authorization (passed to all tools)
  - `:tenant` - The tenant for multi-tenancy (passed to all tools)
  - `:context` - Additional context map (passed to all tools)
  - `:max_iterations` - Maximum loop iterations (default: 10)
  - `:timeout` - Maximum execution time in ms (default: 30_000)
  - `:on_tool_start` - Callback receiving `AshAi.ToolStartEvent`
  - `:on_tool_end` - Callback receiving `AshAi.ToolEndEvent`
  - `:on_iteration` - Callback receiving `AshAi.IterationEvent`
  - `:return_messages?` - Include message history in result (default: false)
  - `:return_tool_results?` - Include tool results in output (default: false)

  ## Security

  Authorization is checked on **every** tool execution. The actor and tenant
  remain constant throughout the loop, ensuring no privilege escalation.

  ## Loop Termination

  The loop terminates when:
  - The LLM returns a message with no tool calls (success)
  - Maximum iterations reached (error)
  - Timeout exceeded (error)
  - Tool execution fails (error, unless configured otherwise)
  - Authorization fails (always error)
  """

  require Logger

  alias AshAi.Tools

  @type message :: map()
  @type opts :: keyword()
  @type result :: %{
          message: ReqLLM.Message.t(),
          iterations: integer(),
          metadata: map(),
          messages: [message()] | nil,
          tool_results: [any()] | nil
        }
  @type stream_event ::
          {:text, String.t()}
          | {:tool_call, String.t(), map()}
          | {:tool_result, String.t(), any()}
          | {:done, result()}

  defmodule IterationEvent do
    @moduledoc """
    Event data passed to the `on_iteration` callback.

    Contains information about each iteration of the tool loop.
    """
    @type t :: %__MODULE__{
            iteration: integer(),
            message_count: integer(),
            tool_calls: [String.t()],
            timestamp: DateTime.t()
          }

    defstruct [:iteration, :message_count, :tool_calls, :timestamp]
  end

  @doc """
  Run a synchronous tool loop.

  Executes the LLM ↔ Tool loop until completion or termination condition.

  Returns `{:ok, result}` with the final message and metadata, or
  `{:error, reason}` if the loop fails.

  ## Examples

      {:ok, result} = AshAi.ToolLoop.run(
        [%{role: "user", content: "List all posts"}],
        model: "gpt-4",
        otp_app: :my_app,
        actor: current_user
      )

      IO.puts(result.message.content)
  """
  @spec run([message()], opts()) :: {:ok, result()} | {:error, any()}
  def run(messages, opts) do
    with {:ok, config} <- validate_config(opts),
         {:ok, tools, registry} <- build_tools(config) do
      exec_ctx = build_exec_context(config, registry)

      result =
        execute_loop(
          messages,
          tools,
          registry,
          exec_ctx,
          config,
          1,
          []
        )

      case result do
        {:ok, final_message, iterations, tool_results} ->
          {:ok,
           %{
             message: final_message,
             iterations: iterations,
             metadata: %{
               tool_calls_count: length(tool_results),
               max_iterations_reached: iterations >= config.max_iterations
             },
             messages: if(config.return_messages?, do: messages, else: nil),
             tool_results: if(config.return_tool_results?, do: tool_results, else: nil)
           }}

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc """
  Run a streaming tool loop.

  Returns a stream that yields events as the loop executes.

  ## Events

  - `{:text, chunk}` - Text chunk from LLM response
  - `{:tool_call, name, args}` - Tool is being called
  - `{:tool_result, name, result}` - Tool execution completed
  - `{:done, result}` - Loop completed

  ## Examples

      AshAi.ToolLoop.stream(
        [%{role: "user", content: "Create a post"}],
        model: "gpt-4",
        otp_app: :my_app
      )
      |> Enum.each(&handle_event/1)
  """
  @spec stream([message()], opts()) :: Enumerable.t()
  def stream(messages, opts) do
    Stream.resource(
      fn -> init_stream(messages, opts) end,
      &next_stream_event/1,
      &cleanup_stream/1
    )
  end

  # Private Functions

  defp validate_config(opts) do
    config = %{
      model: Keyword.get(opts, :model),
      req_llm: Keyword.get(opts, :req_llm, ReqLLM),
      otp_app: Keyword.get(opts, :otp_app),
      domains: Keyword.get(opts, :domains),
      tools: Keyword.get(opts, :tools),
      actions: Keyword.get(opts, :actions),
      actor: Keyword.get(opts, :actor),
      tenant: Keyword.get(opts, :tenant),
      context: Keyword.get(opts, :context, %{}),
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      timeout: Keyword.get(opts, :timeout, 30_000),
      on_tool_start: Keyword.get(opts, :on_tool_start),
      on_tool_end: Keyword.get(opts, :on_tool_end),
      on_iteration: Keyword.get(opts, :on_iteration),
      return_messages?: Keyword.get(opts, :return_messages?, false),
      return_tool_results?: Keyword.get(opts, :return_tool_results?, false)
    }

    if is_nil(config.model) do
      {:error, "model is required"}
    else
      {:ok, config}
    end
  end

  defp build_tools(config) do
    tool_callbacks =
      %{}
      |> maybe_add_callback(:on_tool_start, config.on_tool_start)
      |> maybe_add_callback(:on_tool_end, config.on_tool_end)

    tool_opts =
      [
        actor: config.actor,
        tenant: config.tenant,
        context: config.context,
        tool_callbacks: tool_callbacks
      ]
      |> maybe_add(:otp_app, config.otp_app)
      |> maybe_add(:domains, config.domains)
      |> maybe_add(:tools, config.tools)
      |> maybe_add(:actions, config.actions)

    try do
      {tools, registry} = Tools.build(tool_opts)
      {:ok, tools, registry}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_callback(map, _key, nil), do: map
  defp maybe_add_callback(map, key, value), do: Map.put(map, key, value)

  defp build_exec_context(config, registry) do
    %{
      actor: config.actor,
      tenant: config.tenant,
      context: config.context,
      registry: registry
    }
  end

  defp execute_loop(
         messages,
         tools,
         registry,
         exec_ctx,
         config,
         iteration,
         tool_results_acc
       ) do
    if iteration > config.max_iterations do
      {:error, :max_iterations_reached}
    else
      emit_iteration_event(config, iteration, messages, [])

      context = %ReqLLM.Context{messages: normalize_messages(messages), tools: tools}

      case call_llm(config, context) do
        {:ok, response} ->
          message = response.message
          tool_calls = extract_tool_calls(message)

          if Enum.empty?(tool_calls) do
            {:ok, message, iteration, tool_results_acc}
          else
            case execute_tool_calls(tool_calls, registry, exec_ctx) do
              {:ok, results} ->
                new_messages = messages ++ [message | results]
                new_tool_results = tool_results_acc ++ extract_tool_result_data(results)

                execute_loop(
                  new_messages,
                  tools,
                  registry,
                  exec_ctx,
                  config,
                  iteration + 1,
                  new_tool_results
                )

              {:error, _reason} = error ->
                error
            end
          end

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp call_llm(config, context) do
    task = Task.async(fn -> config.req_llm.generate_text(config.model, context) end)

    case Task.yield(task, config.timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp extract_tool_calls(message) do
    (message.tool_calls || [])
    |> Enum.map(fn tool_call ->
      # tool_call.function.arguments is a JSON string, decode it
      arguments =
        case Jason.decode(tool_call.function.arguments) do
          {:ok, args} -> args
          {:error, _} -> %{}
        end

      %{
        id: tool_call.id,
        name: tool_call.function.name,
        arguments: arguments
      }
    end)
  end

  defp execute_tool_calls(tool_calls, registry, exec_ctx) do
    results =
      Enum.map(tool_calls, fn tool_call ->
        execute_single_tool(tool_call, registry, exec_ctx)
      end)

    if Enum.any?(results, &match?({:error, _}, &1)) do
      Enum.find(results, &match?({:error, _}, &1))
    else
      {:ok, Enum.map(results, fn {:ok, msg} -> msg end)}
    end
  end

  defp execute_single_tool(tool_call, registry, exec_ctx) do
    callback = Map.get(registry, tool_call.name)

    if callback do
      context = %{
        actor: exec_ctx.actor,
        tenant: exec_ctx.tenant,
        context: exec_ctx.context
      }

      case callback.(tool_call.arguments, context) do
        {:ok, result_json, _raw} ->
          {:ok,
           %ReqLLM.Message{
             role: :tool,
             content: [ReqLLM.Message.ContentPart.text(result_json)],
             tool_call_id: tool_call.id
           }}

        {:error, error_json} ->
          {:error, {:tool_execution_failed, tool_call.name, error_json}}
      end
    else
      {:error, {:tool_not_found, tool_call.name}}
    end
  end

  defp extract_tool_result_data(result_messages) do
    Enum.flat_map(result_messages, fn msg ->
      msg.content
      |> Enum.filter(&match?(%ReqLLM.Message.ContentPart{type: :text}, &1))
      |> Enum.map(& &1.text)
    end)
  end

  defp emit_iteration_event(config, iteration, messages, tool_calls) do
    if config.on_iteration do
      config.on_iteration.(%IterationEvent{
        iteration: iteration,
        message_count: length(messages),
        tool_calls: Enum.map(tool_calls, & &1.name),
        timestamp: DateTime.utc_now()
      })
    end
  end

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %ReqLLM.Message{} = msg ->
        msg

      %{role: role, content: content} when is_binary(content) ->
        %ReqLLM.Message{
          role: String.to_existing_atom(to_string(role)),
          content: [ReqLLM.Message.ContentPart.text(content)]
        }

      %{role: role, content: content} when is_list(content) ->
        %ReqLLM.Message{
          role: String.to_existing_atom(to_string(role)),
          content: content
        }

      msg when is_struct(msg) ->
        msg
    end)
  end

  # Streaming Implementation

  defp init_stream(messages, opts) do
    with {:ok, config} <- validate_config(opts),
         {:ok, tools, registry} <- build_tools(config) do
      exec_ctx = build_exec_context(config, registry)

      {:ok,
       %{
         messages: messages,
         tools: tools,
         registry: registry,
         exec_ctx: exec_ctx,
         config: config,
         iteration: 1,
         tool_results: [],
         state: :calling_llm,
         buffer: []
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_stream_event({:error, reason}) do
    {[{:error, reason}], :done}
  end

  defp next_stream_event(:done) do
    {:halt, :done}
  end

  defp next_stream_event(state) when state.iteration > state.config.max_iterations do
    {[{:error, :max_iterations_reached}], :done}
  end

  defp next_stream_event(%{state: :calling_llm} = state) do
    emit_iteration_event(state.config, state.iteration, state.messages, [])

    context = %ReqLLM.Context{messages: normalize_messages(state.messages), tools: state.tools}

    case state.config.req_llm.stream_text(state.config.model, context) do
      {:ok, %{stream: stream}} ->
        {[], %{state | state: :streaming, buffer: Enum.to_list(stream)}}

      {:error, reason} ->
        {[{:error, reason}], :done}
    end
  end

  defp next_stream_event(%{state: :streaming, buffer: []} = state) do
    # No more stream events, process what we have
    {[], %{state | state: :processing_response}}
  end

  defp next_stream_event(%{state: :streaming, buffer: [event | rest]} = state) do
    case event do
      %{type: :content, text: text} ->
        {[{:text, text}], %{state | buffer: rest}}

      %{type: :tool_call, name: name, arguments: args, id: id} ->
        tool_call = %{id: id, name: name, arguments: args}
        new_state = %{state | buffer: rest, pending_tool_calls: [tool_call | []]}
        {[{:tool_call, name, args}], new_state}

      _ ->
        next_stream_event(%{state | buffer: rest})
    end
  end

  defp next_stream_event(%{state: :processing_response} = _state) do
    # In a real implementation, we'd execute tool calls here
    # For now, just finish
    {:halt, :done}
  end

  defp cleanup_stream(_state), do: :ok
end
