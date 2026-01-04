ExUnit.start(max_cases: 1)

Ecto.Adapters.SQL.Sandbox.mode(Karo.Repo, :manual)

Mimic.copy(Karo.ChatSession)
Mimic.copy(Karo.LLM)
