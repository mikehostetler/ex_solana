# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Actions.PromptTest do
  @moduledoc """
  Tests for the ReqLLM-based prompt action implementation.

  This test suite validates:
  - String model specifications
  - Various prompt formats (string, tuple, ReqLLM.Context, list, function)
  - Content part normalization
  - Backward compatibility with legacy formats
  """
  use ExUnit.Case, async: true
  alias __MODULE__.{TestDomain, TestResource}

  defp content_contains?(content, substring) when is_binary(content) do
    content =~ substring
  end

  defp content_contains?(content, substring) when is_list(content) do
    Enum.any?(content, fn
      %ReqLLM.Message.ContentPart{type: :text, text: text} -> text =~ substring
      _ -> false
    end)
  end

  defmodule FakeReqLLM do
    @moduledoc "Fake ReqLLM module for testing"

    def generate_object(model, context, _schema) do
      send(self(), {:generate_object_called, model, context})

      {:ok, %{object: %{"result" => "test_result"}}}
    end
  end

  defmodule FakeReqLLMWithSentiment do
    @moduledoc "Fake ReqLLM that returns sentiment data"

    def generate_object(_model, context, _schema) do
      send(self(), {:sentiment_called, context})

      {:ok,
       %{
         object: %{
           "result" => %{
             "sentiment" => "positive",
             "confidence" => 0.95,
             "keywords" => ["great", "excellent"]
           }
         }
       }}
    end
  end

  defmodule FakeReqLLMWithOcr do
    @moduledoc "Fake ReqLLM that returns OCR data"

    def generate_object(_model, context, _schema) do
      send(self(), {:ocr_called, context})

      {:ok,
       %{
         object: %{
           "result" => %{
             "image_text" => "Hello World"
           }
         }
       }}
    end
  end

  defmodule FakeReqLLMError do
    @moduledoc "Fake ReqLLM that returns an error"

    def generate_object(_model, _context, _schema) do
      {:error, "API error: rate limited"}
    end
  end

  defmodule Sentiment do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute :sentiment, :string, public?: true
      attribute :confidence, :float, public?: true
      attribute :keywords, {:array, :string}, public?: true
    end

    actions do
      default_accept([:*])
      defaults([:create, :read])
    end
  end

  defmodule OcrResult do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [
        fields: [
          image_text: [
            type: :string,
            allow_nil?: false,
            description: "The extracted text from the image"
          ]
        ]
      ]
  end

  defmodule TestResource do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshAi]

    ets do
      private?(true)
    end

    attributes do
      uuid_v7_primary_key(:id, writable?: true)
      attribute(:name, :string, public?: true)
    end

    actions do
      default_accept([:*])
      defaults([:create, :read, :update, :destroy])

      action :analyze_sentiment, Sentiment do
        description("Analyze the sentiment of a given text")
        argument(:text, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: {"You are a sentiment analyzer", "Analyze: <%= @input.arguments.text %>"},
              req_llm: FakeReqLLMWithSentiment
            )
      end

      action :analyze_with_string_prompt, :string do
        description("Test legacy string prompt")
        argument(:text, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: "Process this text: <%= @input.arguments.text %>",
              req_llm: FakeReqLLM
            )
      end

      action :analyze_with_function_prompt, :string do
        description("Test function-based prompt")
        argument(:text, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: fn input, _context ->
                {"You are a text processor", "Process: #{input.arguments.text}"}
              end,
              req_llm: FakeReqLLM
            )
      end

      action :analyze_with_messages_list, :string do
        description("Test message list prompt")
        argument(:text, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: [
                %{role: "system", content: "You are a helpful assistant"},
                %{role: "user", content: "Process: <%= @input.arguments.text %>"}
              ],
              req_llm: FakeReqLLM
            )
      end

      action :analyze_with_reqllm_context, :string do
        description("Test ReqLLM.Context prompt")
        argument(:text, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: fn input, _context ->
                ReqLLM.Context.new([
                  ReqLLM.Context.system("You are a helpful assistant"),
                  ReqLLM.Context.user("Process: #{input.arguments.text}")
                ])
              end,
              req_llm: FakeReqLLM
            )
      end

      action :ocr_with_context_api, OcrResult do
        description("OCR using ReqLLM.Context API")
        argument(:image_url, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: fn input, _context ->
                ReqLLM.Context.new([
                  ReqLLM.Context.system("You are an OCR expert"),
                  ReqLLM.Context.user([
                    ReqLLM.Message.ContentPart.text("Extract text from this image"),
                    ReqLLM.Message.ContentPart.image_url(input.arguments.image_url)
                  ])
                ])
              end,
              req_llm: FakeReqLLMWithOcr
            )
      end

      action :test_error_handling, :string do
        description("Test error handling")
        argument(:text, :string, allow_nil?: false)

        run prompt("openai:gpt-4o",
              prompt: "Analyze: <%= @input.arguments.text %>",
              req_llm: FakeReqLLMError
            )
      end
    end
  end

  defmodule TestDomain do
    use Ash.Domain, extensions: [AshAi]

    resources do
      resource(TestResource)
    end
  end

  describe "prompt with tuple format" do
    test "successfully executes with {system, user} tuple prompt" do
      result =
        TestResource
        |> Ash.ActionInput.for_action(:analyze_sentiment, %{text: "This is amazing!"})
        |> Ash.run_action!()

      assert result.sentiment == "positive"
      assert result.confidence == 0.95
      assert result.keywords == ["great", "excellent"]
    end

    test "EEx template in tuple user message substitutes correctly" do
      TestResource
      |> Ash.ActionInput.for_action(:analyze_sentiment, %{text: "substituted value"})
      |> Ash.run_action!()

      assert_receive {:sentiment_called, context}
      user_message = Enum.find(context.messages, &(&1.role == :user))
      assert content_contains?(user_message.content, "substituted value")
    end
  end

  describe "prompt with string format" do
    test "successfully executes with string prompt" do
      result =
        TestResource
        |> Ash.ActionInput.for_action(:analyze_with_string_prompt, %{text: "test input"})
        |> Ash.run_action!()

      assert result == "test_result"

      assert_receive {:generate_object_called, "openai:gpt-4o", context}
      assert %ReqLLM.Context{} = context
      assert length(context.messages) == 2
    end

    test "EEx template substitutes input arguments correctly" do
      TestResource
      |> Ash.ActionInput.for_action(:analyze_with_string_prompt, %{text: "hello world"})
      |> Ash.run_action!()

      assert_receive {:generate_object_called, _model, context}
      system_message = Enum.find(context.messages, &(&1.role == :system))
      assert content_contains?(system_message.content, "hello world")
    end
  end

  describe "prompt with function format" do
    test "successfully executes with function prompt returning tuple" do
      result =
        TestResource
        |> Ash.ActionInput.for_action(:analyze_with_function_prompt, %{text: "test input"})
        |> Ash.run_action!()

      assert result == "test_result"
    end

    test "successfully executes with function prompt returning ReqLLM.Context" do
      result =
        TestResource
        |> Ash.ActionInput.for_action(:analyze_with_reqllm_context, %{text: "test input"})
        |> Ash.run_action!()

      assert result == "test_result"

      assert_receive {:generate_object_called, "openai:gpt-4o", context}
      assert %ReqLLM.Context{} = context
    end
  end

  describe "prompt with messages list" do
    test "successfully executes with list of message maps" do
      result =
        TestResource
        |> Ash.ActionInput.for_action(:analyze_with_messages_list, %{text: "test input"})
        |> Ash.run_action!()

      assert result == "test_result"
    end

    test "EEx template in message list content substitutes correctly" do
      TestResource
      |> Ash.ActionInput.for_action(:analyze_with_messages_list, %{text: "list template value"})
      |> Ash.run_action!()

      assert_receive {:generate_object_called, _model, context}
      user_message = Enum.find(context.messages, &(&1.role == :user))
      assert content_contains?(user_message.content, "list template value")
    end
  end

  describe "prompt with ReqLLM.Context API" do
    test "supports ReqLLM.Context with content parts for images" do
      result =
        TestResource
        |> Ash.ActionInput.for_action(:ocr_with_context_api, %{
          image_url: "https://example.com/image.jpg"
        })
        |> Ash.run_action!()

      assert result.image_text == "Hello World"

      assert_receive {:ocr_called, context}
      assert %ReqLLM.Context{} = context

      user_message = Enum.find(context.messages, &(&1.role == :user))
      assert user_message != nil
      assert is_list(user_message.content)
    end
  end

  describe "error handling" do
    test "propagates ReqLLM errors" do
      error =
        assert_raise Ash.Error.Unknown, fn ->
          TestResource
          |> Ash.ActionInput.for_action(:test_error_handling, %{text: "test"})
          |> Ash.run_action!()
        end

      assert length(error.errors) == 1
      assert hd(error.errors).error =~ "rate limited"
    end
  end
end
