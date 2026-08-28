# lib/all_hands_sing_along_web/router.ex
defmodule AllHandsSingAlongWeb.Router do
  use AllHandsSingAlongWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AllHandsSingAlongWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AllHandsSingAlongWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/rooms/:code", RoomLive, :show

    post "/session/host", SessionController, :create_host
    post "/session/join", SessionController, :join
  end

  if Application.compile_env(:all_hands_sing_along, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AllHandsSingAlongWeb.Telemetry
    end
  end
end
