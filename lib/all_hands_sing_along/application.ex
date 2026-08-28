defmodule AllHandsSingAlong.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AllHandsSingAlongWeb.Telemetry,
      AllHandsSingAlong.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:all_hands_sing_along, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster,
       query: Application.get_env(:all_hands_sing_along, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AllHandsSingAlong.PubSub},
      {Registry, keys: :unique, name: AllHandsSingAlong.Rooms.Registry},
      AllHandsSingAlong.Rooms.PlaybackSupervisor,
      AllHandsSingAlong.Catalog.StemSeparator,
      AllHandsSingAlongWeb.Presence,
      AllHandsSingAlongWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AllHandsSingAlong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AllHandsSingAlongWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
