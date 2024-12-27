import Config

# Load .env file
Dotenv.load()

# Check if the PHX_SERVER environment variable is set
if System.get_env("PHX_SERVER") do
  config :coinflips, CoinflipsWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Load DATABASE_URL from environment
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :coinflips, Coinflips.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # Fetching critical secrets
  config :coinflips,
    app_private_key: System.fetch_env!("APP_PRIVATE_KEY"),
    provider_url: System.fetch_env!("PROVIDER_URL")

  # Load SECRET_KEY_BASE from environment
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Example custom ENV variables
  app_private_key =
    System.get_env("APP_PRIVATE_KEY") ||
      raise "APP_PRIVATE_KEY is missing in environment variables."

  provider_url =
    System.get_env("PROVIDER_URL") ||
      raise "PROVIDER_URL is missing in environment variables."

  config :coinflips, CoinflipsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :coinflips, :ethers,
    private_key: app_private_key,
    provider_url: provider_url
end
