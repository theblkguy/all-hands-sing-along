# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :all_hands_sing_along,
  ecto_repos: [AllHandsSingAlong.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :all_hands_sing_along, AllHandsSingAlongWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AllHandsSingAlongWeb.ErrorHTML, json: AllHandsSingAlongWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AllHandsSingAlong.PubSub,
  live_view: [signing_salt: "R6gFKmiF"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  all_hands_sing_along: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  all_hands_sing_along: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "audio/mp4" => ["m4a"],
  "audio/ogg" => ["ogg"],
  "text/plain" => ["txt", "text", "lrc"]
}

config :all_hands_sing_along, AllHandsSingAlong.Catalog.Lyrics,
  url: "https://lrclib.net/api/get",
  search_url: "https://lrclib.net/api/search",
  req_options: []

config :all_hands_sing_along, AllHandsSingAlong.Catalog.StemSeparator,
  adapter: AllHandsSingAlong.Catalog.DemucsStemAdapter,
  python: "python3",
  vocal_mix: 0.12,
  enabled: true,
  sync: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
