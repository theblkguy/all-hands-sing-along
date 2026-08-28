# lib/all_hands_sing_along_web/presence.ex
defmodule AllHandsSingAlongWeb.Presence do
  @moduledoc false
  use Phoenix.Presence,
    otp_app: :all_hands_sing_along,
    pubsub_server: AllHandsSingAlong.PubSub
end
