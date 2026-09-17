# lib/all_hands_sing_along_web/router.ex
defmodule AllHandsSingAlongWeb.Router do
  use AllHandsSingAlongWeb, :router

  import AllHandsSingAlongWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AllHandsSingAlongWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  # Audio for <audio> tags: needs the session cookie to prove sign-in, but no
  # HTML content negotiation or CSRF.
  pipeline :media do
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :require_user do
    plug :require_authenticated_user
    plug :require_username
  end

  scope "/", AllHandsSingAlongWeb do
    get "/health", HealthController, :show
  end

  # The Mac worker authenticates with the room's host token, not a Google
  # session. Unchanged.
  scope "/internal", AllHandsSingAlongWeb do
    post "/stems/claim", StemWorkerController, :claim
    post "/stems/:id/progress", StemWorkerController, :progress
    post "/stems/:id/complete", StemWorkerController, :complete
    post "/stems/:id/fail", StemWorkerController, :fail
  end

  # Sign-in round trip: reachable while signed out, obviously.
  scope "/auth", AllHandsSingAlongWeb do
    pipe_through :browser

    get "/google", AuthController, :request
    get "/google/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  # Everything people actually use. When Google auth is configured, these all
  # require a signed-in user; otherwise they're open, as before.
  scope "/", AllHandsSingAlongWeb do
    pipe_through [:media, :require_user]

    get "/uploads/:filename", UploadController, :show
  end

  scope "/", AllHandsSingAlongWeb do
    pipe_through [:browser, :require_user]

    post "/session/host", SessionController, :create_host
    post "/session/join", SessionController, :join

    # Host recovery link. Opening it in any browser (phone, second laptop,
    # after clearing cookies) makes that browser the host.
    get "/rooms/:code/host/:token", SessionController, :claim_host

    live_session :rooms, on_mount: [{AllHandsSingAlongWeb.UserAuth, :require_user}] do
      live "/rooms/:code", RoomLive, :show
    end
  end

  # The front door renders a Sign in button when signed out instead of bouncing
  # straight to Google.
  scope "/", AllHandsSingAlongWeb do
    pipe_through :browser

    live_session :home, on_mount: [{AllHandsSingAlongWeb.UserAuth, :mount_current_user}] do
      live "/", HomeLive, :index
    end
  end

  if Application.compile_env(:all_hands_sing_along, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AllHandsSingAlongWeb.Telemetry
    end
  end
end
