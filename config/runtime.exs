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

# Session Persistence Configuration
#
# Controls limits and behavior for session file persistence.
#
# Environment variables:
#   JIDO_MAX_SESSION_SIZE - Maximum session file size in bytes (default: 10MB)
#   JIDO_MAX_SESSIONS     - Maximum number of persisted sessions (default: 100)
#   JIDO_CLEANUP_DAYS     - Age threshold for auto-cleanup in days (default: 30)

config :jido_code, :persistence,
  max_file_size: System.get_env("JIDO_MAX_SESSION_SIZE", "10485760") |> String.to_integer(),
  max_sessions: System.get_env("JIDO_MAX_SESSIONS", "100") |> String.to_integer(),
  cleanup_age_days: System.get_env("JIDO_CLEANUP_DAYS", "30") |> String.to_integer()

# Rate Limiting Configuration
#
# Controls rate limits for operations like session resume.
#
# Environment variables:
#   JIDO_RESUME_LIMIT   - Max resume attempts per window (default: 5)
#   JIDO_RESUME_WINDOW  - Time window in seconds (default: 60)

config :jido_code, :rate_limits,
  resume: [
    limit: System.get_env("JIDO_RESUME_LIMIT", "5") |> String.to_integer(),
    window_seconds: System.get_env("JIDO_RESUME_WINDOW", "60") |> String.to_integer()
  ],
  cleanup_interval: :timer.minutes(5)
