import Config

config :karo, Karo.Repo, database: "priv/karo_dev.sqlite3"

config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN")
