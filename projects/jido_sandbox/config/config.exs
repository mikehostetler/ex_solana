import Config

# Default sandbox configuration
config :jido_sandbox,
  default_vfs: :in_memory

# Import environment specific config
import_config "#{config_env()}.exs"
