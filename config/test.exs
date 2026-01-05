import Config

config :karo, Karo.Repo,
  database: "priv/karo_test.sqlite3",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

# Nostrum requires a token in Bot token format (MTIz...) but we won't connect
# Use a dummy token that passes format validation
config :nostrum,
  token: "MTIzNDU2Nzg5MDEyMzQ1Njc4.ABCDEF.ABCDEFghijklmnopqrstuvwxyz123456"
