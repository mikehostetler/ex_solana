import Config

# Load .env files in dev/test if dotenv_parser is available
if config_env() in [:dev, :test] do
  if Code.ensure_loaded?(DotenvParser) do
    env_file = Path.join(File.cwd!(), ".env")

    if File.exists?(env_file) do
      DotenvParser.load_file(env_file)
    end
  end
end

# Configure FLAME backend based on environment
fly_app = System.get_env("FLY_APP_NAME")
fly_token = System.get_env("FLY_API_TOKEN")

if fly_app && fly_token do
  config :flame,
    backend: {FLAME.FlyBackend, token: fly_token, app: fly_app}
end

# Allow explicit pool configuration
if pool = System.get_env("JIDO_FLAME_DEFAULT_POOL") do
  config :jido_flame, default_pool: String.to_atom(pool)
end
