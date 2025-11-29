defmodule ReqLLM.Coverage.Azure.EmbeddingTest do
  @moduledoc """
  Azure OpenAI embedding API feature coverage tests.

  Run with REQ_LLM_FIXTURES_MODE=record to test against live API and record fixtures.
  Otherwise uses fixtures for fast, reliable testing.

  Note: Azure requires `base_url` and `deployment` options to be set via environment
  variables or explicit options when recording fixtures.
  """

  use ReqLLM.ProviderTest.Embedding, provider: :azure
end
