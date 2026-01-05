import Config

if config_env() == :prod do
  config :karo, Karo.Repo, database: System.get_env("KARO_DB_PATH", "priv/karo.sqlite3")

  config :karo,
    llm: [
      provider: :openai,
      model: System.get_env("KARO_LLM_MODEL", "gpt-4o-mini"),
      api_key: System.fetch_env!("OPENAI_API_KEY")
    ]

  config :nostrum,
    token: System.fetch_env!("DISCORD_BOT_TOKEN"),
    gateway_intents: [:guilds, :guild_messages, :direct_messages, :message_content]
end
