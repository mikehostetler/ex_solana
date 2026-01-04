import Config

config :karo,
  ecto_repos: [Karo.Repo],
  ash_domains: [Karo.ChatDomain]

config :karo, Karo.Repo, database: "priv/karo_#{config_env()}.sqlite3"

config :karo,
  llm: [
    provider: :openai,
    model: "gpt-4o-mini"
  ],
  chat_session: [
    idle_timeout_ms: :timer.minutes(15),
    max_context_messages: 50
  ]

config :ash,
  disable_async?: true

import_config "#{config_env()}.exs"
