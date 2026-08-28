defmodule AllHandsSingAlong.Repo do
  use Ecto.Repo,
    otp_app: :all_hands_sing_along,
    adapter: Ecto.Adapters.SQLite3
end
