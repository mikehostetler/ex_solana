import Config

# to provide built-in test partitioning in CI environment.
# Configure your database
# Run `mix help test` for more information.
#
# We don't run a server during test. If one is required,
# In test we don't send emails
# you can enable the server option below.
# The MIX_TEST_PARTITION environment variable can be used

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

config :bcrypt_elixir, log_rounds: 1

config :jido_hub, JidoHub.Mailer, adapter: Swoosh.Adapters.Test

config :jido_hub, JidoHub.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "jido_hub_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :jido_hub, JidoHubWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YzVhMrZf35ngKG8IvgiIirZjicZUmJ3bHITMwzXfJthMtRYRpuIW5shwcMcyju7N",
  server: true

# Disable rate limiting in tests to avoid flakiness
config :jido_hub, JidoHubWeb.Plugs.RateLimit, enabled: false
config :jido_hub, Oban, testing: :manual
config :jido_hub, :env, :test
config :jido_hub, dev_routes: false, token_signing_secret: "C9VUNuTTtIM648esimuGcwjYA0xg/oBa"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix_test,
  endpoint: JidoHubWeb.Endpoint,
  otp_app: :jido_hub,
  base_url: "http://localhost:4002"

config :phoenix_test_playwright, endpoint: JidoHubWeb.Endpoint

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
