ExUnit.start(capture_log: true)
ExUnit.configure(exclude: [:playwright])
Ecto.Adapters.SQL.Sandbox.mode(JidoHub.Repo, :manual)
