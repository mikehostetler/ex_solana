[
  import_deps: [
    :ash_typescript,
    :ash_ai,
    :ash_oban,
    :oban,
    :ash_admin,
    :ash_authentication_phoenix,
    :ash_authentication,
    :ash_postgres,
    :ash_json_api,
    :ash_phoenix,
    :ash,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter, Quokka],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
