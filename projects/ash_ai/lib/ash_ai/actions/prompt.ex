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

  Uses ReqLLM for structured output generation with model specifications as strings.

  ## Example

  ```elixir
  action :analyze_sentiment, :atom do
    constraints one_of: [:positive, :negative]

    description \"\"\"
    Analyzes the sentiment of a given piece of text to determine if it is overall positive or negative.
    \"\"\"

    argument :text, :string do
      allow_nil? false
      description "The text for analysis."
    end

    run prompt("openai:gpt-4o",
      prompt: {"You are a sentiment analyzer", "Analyze: <%= @input.arguments.text %>"}
    )
  end
  ```

  ## Model Specification

  The first argument to `prompt/2` is a model specification string in the format `"provider:model-name"`.
  Examples: `"openai:gpt-4o"`, `"anthropic:claude-haiku-4-5"`, `"openai:gpt-4o-mini"`.

  ## Options

  - `:prompt` - A custom prompt. Supports multiple formats - see the prompt section below.
  - `:req_llm` - Override the ReqLLM module (useful for testing with mocks).

  ## Prompt Formats

  The prompt by default is generated using the action and input descriptions. You can provide your own prompt
  via the `prompt` option which supports multiple formats:

  ### Supported Formats

  1. **String (EEx template)**: `"Analyze this: <%= @input.arguments.text %>"`
  2. **{System, User} tuple**: `{"You are an expert", "Analyze: <%= @input.arguments.text %>"}`
  3. **ReqLLM.Context**: Pass a context directly (canonical format)
  4. **List of messages**: Maps with role/content, ReqLLM.Message structs, or mixed
  5. **Function returning any of the above**: `fn input, context -> ... end`

  ### Using ReqLLM.Context (Recommended)

  ```elixir
  import ReqLLM.Context

  run prompt("openai:gpt-4o",
    prompt: fn input, _ctx ->
      ReqLLM.Context.new([
        system("You are an OCR expert"),
        user([
          ReqLLM.Message.ContentPart.text("Extract text from this image"),
          ReqLLM.Message.ContentPart.image_url(input.arguments.image_url)
        ])
      ])
    end
  )
  ```

  ### Legacy Map Format

  For convenience, loose maps with role/content keys are also supported:

  ```elixir
  [
    %{role: "system", content: "You are an OCR expert"},
    %{role: "user", content: "Extract text: <%= @input.arguments.text %>"}
  ]
  ```

  The default prompt template is:

  ```elixir
  #{inspect(@prompt_template, pretty: true)}
  ```
  """
  use Ash.Resource.Actions.Implementation

  def run(input, opts, context) do
    model = opts[:model]
    schema = build_json_schema(input)
    reqllm_context = build_context(input, opts, context)

    req_llm_module = Keyword.get(opts, :req_llm, ReqLLM)

    case req_llm_module.generate_object(model, reqllm_context, schema) do
      {:ok, %{object: result}} ->
        cast_result(result, input.action)

      {:ok, result} when is_map(result) ->
        cast_result(result, input.action)

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_json_schema(input) do
    if input.action.returns do
      inner_schema =
        AshAi.OpenApi.resource_write_attribute_type(
          %{name: :result, type: input.action.returns, constraints: input.action.constraints},
          nil,
          :create
        )

      result_schema =
        if input.action.allow_nil? do
          %{"anyOf" => [%{"type" => "null"}, inner_schema]}
        else
          inner_schema
        end

      %{
        "type" => "object",
        "properties" => %{
          "result" => result_schema
        },
        "required" => ["result"],
        "additionalProperties" => false
      }
    else
      %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      }
    end
  end

  defp cast_result(result, action) do
    value = unwrap_result(result)

    with {:ok, value} <-
           Ash.Type.cast_input(
             action.returns,
             value,
             action.constraints
           ),
         {:ok, value} <-
           Ash.Type.apply_constraints(
             action.returns,
             value,
             action.constraints
           ) do
      {:ok, value}
    else
      {:error, error} ->
        {:error, "Failed to cast LLM response: #{inspect(error)}. Response: #{inspect(result)}"}
    end
  end

  defp unwrap_result(%{"result" => value}), do: value
  defp unwrap_result(%{result: value}), do: value
  defp unwrap_result(value), do: value

  # sobelow_skip ["RCE.EEx"]
  defp build_context(input, opts, context) do
    prompt = Keyword.get(opts, :prompt, @prompt_template)

    prompt_value =
      case prompt do
        func when is_function(func, 2) ->
          func.(input, context)

        other ->
          other
      end

    normalize_to_context(prompt_value, input, context)
  end

  # sobelow_skip ["RCE.EEx"]
  defp normalize_to_context(prompt, input, context) do
    case prompt do
      # Already a ReqLLM.Context - pass through
      %ReqLLM.Context{} = ctx ->
        ctx

      # String template - evaluate and create system + user messages
      prompt when is_binary(prompt) ->
        system_prompt = EEx.eval_string(prompt, assigns: [input: input, context: context])

        ReqLLM.Context.new([
          ReqLLM.Context.system(system_prompt),
          ReqLLM.Context.user("Perform the action")
        ])

      # {system, user} tuple - evaluate both templates
      {system, user} when is_binary(system) and is_binary(user) ->
        system_prompt = EEx.eval_string(system, assigns: [input: input, context: context])
        user_message = EEx.eval_string(user, assigns: [input: input, context: context])

        ReqLLM.Context.new([
          ReqLLM.Context.system(system_prompt),
          ReqLLM.Context.user(user_message)
        ])

      # List of messages - process EEx templates in string content, then normalize
      messages when is_list(messages) ->
        processed = process_message_templates(messages, input, context)
        ReqLLM.Context.normalize!(processed, convert_loose: true)
    end
  end

  # sobelow_skip ["RCE.EEx"]
  defp process_message_templates(messages, input, context) do
    Enum.map(messages, fn msg ->
      case msg do
        # ReqLLM.Message struct - process content if it's a string
        %ReqLLM.Message{content: content} = message when is_binary(content) ->
          processed = EEx.eval_string(content, assigns: [input: input, context: context])
          %{message | content: processed}

        %ReqLLM.Message{} = message ->
          message

        # Loose map with string keys
        %{"content" => content} = map when is_binary(content) ->
          processed = EEx.eval_string(content, assigns: [input: input, context: context])
          Map.put(map, "content", processed)

        # Loose map with atom keys
        %{content: content} = map when is_binary(content) ->
          processed = EEx.eval_string(content, assigns: [input: input, context: context])
          Map.put(map, :content, processed)

        # Pass through anything else (ReqLLM.Context.normalize will handle it)
        other ->
          other
      end
    end)
  end
end
