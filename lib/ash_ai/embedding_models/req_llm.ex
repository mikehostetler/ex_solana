# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.EmbeddingModels.ReqLLM do
  @moduledoc """
  ReqLLM-backed embedding model for AshAi vectorization.

  Uses `ReqLLM.embed/2` to generate embeddings from text.

  ## Configuration

      vectorize do
        embedding_model {AshAi.EmbeddingModels.ReqLLM,
          model: "openai:text-embedding-3-small",
          dimensions: 1536
        }
      end

  ## Options

  - `:model` (required) - ReqLLM model identifier (e.g., "openai:text-embedding-3-small")
  - `:dimensions` (required) - Vector dimensions for the model
  - `:req_opts` (optional) - Additional options passed to ReqLLM
  - `:max_batch_size` (optional) - Maximum batch size for chunking (default: 100)

  ## Common Dimensions

  - OpenAI text-embedding-3-small: 1536
  - OpenAI text-embedding-3-large: 3072
  - Google Gemini text-embedding-004: 768 or 3072
  - Cohere embed-english-v3.0: 1024
  - Voyage voyage-2: 1024

  ## Example

      defmodule MyApp.Post do
        use Ash.Resource,
          extensions: [AshAi]

        vectorize do
          strategy :after_action

          embedding_model {AshAi.EmbeddingModels.ReqLLM,
            model: "openai:text-embedding-3-small",
            dimensions: 1536,
            req_opts: [api_key: System.get_env("OPENAI_API_KEY")]
          }

          attribute :content

          full_text :summary do
            text fn record ->
              "Title: \#{record.title}. Content: \#{record.content}"
            end
          end
        end

        attributes do
          uuid_primary_key :id
          attribute :title, :string
          attribute :content, :string
        end
      end
  """
  use AshAi.EmbeddingModel

  @default_max_batch_size 100

  @impl true
  def dimensions(opts) do
    # Compile-time safe; no external calls allowed
    case Keyword.fetch!(opts, :dimensions) do
      nil -> raise KeyError, key: :dimensions, term: opts
      dims -> dims
    end
  end

  @impl true
  def generate(texts, opts) do
    model = Keyword.fetch!(opts, :model)
    req_opts = Keyword.get(opts, :req_opts, [])
    max_batch_size = Keyword.get(opts, :max_batch_size, @default_max_batch_size)

    # Normalize nil values to empty strings
    inputs = Enum.map(texts, &(&1 || ""))

    # Chunk if necessary to respect provider limits
    chunks = Enum.chunk_every(inputs, max_batch_size)

    chunks
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      case call_reqllm(model, chunk, req_opts) do
        {:ok, embeddings} -> {:cont, {:ok, acc ++ embeddings}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp call_reqllm(model, inputs, req_opts) do
    # Check for test mode mock function
    case Process.get(:reqllm_mock) do
      nil ->
        real_reqllm_call(model, inputs, req_opts)

      mock_fn when is_function(mock_fn, 3) ->
        mock_fn.(model, inputs, req_opts)
    end
  end

  defp real_reqllm_call(model, inputs, req_opts) do
    unless function_exported?(ReqLLM, :embed, 3) do
      {:error, "ReqLLM.embed/3 not found. Ensure ReqLLM is installed and up to date."}
    else
      case ReqLLM.embed(model, inputs, req_opts) do
        {:ok, embeddings} when is_list(embeddings) ->
          {:ok, embeddings}

        {:error, error} ->
          {:error, error}

        other ->
          {:error, "Unexpected response from ReqLLM.embed/2: #{inspect(other)}"}
      end
    end
  end
end
