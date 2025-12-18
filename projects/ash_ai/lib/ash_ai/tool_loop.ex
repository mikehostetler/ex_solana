# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.ToolLoop do
  @moduledoc """
  Manages the LLM conversation loop with tool calls.

  This module provides a clean API for running conversations with LLMs
  that can call tools. It handles the loop of:
  1. Sending messages to the LLM
  2. Processing tool calls from the LLM
  3. Executing tools and collecting results
  4. Continuing the conversation with tool results

  ## Usage

      # Build messages
      messages = [ReqLLM.Context.system("You are a helpful assistant.")]
      
      # Run the loop (blocking)
      {:ok, result} = AshAi.ToolLoop.run(messages, opts)
      
      # Or stream events
      stream = AshAi.ToolLoop.stream(messages, opts)
      for event <- stream, do: handle_event(event)
  """

  alias ReqLLM.Context

  defmodule IterationEvent do
    @moduledoc """
    Event emitted at the start of each iteration in the tool loop.
    """
    defstruct [:iteration, :messages_count, :tool_calls_count]
  end

  defmodule Result do
    @moduledoc """
    Result returned from a completed tool loop.
    """
    defstruct [:messages, :final_text, :iterations, :tool_calls_made]
  end

  @doc """
  Runs the tool loop synchronously.

  Returns `{:ok, %Result{}}` on success or `{:error, reason}` on failure.

  ## Options

  - `:model` - The model to use (required, e.g., "openai:gpt-4o-mini")
  - `:req_llm` - The ReqLLM module to use (default: ReqLLM)
  - `:max_iterations` - Maximum number of iterations (default: 10)
  - `:actor` - The actor performing actions
  - `:tenant` - The tenant context
  - `:context` - Additional context for actions
  - `:on_tool_start` - Callback when a tool starts
  - `:on_tool_end` - Callback when a tool ends
  - `:otp_app` - OTP app for discovering tools
  - `:actions` - List of {Resource, actions} tuples
  """
  def run(messages, opts) do
    opts = AshAi.Options.validate!(opts)
    model = opts.model
    req_llm = opts.req_llm
    max_iterations = opts.max_iterations

    {tools, registry} = AshAi.Tools.build_tools_and_registry(opts)
    context = build_context(opts)

    run_loop(req_llm, model, messages, tools, registry, context, opts, 1, max_iterations, [])
  end

  @doc """
  Streams events from the tool loop.

  Returns a Stream that yields events as they occur:
  - `{:content, text}` - Text content from the LLM
  - `{:tool_call, %{id: id, name: name, arguments: args}}` - Tool call from LLM
  - `{:tool_result, %{id: id, result: result}}` - Result of tool execution
  - `{:iteration, %IterationEvent{}}` - Start of a new iteration
  - `{:done, %Result{}}` - Conversation complete

  ## Options

  Same as `run/2`.
  """
  def stream(messages, opts) do
    Stream.resource(
      fn -> init_stream(messages, opts) end,
      &next_stream_chunk/1,
      &cleanup_stream/1
    )
  end

  defp init_stream(messages, opts) do
    opts = AshAi.Options.validate!(opts)
    model = opts.model
    req_llm = opts.req_llm

    {tools, registry} = AshAi.Tools.build_tools_and_registry(opts)
    context = build_context(opts)

    %{
      req_llm: req_llm,
      model: model,
      messages: messages,
      tools: tools,
      registry: registry,
      context: context,
      iteration: 1,
      max_iterations: opts.max_iterations,
      tool_calls_made: [],
      state: :running
    }
  end

  defp next_stream_chunk(%{state: :done} = state) do
    {:halt, state}
  end

  defp next_stream_chunk(state) do
    case stream_iteration(state) do
      {:continue, events, new_state} ->
        {events, new_state}

      {:done, events, result} ->
        {events ++ [{:done, result}], %{state | state: :done}}
    end
  end

  defp cleanup_stream(_state), do: :ok

  defp stream_iteration(state) do
    %{
      req_llm: req_llm,
      model: model,
      messages: messages,
      tools: tools,
      registry: registry,
      context: context,
      iteration: iteration,
      max_iterations: max_iterations,
      tool_calls_made: tool_calls_made
    } = state

    if iteration > max_iterations do
      result = %Result{
        messages: messages,
        final_text: "",
        iterations: iteration - 1,
        tool_calls_made: tool_calls_made
      }

      {:done, [{:error, :max_iterations_reached}], result}
    else
      {:ok, response} = req_llm.stream_text(model, messages, tools: tools)

      {text, tool_calls, events} = collect_stream(response.stream)

      if tool_calls != [] do
        tool_call_tuples =
          Enum.map(tool_calls, fn tc ->
            {tc.name, tc.arguments, id: tc.id}
          end)

        assistant_with_tools = Context.assistant("", tool_calls: tool_call_tuples)

        messages = messages ++ [assistant_with_tools]

        {messages, tool_events} = run_tools_streaming(tool_calls, messages, registry, context)

        new_state = %{
          state
          | messages: messages,
            iteration: iteration + 1,
            tool_calls_made: tool_calls_made ++ tool_calls
        }

        {:continue,
         events ++ tool_events ++ [{:iteration, %IterationEvent{iteration: iteration + 1}}],
         new_state}
      else
        messages =
          if text != "" do
            messages ++ [Context.assistant(text)]
          else
            messages
          end

        result = %Result{
          messages: messages,
          final_text: text,
          iterations: iteration,
          tool_calls_made: tool_calls_made
        }

        {:done, events, result}
      end
    end
  end

  defp collect_stream(stream) do
    # Track tool calls by index, accumulate argument fragments separately
    acc = %{text: "", tool_calls: %{}, tool_arg_fragments: %{}, events: []}

    acc =
      Enum.reduce(stream, acc, fn chunk, acc ->
        case chunk.type do
          :content ->
            text = chunk.text || ""
            event = {:content, text}

            %{
              acc
              | text: acc.text <> text,
                events: acc.events ++ [event]
            }

          :tool_call ->
            tool_id = chunk.metadata[:id] || chunk.metadata[:call_id] || generate_tool_id()
            index = chunk.metadata[:index] || 0
            tc = %{id: tool_id, name: chunk.name, index: index}

            %{
              acc
              | tool_calls: Map.put(acc.tool_calls, index, tc)
            }

          :meta ->
            case chunk.metadata do
              %{tool_call_args: %{index: index, fragment: fragment}} ->
                existing = Map.get(acc.tool_arg_fragments, index, "")

                %{
                  acc
                  | tool_arg_fragments:
                      Map.put(acc.tool_arg_fragments, index, existing <> fragment)
                }

              _ ->
                acc
            end

          _ ->
            acc
        end
      end)

    # Merge accumulated fragments into tool calls and emit events
    tool_calls =
      acc.tool_calls
      |> Enum.sort_by(fn {index, _tc} -> index end)
      |> Enum.map(fn {index, tc} ->
        arg_json = Map.get(acc.tool_arg_fragments, index, "{}")

        arguments =
          case Jason.decode(arg_json) do
            {:ok, parsed} -> parsed
            {:error, _} -> %{}
          end

        %{id: tc.id, name: tc.name, arguments: arguments}
      end)

    # Generate events for each completed tool call
    tool_call_events = Enum.map(tool_calls, fn tc -> {:tool_call, tc} end)

    {acc.text, tool_calls, acc.events ++ tool_call_events}
  end

  defp run_tools_streaming(tool_calls, messages, registry, ctx) do
    {messages, events} =
      Enum.reduce(tool_calls, {messages, []}, fn tc, {msgs, evts} ->
        fun = Map.get(registry, tc.name)

        {result, event} =
          if is_nil(fun) do
            content = Jason.encode!(%{error: "Unknown tool: #{tc.name}"})
            {{:error, content}, {:tool_result, %{id: tc.id, error: "Unknown tool"}}}
          else
            args =
              case tc.arguments do
                s when is_binary(s) -> Jason.decode!(s)
                m -> m
              end

            result =
              try do
                fun.(args, ctx)
              rescue
                e ->
                  {:error, Jason.encode!(%{error: Exception.message(e)})}
              end

            content =
              case result do
                {:ok, content, _raw} -> content
                {:error, content} -> content
              end

            {{:ok, content}, {:tool_result, %{id: tc.id, result: result}}}
          end

        content =
          case result do
            {:ok, c} -> c
            {:error, c} -> c
          end

        {msgs ++ [Context.tool_result(tc.id, content)], evts ++ [event]}
      end)

    {messages, events}
  end

  defp build_context(opts) do
    %{
      actor: opts.actor,
      tenant: opts.tenant,
      context: opts.context || %{},
      tool_callbacks: %{
        on_tool_start: opts.on_tool_start,
        on_tool_end: opts.on_tool_end
      }
    }
  end

  defp run_loop(
         req_llm,
         model,
         messages,
         tools,
         registry,
         context,
         opts,
         iteration,
         max,
         tool_calls_made
       ) do
    if iteration > max do
      {:error, :max_iterations_reached}
    else
      {:ok, response} = req_llm.stream_text(model, messages, tools: tools)

      acc = %{text: "", tool_calls: %{}, tool_arg_fragments: %{}}

      acc =
        response.stream
        |> Enum.reduce(acc, fn chunk, acc ->
          case chunk.type do
            :content ->
              text = chunk.text || ""
              %{acc | text: acc.text <> text}

            :tool_call ->
              tool_id = chunk.metadata[:id] || chunk.metadata[:call_id] || generate_tool_id()
              index = chunk.metadata[:index] || 0
              tc = %{id: tool_id, name: chunk.name, index: index}
              %{acc | tool_calls: Map.put(acc.tool_calls, index, tc)}

            :meta ->
              case chunk.metadata do
                %{tool_call_args: %{index: index, fragment: fragment}} ->
                  existing = Map.get(acc.tool_arg_fragments, index, "")

                  %{
                    acc
                    | tool_arg_fragments:
                        Map.put(acc.tool_arg_fragments, index, existing <> fragment)
                  }

                _ ->
                  acc
              end

            _ ->
              acc
          end
        end)

      # Merge accumulated fragments into tool calls
      tool_calls =
        acc.tool_calls
        |> Enum.map(fn {index, tc} ->
          arg_json = Map.get(acc.tool_arg_fragments, index, "{}")

          arguments =
            case Jason.decode(arg_json) do
              {:ok, parsed} -> parsed
              {:error, _} -> %{}
            end

          %{id: tc.id, name: tc.name, arguments: arguments}
        end)

      if tool_calls != [] do
        tool_call_tuples =
          Enum.map(tool_calls, fn tc ->
            {tc.name, tc.arguments, id: tc.id}
          end)

        assistant_with_tools = Context.assistant("", tool_calls: tool_call_tuples)

        messages = messages ++ [assistant_with_tools]
        messages = run_tools(tool_calls, messages, registry, context)

        run_loop(
          req_llm,
          model,
          messages,
          tools,
          registry,
          context,
          opts,
          iteration + 1,
          max,
          tool_calls_made ++ tool_calls
        )
      else
        messages =
          if acc.text != "" do
            messages ++ [Context.assistant(acc.text)]
          else
            messages
          end

        {:ok,
         %Result{
           messages: messages,
           final_text: acc.text,
           iterations: iteration,
           tool_calls_made: tool_calls_made
         }}
      end
    end
  end

  defp run_tools(tool_calls, messages, registry, ctx) do
    Enum.reduce(tool_calls, messages, fn tc, msgs ->
      fun = Map.get(registry, tc.name)

      if is_nil(fun) do
        msgs ++ [Context.tool_result(tc.id, Jason.encode!(%{error: "Unknown tool: #{tc.name}"}))]
      else
        args =
          case tc.arguments do
            s when is_binary(s) -> Jason.decode!(s)
            m -> m
          end

        result =
          try do
            fun.(args, ctx)
          rescue
            e ->
              {:error, Jason.encode!(%{error: Exception.message(e)})}
          end

        content =
          case result do
            {:ok, content, _raw} -> content
            {:error, content} -> content
          end

        msgs ++ [Context.tool_result(tc.id, content)]
      end
    end)
  end

  defp generate_tool_id do
    "call_#{:erlang.unique_integer([:positive])}"
  end
end
