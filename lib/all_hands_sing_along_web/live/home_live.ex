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

        <section id="how-it-works" class="space-y-4">
          <h2 class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">
            How it works
          </h2>
          <div class="grid gap-4 sm:grid-cols-3">
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <p class="flex size-8 items-center justify-center rounded-full border border-amber-200/30 bg-amber-200/10 text-sm font-medium text-amber-100">
                1
              </p>
              <h3 class="mt-4 font-medium text-white">Host a room</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                Create a room and share the code so everyone lands in the same queue.
              </p>
            </div>
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <p class="flex size-8 items-center justify-center rounded-full border border-amber-200/30 bg-amber-200/10 text-sm font-medium text-amber-100">
                2
              </p>
              <h3 class="mt-4 font-medium text-white">Add songs</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                Anyone can join the queue with a title and artist. Audio is optional.
              </p>
            </div>
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <p class="flex size-8 items-center justify-center rounded-full border border-amber-200/30 bg-amber-200/10 text-sm font-medium text-amber-100">
                3
              </p>
              <h3 class="mt-4 font-medium text-white">Host hits Play</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                When a song is Ready, the host starts the singer. Headphones on. Zoom for faces.
              </p>
            </div>
          </div>
        </section>

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
