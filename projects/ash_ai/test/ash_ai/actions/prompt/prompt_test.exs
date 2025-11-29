# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Actions.Prompt.PromptTest do
  use ExUnit.Case, async: true
  alias __MODULE__.{TestDomain, TestResource, OcrResult}

  defmodule OcrResult do
    use Ash.Resource, data_layer: :embedded

    attributes do
      attribute :image_text, :string, public?: true
    end

    actions do
      default_accept [:*]
      defaults [:create, :read]
    end
  end

  defmodule TestResource do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshAi]

    ets do
      private? true
    end

    attributes do
      uuid_v7_primary_key :id, writable?: true
    end

    actions do
      default_accept [:*]
      defaults [:create, :read, :update, :destroy]

      action :ocr_with_messages, OcrResult do
        argument :image_url, :string, allow_nil?: false
        argument :extra_context, :string

        run prompt(
              "test-model",
              req_llm: AshAi.Actions.Prompt.PromptTest.FakeReqLLM,
              prompt: [
                %{role: "system", content: "You are an expert at OCR."},
                %{
                  role: "user",
                  content: [
                    %{type: "text", text: "Extra: <%= @input.arguments.extra_context %>"},
                    %{type: "image_url", url: "<%= @input.arguments.image_url %>"}
                  ]
                }
              ]
            )
      end

      action :legacy_string_prompt, OcrResult do
        argument :text, :string, allow_nil?: false

        run prompt("test-model",
              req_llm: AshAi.Actions.Prompt.PromptTest.FakeReqLLM,
              prompt: "Process: <%= @input.arguments.text %>"
            )
      end

      action :legacy_tuple_prompt, OcrResult do
        argument :text, :string, allow_nil?: false

        run prompt("test-model",
              req_llm: AshAi.Actions.Prompt.PromptTest.FakeReqLLM,
              prompt: {"You are a processor", "Process: <%= @input.arguments.text %>"}
            )
      end
    end
  end

  defmodule TestDomain do
    use Ash.Domain, extensions: [AshAi]

    resources do
      resource TestResource
    end
  end

  defmodule FakeReqLLM do
    def generate_object(_model, %ReqLLM.Context{messages: msgs}, _schema) do
      has_image =
        Enum.any?(msgs, fn m ->
          Enum.any?(m.content, &match?(%ReqLLM.Message.ContentPart{type: :image_url}, &1))
        end)

      obj = if has_image, do: %{"image_text" => "Hello World"}, else: %{"image_text" => "ok"}

      {:ok,
       %{
         object: obj,
         message: %ReqLLM.Message{
           role: :assistant,
           content: [ReqLLM.Message.ContentPart.text("done")]
         }
       }}
    end

    def generate_text(_model, _context) do
      {:ok,
       %{
         message: %ReqLLM.Message{
           role: :assistant,
           content: [ReqLLM.Message.ContentPart.text("plain text")]
         }
       }}
    end
  end

  test "messages with image_url are normalized and return structured output" do
    result =
      TestResource
      |> Ash.ActionInput.for_action(:ocr_with_messages, %{
        image_url: "http://example/img.jpg",
        extra_context: "ctx"
      })
      |> Ash.run_action!()

    assert result["image_text"] == "Hello World"
  end

  test "legacy string prompt returns structured output" do
    result =
      TestResource
      |> Ash.ActionInput.for_action(:legacy_string_prompt, %{text: "input"})
      |> Ash.run_action!()

    assert result["image_text"] == "ok"
  end

  test "legacy tuple prompt returns structured output" do
    result =
      TestResource
      |> Ash.ActionInput.for_action(:legacy_tuple_prompt, %{text: "input"})
      |> Ash.run_action!()

    assert result["image_text"] == "ok"
  end
end
