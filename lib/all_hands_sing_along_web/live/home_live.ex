# lib/all_hands_sing_along_web/live/home_live.ex
defmodule AllHandsSingAlongWeb.HomeLive do
  @moduledoc """
  Create or join a karaoke room.
  """
  use AllHandsSingAlongWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "All Hands SingAlong")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <div>
          <p class="badge badge-soft mb-3">Zoom companion</p>
          <h1 class="text-3xl font-semibold">All Hands SingAlong</h1>
          <p class="mt-2 text-base-content/70">
            One host runs the queue. Everyone opens this page so the song and lyrics stay in sync.
            Stay on Zoom for faces. Use headphones.
          </p>
        </div>

        <div class="grid gap-6 md:grid-cols-2">
          <.form
            for={%{}}
            as={:host}
            action={~p"/session/host"}
            method="post"
            id="create-room-form"
            class="card bg-base-200 shadow-sm"
          >
            <div class="card-body space-y-3">
              <h2 class="card-title">Host a room</h2>
              <.input name="display_name" label="Your name" value="" required />
              <.button type="submit" variant="primary">Create room</.button>
            </div>
          </.form>

          <.form
            for={%{}}
            as={:guest}
            action={~p"/session/join"}
            method="post"
            id="join-room-form"
            class="card bg-base-200 shadow-sm"
          >
            <div class="card-body space-y-3">
              <h2 class="card-title">Join a room</h2>
              <.input name="display_name" label="Your name" value="" required />
              <.input name="code" label="Room code" value="" required />
              <.button type="submit">Join</.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
