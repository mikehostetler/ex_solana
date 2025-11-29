defmodule ReqLLM.Providers.Azure.RoutingTest do
  @moduledoc """
  Tests for Azure provider routing and deployment.

  Covers:
  - Multi-family routing (OpenAI vs Anthropic endpoints)
  - Model family validation
  - Cross-family model switching
  - Deployment name variations
  - Deployment name edge cases
  """

  use ExUnit.Case, async: true

  alias ReqLLM.Providers.Azure

  describe "multi-family routing" do
    test "routes GPT models to chat/completions endpoint" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "my-deployment"
        )

      url = URI.to_string(request.url)
      assert url =~ "/chat/completions"
      refute url =~ "/messages"
    end

    test "routes o1 models to chat/completions endpoint" do
      {:ok, model} = ReqLLM.model("azure:o1-mini")
      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])

      {:ok, finch_request} =
        Azure.attach_stream(
          model,
          context,
          [
            api_key: "test-api-key",
            deployment: "my-deployment",
            base_url: "https://my-resource.openai.azure.com/openai"
          ],
          :req_llm_finch
        )

      url_string =
        case finch_request do
          %{path: path, query: query} when is_binary(query) and query != "" ->
            path <> "?" <> query

          %{path: path} ->
            path
        end

      assert url_string =~ "/chat/completions"
      refute url_string =~ "/messages"
    end

    test "uses correct headers for GPT models" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")
      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])

      {:ok, finch_request} =
        Azure.attach_stream(
          model,
          context,
          [
            api_key: "test-api-key",
            deployment: "my-deployment",
            base_url: "https://my-resource.openai.azure.com/openai"
          ],
          :req_llm_finch
        )

      header_map = Map.new(finch_request.headers)
      assert header_map["api-key"] == "test-api-key"
      refute Map.has_key?(header_map, "anthropic-version")
    end

    test "routes Claude models to messages endpoint" do
      model = %LLMDB.Model{
        id: "claude-3-5-sonnet-20241022",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          api_key: "test-key",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "claude-deployment"
        )

      url = URI.to_string(request.url)
      assert url =~ "/messages"
      refute url =~ "/chat/completions"
    end

    test "routes Claude models to messages endpoint in streaming" do
      model = %LLMDB.Model{
        id: "claude-3-5-sonnet-20241022",
        provider: :azure,
        capabilities: %{chat: true}
      }

      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])

      {:ok, finch_request} =
        Azure.attach_stream(
          model,
          context,
          [
            api_key: "test-api-key",
            deployment: "claude-deployment",
            base_url: "https://my-resource.openai.azure.com/openai"
          ],
          :req_llm_finch
        )

      url_string =
        case finch_request do
          %{path: path, query: query} when is_binary(query) and query != "" ->
            path <> "?" <> query

          %{path: path} ->
            path
        end

      assert url_string =~ "/messages"
      refute url_string =~ "/chat/completions"
    end

    test "uses correct headers for Claude models" do
      model = %LLMDB.Model{
        id: "claude-3-5-sonnet-20241022",
        provider: :azure,
        capabilities: %{chat: true}
      }

      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])

      {:ok, finch_request} =
        Azure.attach_stream(
          model,
          context,
          [
            api_key: "test-api-key",
            deployment: "claude-deployment",
            base_url: "https://my-resource.openai.azure.com/openai"
          ],
          :req_llm_finch
        )

      header_map = Map.new(finch_request.headers)
      assert header_map["x-api-key"] == "test-api-key"
      assert header_map["anthropic-version"] == "2023-06-01"
    end
  end

  describe "model family validation" do
    test "raises error for unknown model family" do
      model = %LLMDB.Model{
        id: "unknown-model-xyz",
        provider: :azure,
        capabilities: %{chat: true}
      }

      assert_raise ArgumentError, ~r/Unknown Azure model family.*unknown-model-xyz/, fn ->
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )
      end
    end

    test "recognizes gpt family" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )

      url = URI.to_string(request.url)
      assert url =~ "/chat/completions"
    end

    test "recognizes text-embedding family" do
      model = %LLMDB.Model{
        id: "text-embedding-3-small",
        provider: :azure,
        capabilities: %{embeddings: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :embedding,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )

      url = URI.to_string(request.url)
      assert url =~ "/embeddings"
    end

    test "provider_model_id takes precedence over id for model family routing" do
      model = %LLMDB.Model{
        id: "my-custom-alias",
        provider: :azure,
        provider_model_id: "gpt-4o",
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )

      url = URI.to_string(request.url)
      assert url =~ "/chat/completions"
    end
  end

  describe "cross-family model switching" do
    test "routes OpenAI models to chat/completions endpoint" do
      model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "gpt-deployment"
        )

      url = URI.to_string(request.url)
      assert url =~ "/chat/completions"
      refute url =~ "/messages"
    end

    test "routes Claude models to messages endpoint" do
      model = %LLMDB.Model{
        id: "claude-3-5-sonnet-20241022",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          api_key: "test-key",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "claude-deployment"
        )

      url = URI.to_string(request.url)
      assert url =~ "/messages"
      refute url =~ "/chat/completions"
    end

    test "applies correct formatter for OpenAI models (no model field, string keys)" do
      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])
      body = Azure.OpenAI.format_request("gpt-4o", context, stream: false)

      refute Map.has_key?(body, "model")
      assert Map.has_key?(body, "messages")
      assert is_list(body["messages"])
      assert hd(body["messages"])["role"] == "user"
    end

    test "applies correct formatter for Claude models (model field, atom keys)" do
      context = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])
      body = Azure.Anthropic.format_request("claude-3-5-sonnet-20241022", context, stream: false)

      assert body.model == "claude-3-5-sonnet-20241022"
      assert Map.has_key?(body, :messages)
      assert is_list(body.messages)
      assert hd(body.messages).role == "user"
    end

    test "uses correct api-key header for each model family" do
      openai_model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true}
      }

      claude_model = %LLMDB.Model{
        id: "claude-3-5-sonnet-20241022",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, openai_request} =
        Azure.prepare_request(
          :chat,
          openai_model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "gpt-deployment",
          api_key: "test-key"
        )

      {:ok, claude_request} =
        Azure.prepare_request(
          :chat,
          claude_model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "claude-deployment",
          api_key: "test-key"
        )

      openai_api_key = get_header(openai_request.headers, "api-key")
      claude_api_key = get_header(claude_request.headers, "x-api-key")

      assert openai_api_key == "test-key"
      assert claude_api_key == "test-key"
    end

    test "includes anthropic-version header only for Claude models" do
      openai_model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true}
      }

      claude_model = %LLMDB.Model{
        id: "claude-3-5-sonnet-20241022",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, openai_request} =
        Azure.prepare_request(
          :chat,
          openai_model,
          "Hello",
          api_key: "test-key",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "gpt-deployment"
        )

      {:ok, claude_request} =
        Azure.prepare_request(
          :chat,
          claude_model,
          "Hello",
          api_key: "test-key",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "claude-deployment"
        )

      openai_anthropic_version = get_header(openai_request.headers, "anthropic-version")
      claude_anthropic_version = get_header(claude_request.headers, "anthropic-version")

      assert openai_anthropic_version == nil
      assert claude_anthropic_version == "2023-06-01"
    end
  end

  describe "deployment name variations" do
    test "uses explicit deployment option over model ID" do
      model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "my-custom-deployment"
        )

      url = URI.to_string(request.url)
      assert url =~ "/deployments/my-custom-deployment/"
      refute url =~ "/deployments/gpt-4o/"
    end

    test "handles deployment names with special characters" do
      model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "gpt-4o-prod-v2"
        )

      url = URI.to_string(request.url)
      assert url =~ "/deployments/gpt-4o-prod-v2/"
    end

    test "falls back to model ID when deployment not specified" do
      model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true}
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )

      url = URI.to_string(request.url)
      assert url =~ "/deployments/gpt-4o/"
    end

    test "does not auto-use provider_model_id for deployment (requires explicit option)" do
      model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true},
        provider_model_id: "gpt-4o-2024-08-06"
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )

      url = URI.to_string(request.url)
      assert url =~ "/deployments/gpt-4o/"
      refute url =~ "/deployments/gpt-4o-2024-08-06/"
    end

    test "provider_model_id IS used for model family routing" do
      model = %LLMDB.Model{
        id: "my-claude-alias",
        provider: :azure,
        capabilities: %{chat: true},
        provider_model_id: "claude-3-5-sonnet-20241022"
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          api_key: "test-key",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "claude-deployment"
        )

      url = URI.to_string(request.url)
      assert url =~ "/messages"
      refute url =~ "/chat/completions"
    end

    test "deployment precedence: explicit option > model.id" do
      model = %LLMDB.Model{
        id: "gpt-4o",
        provider: :azure,
        capabilities: %{chat: true},
        provider_model_id: "gpt-4o-2024-08-06"
      }

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "production-gpt4"
        )

      url = URI.to_string(request.url)
      assert url =~ "/deployments/production-gpt4/"
      refute url =~ "/deployments/gpt-4o/"
      refute url =~ "/deployments/gpt-4o-2024-08-06/"
    end
  end

  describe "deployment name edge cases" do
    test "accepts deployment with hyphens" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "my-gpt-4o-deployment"
        )

      url_string = URI.to_string(request.url)
      assert url_string =~ "/deployments/my-gpt-4o-deployment/"
    end

    test "accepts deployment with underscores" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "my_gpt_4o_deployment"
        )

      url_string = URI.to_string(request.url)
      assert url_string =~ "/deployments/my_gpt_4o_deployment/"
    end

    test "accepts deployment with numbers" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai",
          deployment: "gpt4o-v2-20240101"
        )

      url_string = URI.to_string(request.url)
      assert url_string =~ "/deployments/gpt4o-v2-20240101/"
    end

    test "uses model.id as default deployment" do
      {:ok, model} = ReqLLM.model("azure:gpt-4o")

      {:ok, request} =
        Azure.prepare_request(
          :chat,
          model,
          "Hello",
          base_url: "https://my-resource.openai.azure.com/openai"
        )

      url_string = URI.to_string(request.url)
      assert url_string =~ "/deployments/gpt-4o/"
    end
  end

  defp get_header(headers, key) do
    case Enum.find(headers, fn {k, _v} -> k == key end) do
      {_, [value | _]} -> value
      {_, value} when is_binary(value) -> value
      nil -> nil
    end
  end
end
