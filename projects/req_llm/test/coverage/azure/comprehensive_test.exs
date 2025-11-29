defmodule ReqLLM.Coverage.Azure.ComprehensiveTest do
  @moduledoc """
  Comprehensive Azure AI Services provider tests.

  Tests all models from ModelMatrix with consolidated test suite:
  - Basic generate_text (non-streaming)
  - Streaming with system context + creative params
  - Token limit constraints
  - Usage metrics and cost calculations
  - Tool calling capabilities
  - Object generation (streaming)
  - Reasoning/thinking tokens (for models with reasoning capability)

  Run with REQ_LLM_FIXTURES_MODE=record to test against live API and record fixtures.
  Otherwise uses fixtures for fast, reliable testing.

  ## Azure-Specific Requirements

  When recording fixtures, ensure these environment variables are set:
  - `AZURE_OPENAI_API_KEY` - Azure API key
  - `AZURE_OPENAI_BASE_URL` - Base URL (e.g., https://your-resource.openai.azure.com/openai)

  Deployment names default to model IDs unless explicitly specified.
  """

  use ReqLLM.ProviderTest.Comprehensive, provider: :azure
end
