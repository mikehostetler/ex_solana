# Compile test support modules
Code.require_file("support/env_isolation.ex", __DIR__)
Code.require_file("support/manager_isolation.ex", __DIR__)

ExUnit.start()
