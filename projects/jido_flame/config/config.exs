import Config

config :jido_flame,
  default_pool: nil

import_config "#{config_env()}.exs"
