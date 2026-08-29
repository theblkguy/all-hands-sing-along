# lib/all_hands_sing_along_web/live/home_live.ex
defmodule AllHandsSingAlongWeb.HomeLive do
  @moduledoc """
  Create or join a karaoke room.
  """
  use AllHandsSingAlongWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "All Hands Sing Song")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-10 pt-6">
        <div class="max-w-xl space-y-4">
          <p class="text-xs font-medium uppercase tracking-[0.28em] text-amber-100/70">
            Zoom companion
          </p>
          <h1 class="text-4xl font-semibold tracking-tight text-white sm:text-5xl">
            All Hands Sing Song
          </h1>
          <p class="text-base leading-relaxed text-white/65">
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
            class="glass-panel space-y-4 rounded-3xl p-6"
          >
            <h2 class="text-lg font-medium text-white">Host a room</h2>
            <.input name="display_name" label="Your name" value="" required />
            <.button type="submit" variant="primary">Create room</.button>
          </.form>

          <.form
            for={%{}}
            as={:guest}
            action={~p"/session/join"}
            method="post"
            id="join-room-form"
            class="glass-panel space-y-4 rounded-3xl p-6"
          >
            <h2 class="text-lg font-medium text-white">Join a room</h2>
            <.input name="display_name" label="Your name" value="" required />
            <.input name="code" label="Room code" value="" required />
            <.button type="submit">Join</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
