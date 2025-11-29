# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.EmbeddingModels.ReqLLMTest do
  use ExUnit.Case, async: true

  alias AshAi.EmbeddingModels.ReqLLM

  describe "dimensions/1" do
    test "returns configured dimensions" do
      assert 1536 = ReqLLM.dimensions(dimensions: 1536)
      assert 3072 = ReqLLM.dimensions(dimensions: 3072)
      assert 768 = ReqLLM.dimensions(dimensions: 768)
    end

    test "raises when dimensions not configured" do
      assert_raise KeyError, fn ->
        ReqLLM.dimensions([])
      end
    end

    test "raises when dimensions is nil" do
      assert_raise KeyError, fn ->
        ReqLLM.dimensions(dimensions: nil)
      end
    end
  end

  describe "generate/2" do
    setup do
      # Store original function to restore after test
      original_exported? = :erlang.function_exported(ReqLLM, :embed, 2)
      on_exit(fn -> original_exported? end)
      :ok
    end

    test "calls ReqLLM.embed with model and inputs" do
      # Mock ReqLLM.embed/2
      mock_embed = fn model, inputs, _opts ->
        assert model == "openai:text-embedding-3-small"
        assert inputs == ["hello", "world"]

        {:ok,
         [
           [0.1, 0.2, 0.3],
           [0.4, 0.5, 0.6]
         ]}
      end

      # Replace the call_reqllm function behavior
      with_mock_reqllm(mock_embed, fn ->
        {:ok, embeddings} =
          ReqLLM.generate(
            ["hello", "world"],
            model: "openai:text-embedding-3-small",
            dimensions: 3
          )

        assert length(embeddings) == 2
        assert hd(embeddings) == [0.1, 0.2, 0.3]
      end)
    end

    test "normalizes nil values to empty strings" do
      mock_embed = fn _model, inputs, _opts ->
        assert inputs == ["", "world", ""]

        {:ok,
         [
           [0.1, 0.2],
           [0.3, 0.4],
           [0.5, 0.6]
         ]}
      end

      with_mock_reqllm(mock_embed, fn ->
        {:ok, embeddings} =
          ReqLLM.generate(
            [nil, "world", nil],
            model: "test:model",
            dimensions: 2
          )

        assert length(embeddings) == 3
      end)
    end

    test "chunks large batches" do
      mock_embed = fn _model, inputs, _opts ->
        # Each chunk should be max 5 items
        assert length(inputs) <= 5

        {:ok, Enum.map(inputs, fn _ -> [0.1, 0.2] end)}
      end

      with_mock_reqllm(mock_embed, fn ->
        # Generate 12 items with max_batch_size of 5
        # Should result in 3 calls: 5, 5, 2
        {:ok, embeddings} =
          ReqLLM.generate(
            Enum.map(1..12, &"text#{&1}"),
            model: "test:model",
            dimensions: 2,
            max_batch_size: 5
          )

        assert length(embeddings) == 12
      end)
    end

    test "handles ReqLLM errors" do
      mock_embed = fn _model, _inputs, _opts ->
        {:error, "API rate limit exceeded"}
      end

      with_mock_reqllm(mock_embed, fn ->
        assert {:error, "API rate limit exceeded"} =
                 ReqLLM.generate(
                   ["hello"],
                   model: "test:model",
                   dimensions: 2
                 )
      end)
    end

    test "passes req_opts to ReqLLM" do
      mock_embed = fn _model, _inputs, opts ->
        assert opts[:api_key] == "test-key"
        assert opts[:timeout] == 30_000

        {:ok, [[0.1, 0.2]]}
      end

      with_mock_reqllm(mock_embed, fn ->
        {:ok, _embeddings} =
          ReqLLM.generate(
            ["hello"],
            model: "test:model",
            dimensions: 2,
            req_opts: [api_key: "test-key", timeout: 30_000]
          )
      end)
    end
  end

  # Helper to mock ReqLLM.embed/3 behavior using process dictionary
  defp with_mock_reqllm(mock_fn, test_fn) do
    Process.put(:reqllm_mock, mock_fn)

    try do
      test_fn.()
    after
      Process.delete(:reqllm_mock)
    end
  end
end
