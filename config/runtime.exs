import Config

# Runtime configuration for LLM providers
# This file is executed at runtime, allowing environment variable configuration

# LLM Provider Configuration
#
# JidoCode requires explicit provider configuration - there is no default.
# Configure via environment variables or this file.
#
# Environment variables:
#   JIDO_CODE_PROVIDER - Provider name (e.g., "anthropic", "openai", "openrouter")
#   JIDO_CODE_MODEL    - Model name (e.g., "claude-3-5-sonnet-20241022")
#
# Provider-specific API keys are read by JidoAI's Keyring system:
#   ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY, etc.

config :jido_code, :llm,
  provider: System.get_env("JIDO_CODE_PROVIDER"),
  model: System.get_env("JIDO_CODE_MODEL"),
  temperature: 0.7,
  max_tokens: 4096
