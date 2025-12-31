import Config

# Reduce log noise during tests
# Using :none to suppress all logs including GenServer crash reports from hierarchy tests
# Tests that need to assert on logs should be skipped or use explicit log level override
config :logger, level: :none
