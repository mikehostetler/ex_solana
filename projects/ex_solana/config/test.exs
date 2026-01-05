import Config

config :ex_solana, ExSolana.TestValidator,
  ledger: "/tmp/test-ledger",
  programs: [
    %{name: "raydium_amm", path: "path/to/your/raydium_amm.so"},
    %{name: "other_program", path: "path/to/your/other_program.so"}
  ]

config :ex_solana,
  rpc: [
    network: "localhost"
  ],
  websocket: [
    url: "ws://localhost",
    reconnect_interval: 5000
  ],
  cache: [
    enabled: false
  ],
  verbose: false
