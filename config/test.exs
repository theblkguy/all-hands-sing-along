import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :all_hands_sing_along, AllHandsSingAlong.Repo,
  database: Path.expand("../all_hands_sing_along_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :all_hands_sing_along, AllHandsSingAlongWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mFHq+UK59QDDU4RDtl2KGXueta6xZQvqpKh/J7prcS8oDI3VS09zQJTLC8o3FdGd",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :all_hands_sing_along, AllHandsSingAlong.Catalog.Lyrics,
  req_options: [plug: {Req.Test, AllHandsSingAlong.Catalog.Lyrics}]

config :all_hands_sing_along, AllHandsSingAlong.Catalog.StemSeparator,
  adapter: AllHandsSingAlong.Catalog.StubStemAdapter,
  enabled: true,
  sync: true
