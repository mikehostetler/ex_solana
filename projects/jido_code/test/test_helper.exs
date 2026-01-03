# Compile test support modules
Code.require_file("support/env_isolation.ex", __DIR__)
Code.require_file("support/manager_isolation.ex", __DIR__)
Code.require_file("support/session_isolation.ex", __DIR__)

# Ensure JidoCode application infrastructure is started before running tests
# This ensures all GenServers, Registries, and Supervisors are initialized
{:ok, _} = Application.ensure_all_started(:jido_code)

# Ensure all required ETS tables exist before any tests run
# This prevents race conditions when tests run in parallel
JidoCode.TestHelpers.SessionIsolation.ensure_tables_exist()

# Exclude LLM integration tests by default
# Run with: mix test --include llm
ExUnit.start(exclude: [:llm])
