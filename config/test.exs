import Config

# Test configuration
config :llm_db,
  compile_embed: false,
  integrity_policy: :warn,
  # Use test-specific cache directory to avoid polluting production cache
  models_dev_cache_dir: "tmp/test/upstream",
  openrouter_cache_dir: "tmp/test/upstream",
  upstream_cache_dir: "tmp/test/upstream"
