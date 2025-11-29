# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Actions.Prompt do
  @prompt_template {"""
                    You are responsible for performing the `<%= @input.action.name %>` action.

                    <%= if @input.action.description do %>
                    # Description
                    <%= @input.action.description %>
                    <% end %>

                    ## Inputs
                    <%= for argument <- @input.action.arguments do %>
                    - <%= argument.name %><%= if argument.description do %>: <%= argument.description %>
                    <% end %>
                    <% end %>
                    """,
                    """
                    # Action Inputs

                    <%= for argument <- @input.action.arguments,
                        {:ok, value} = Ash.ActionInput.fetch_argument(@input, argument.name),
                        {:ok, value} = Ash.Type.dump_to_embedded(argument.type, value, argument.constraints) do %>
                      - <%= argument.name %>: <%= Jason.encode!(value) %>
                    <% end %>
                    """}
  @moduledoc """
  A generic action impl that returns structured outputs from an LLM matching the action return.

  Typically used via `prompt/2`, for example:

  ```elixir
  action :analyze_sentiment, :atom do
    constraints one_of: [:positive, :negative]

    description \"""
    Analyzes the sentiment of a given piece of text to determine if it is overall positive or negative.

    Does not consider swear words as inherently negative.
    \"""

    argument :text, :string do
      allow_nil? false
      description "The text for analysis."
    end

    run prompt(
      "openai:gpt-4o",
      # setting `tools: true` allows it to use all exposed tools in your app
      tools: true
      # alternatively you can restrict it to only a set of tools
      # tools: [:list, :of, :tool, :names]
      # provide an optional prompt, which is an EEx template
      # prompt: "Analyze the sentiment of the following text: <%= @input.arguments.description %>"
    )
  end
  ```

  The first argument to `prompt/2` is the model specification. It can also be a 2-arity function which will be invoked
  with the input and the context, useful for dynamically selecting the model.

  ## Model Specification

  The model can be specified in several formats:

  ### String format (recommended)
  ```elixir
  run prompt("openai:gpt-4o", tools: true)
  run prompt("anthropic:claude-haiku-4-5", tools: false)
  ```

  ### Tuple format with options
  ```elixir
  run prompt({:openai, "gpt-4o", temperature: 0.7}, tools: true)
  ```

  ### Dynamic function
  For runtime configuration (like using environment variables), pass a function
  as the first argument to `prompt/2`:
  ```elixir
  run prompt(
    fn _input, _context ->
      "openai:gpt-4o"
    end,
    tools: false
  )
  ```

  This function will be executed just before the prompt is sent to the LLM.

  ## Options

  - `:tools`: A list of tool names to expose to the agent call.
  - `:verbose?`: Set to `true` for more output to be logged.
  - `:prompt`: A custom prompt. Supports multiple formats - see the prompt section below.

  ## Prompt

  The prompt by default is generated using the action and input descriptions. You can provide your own prompt
  via the `prompt` option which supports multiple formats based on the type of data provided:

  ### Supported Formats

  1. **String (EEx template)**: `"Analyze this: <%= @input.arguments.text %>"`
  2. **{System, User} tuple**: `{"You are an expert", "Analyze the sentiment"}`
  3. **Function**: `fn input, context -> {"Dynamic system", "Dynamic user"} end`
  4. **List of Messages**: `[%{role: "system", content: "..."}, %{role: "user", content: "..."}]`
  5. **Function returning Messages**: `fn input, context -> [%{role: "system", content: "..."}] end`

  ### Examples

  #### Basic String Template
  ```elixir
  run prompt(
    "openai:gpt-4o",
    prompt: "Analyze the sentiment of: <%= @input.arguments.text %>"
  )
  ```

  #### System/User Tuple
  ```elixir
  run prompt(
    "openai:gpt-4o",
    prompt: {"You are a sentiment analyzer", "Analyze: <%= @input.arguments.text %>"}
  )
  ```

  #### Messages for Multi-turn Conversations
  ```elixir
  run prompt(
    "openai:gpt-4o",
    prompt: [
      %{role: "system", content: "You are an expert assistant"},
      %{role: "user", content: "Hello, how can you help me?"},
      %{role: "assistant", content: "I can help with various tasks"},
      %{role: "user", content: "Great! Please analyze this data"}
    ]
  )
  ```

  #### Image Analysis with Templates
  ```elixir
  run prompt(
    "openai:gpt-4o",
    prompt: [
      %{role: "system", content: "You are an expert at image analysis"},
      %{role: "user", content: [
        %{type: "text", text: "Extra context: <%= @input.arguments.context %>"},
        %{type: "image_url", url: "<%= @input.arguments.image_url %>"}
      ]}
    ]
  )
  ```

  #### Dynamic Messages via Function
  ```elixir
  run prompt(
    "openai:gpt-4o",
    prompt: fn input, context ->
      base = [%{role: "system", content: "You are helpful"}]

      history = input.arguments.conversation_history
      |> Enum.map(fn %{"role" => role, "content" => content} ->
        %{role: role, content: content}
      end)

      base ++ history
    end
  )
  ```

  ### Template Processing

  - **String prompts**: Processed as EEx templates with `@input` and `@context`
  - **Messages with EEx**: Content strings are processed as EEx templates
  - **Functions**: Can return any supported format for dynamic generation

  The default prompt template is:

  ```elixir
  #{inspect(@prompt_template, pretty: true)}
  ```
  """
  use Ash.Resource.Actions.Implementation

  @max_tool_iterations 8

  def run(input, opts, context) do
    model = get_model(opts, input, context)
    json_schema = get_json_schema(input)
    tools = get_tools(opts, input, context)
    messages = build_messages(input, opts, context)
    req_llm = Keyword.get(opts, :req_llm, ReqLLM)

    if opts[:verbose?] do
      IO.puts("\n=== AshAi.Actions.Prompt ===")
      IO.puts("Model: #{inspect(model)}")
      IO.puts("Messages: #{inspect(messages, pretty: true)}")
      IO.puts("Tools available: #{length(tools)}")
      IO.puts("JSON Schema: #{inspect(json_schema, pretty: true)}")
    end

    req_context = build_req_context(messages)
    req_tools = build_req_tools(tools)

    case {json_schema, req_tools} do
      {%{"type" => "null"}, []} ->
        # Simple text generation
        execute_text_generation(req_llm, model, req_context, opts)

      {%{"type" => "null"}, _tools} ->
        # Tool execution without structured output
        execute_tool_loop(req_llm, model, req_context, req_tools, nil, opts, 0)

      {_schema, []} ->
        # Structured output without tools
        execute_structured_output(req_llm, model, req_context, json_schema, opts)

      {_schema, _tools} ->
        # Structured output with tools
        execute_tool_loop(req_llm, model, req_context, req_tools, json_schema, opts, 0)
    end
  end

  # Simple text generation
  defp execute_text_generation(req_llm, model, context, opts) do
    case req_llm.generate_text(model, context) do
      {:ok, response} ->
        if opts[:verbose?] do
          IO.puts("Response: #{inspect(response.message.content)}")
        end

        {:ok, extract_text_content(response.message)}

      {:error, error} ->
        {:error, error}
    end
  end

  # Structured output generation
  defp execute_structured_output(req_llm, model, context, json_schema, opts) do
    case req_llm.generate_object(model, context, json_schema) do
      {:ok, response} ->
        if opts[:verbose?] do
          IO.puts("Structured response: #{inspect(response.object)}")
        end

        {:ok, response.object}

      {:error, error} ->
        {:error, error}
    end
  end

  # Tool execution loop
  defp execute_tool_loop(req_llm, model, context, tools, json_schema, opts, iteration) do
    if iteration >= @max_tool_iterations do
      {:error, "Maximum tool iterations (#{@max_tool_iterations}) exceeded"}
    else
      case req_llm.generate_text(model, context, tools: tools) do
        {:ok, response} ->
          if opts[:verbose?] do
            IO.puts("\n--- Tool Loop Iteration #{iteration + 1} ---")
            IO.puts("Response: #{inspect(response.message)}")
          end

          cond do
            # No tool calls - we're done
            is_nil(response.message.tool_calls) or response.message.tool_calls == [] ->
              if json_schema do
                # Extract structured output from final response
                case req_llm.generate_object(model, response.context, json_schema) do
                  {:ok, final_response} ->
                    {:ok, final_response.object}

                  {:error, error} ->
                    {:error, error}
                end
              else
                {:ok, extract_text_content(response.message)}
              end

            # Has tool calls - execute and continue
            true ->
              if opts[:verbose?] do
                IO.puts("Executing #{length(response.message.tool_calls)} tool calls")
              end

              case ReqLLM.Context.execute_and_append_tools(
                     response.context,
                     response.message.tool_calls,
                     tools
                   ) do
                {:ok, updated_context} ->
                  execute_tool_loop(
                    req_llm,
                    model,
                    updated_context,
                    tools,
                    json_schema,
                    opts,
                    iteration + 1
                  )

                {:error, error} ->
                  {:error, error}
              end
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Extract text content from a message
  defp extract_text_content(%{content: content}) when is_list(content) do
    content
    |> Enum.filter(fn
      %ReqLLM.Message.ContentPart{type: :text} -> true
      _ -> false
    end)
    |> Enum.map_join("", fn %ReqLLM.Message.ContentPart{text: text} -> text end)
  end

  defp extract_text_content(%{content: content}) when is_binary(content), do: content
  defp extract_text_content(_), do: ""

  # Build ReqLLM.Context from normalized messages
  defp build_req_context(messages) do
    req_messages =
      Enum.map(messages, fn msg ->
        role = normalize_role(msg.role)

        content_parts =
          case msg.content do
            str when is_binary(str) ->
              [ReqLLM.Message.ContentPart.text(str)]

            parts when is_list(parts) ->
              Enum.map(parts, &normalize_content_part/1)
          end

        %ReqLLM.Message{
          role: role,
          content: content_parts
        }
      end)

    %ReqLLM.Context{messages: req_messages}
  end

  # Normalize role atoms/strings
  defp normalize_role("system"), do: :system
  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("tool"), do: :tool
  defp normalize_role(role) when is_atom(role), do: role

  # Normalize content parts from our simplified format to ReqLLM.Message.ContentPart
  defp normalize_content_part(%{type: "text", text: text}) do
    ReqLLM.Message.ContentPart.text(text)
  end

  defp normalize_content_part(%{type: "image_url", url: url}) do
    ReqLLM.Message.ContentPart.image_url(url)
  end

  defp normalize_content_part(%{type: type, text: text}) when type in ["text", :text] do
    ReqLLM.Message.ContentPart.text(text)
  end

  defp normalize_content_part(%{type: type, url: url}) when type in ["image_url", :image_url] do
    ReqLLM.Message.ContentPart.image_url(url)
  end

  defp normalize_content_part(str) when is_binary(str) do
    ReqLLM.Message.ContentPart.text(str)
  end

  # Build ReqLLM.Tool list from AshAi functions
  defp build_req_tools(ash_functions) do
    Enum.map(ash_functions, fn ash_func ->
      # Convert AshAi function to ReqLLM.Tool
      ReqLLM.Tool.new!(
        name: ash_func.name,
        description: ash_func.description || "",
        parameter_schema: ash_func.parameter_schema,
        callback: fn args ->
          # Execute the AshAi function
          case ash_func.function.(args) do
            {:ok, result} -> Jason.encode!(result)
            {:error, error} -> "Error: #{inspect(error)}"
            result -> Jason.encode!(result)
          end
        end
      )
    end)
  end

  # Get the model spec (handle both static and dynamic)
  defp get_model(opts, input, context) do
    case opts[:model] do
      function when is_function(function, 2) ->
        function.(input, context)

      model ->
        model
    end
  end

  # Get JSON schema for the action return type
  defp get_json_schema(input) do
    if input.action.returns do
      schema =
        AshAi.OpenApi.resource_write_attribute_type(
          %{name: :result, type: input.action.returns, constraints: input.action.constraints},
          nil,
          :create
        )

      if input.action.allow_nil? do
        %{"anyOf" => [%{"type" => "null"}, schema]}
      else
        schema
      end
      |> Jason.encode!()
      |> Jason.decode!()
    else
      %{"type" => "null"}
    end
  end

  # Get tools to expose to the LLM
  defp get_tools(opts, input, context) do
    case opts[:tools] do
      nil ->
        []

      true ->
        otp_app =
          Spark.otp_app(input.domain) ||
            Spark.otp_app(input.resource) ||
            raise "otp_app must be configured on the domain or the resource to get access to all tools"

        AshAi.functions(
          otp_app: otp_app,
          exclude_actions: [{input.resource, input.action.name}],
          actor: context.actor,
          tenant: context.tenant
        )

      tools ->
        otp_app =
          Spark.otp_app(input.domain) ||
            Spark.otp_app(input.resource) ||
            raise "otp_app must be configured on the domain or the resource to get access to all tools"

        AshAi.functions(
          tools: List.wrap(tools),
          otp_app: otp_app,
          exclude_actions: [{input.resource, input.action.name}],
          actor: context.actor,
          tenant: context.tenant
        )
    end
  end

  # Build messages from prompt option
  @doc false
  def build_messages(input, opts, context) do
    case Keyword.get(opts, :prompt, @prompt_template) do
      # Format 1: String (EEx template)
      prompt when is_binary(prompt) ->
        system_prompt = eval_template(prompt, input, context)

        [
          %{role: "system", content: system_prompt},
          %{role: "user", content: "Perform the action"}
        ]

      # Format 2: Tuple {system, user} (EEx templates)
      {system, user} when is_binary(system) and is_binary(user) ->
        system_prompt = eval_template(system, input, context)
        user_message = eval_template(user, input, context)

        [
          %{role: "system", content: system_prompt},
          %{role: "user", content: user_message}
        ]

      # Format 3: Messages list
      messages when is_list(messages) ->
        process_messages(messages, input, context)

      # Format 4: Function returning any of the above
      func when is_function(func, 2) ->
        result = func.(input, context)
        get_messages_from_result(result, input, context)
    end
  end

  # Process result from function
  defp get_messages_from_result(result, input, context) do
    case result do
      prompt when is_binary(prompt) ->
        build_messages(input, [prompt: prompt], context)

      {system, user} when is_binary(system) and is_binary(user) ->
        build_messages(input, [prompt: {system, user}], context)

      messages when is_list(messages) ->
        build_messages(input, [prompt: messages], context)

      _ ->
        raise ArgumentError,
              "Function must return string, {system, user} tuple, or list of Messages. Got: #{inspect(result)}"
    end
  end

  # Process a list of messages, evaluating EEx templates in content
  defp process_messages(messages, input, context) do
    Enum.map(messages, fn msg ->
      %{
        role: msg.role || msg["role"],
        content: process_message_content(msg.content || msg["content"], input, context)
      }
    end)
  end

  # Process message content (can be string or list of content parts)
  defp process_message_content(content, input, context) when is_binary(content) do
    eval_template(content, input, context)
  end

  defp process_message_content(content, input, context) when is_list(content) do
    Enum.map(content, fn part ->
      case part do
        %{type: "text", text: text} ->
          %{type: "text", text: eval_template(text, input, context)}

        %{type: type, text: text} when type in ["text", :text] ->
          %{type: "text", text: eval_template(text, input, context)}

        %{type: "image_url", url: url} ->
          %{type: "image_url", url: eval_template(url, input, context)}

        %{type: type, url: url} when type in ["image_url", :image_url] ->
          %{type: "image_url", url: eval_template(url, input, context)}

        str when is_binary(str) ->
          %{type: "text", text: eval_template(str, input, context)}

        other ->
          other
      end
    end)
  end

  defp process_message_content(other, _input, _context), do: other

  # Evaluate EEx template with input and context
  # sobelow_skip ["RCE.EEx"]
  defp eval_template(template, input, context) when is_binary(template) do
    EEx.eval_string(template, assigns: [input: input, context: context])
  end

  defp eval_template(other, _input, _context), do: other
end
