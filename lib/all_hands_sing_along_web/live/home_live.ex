# lib/all_hands_sing_along_web/live/home_live.ex
defmodule AllHandsSingAlongWeb.HomeLive do
  @moduledoc """
  Create or join a karaoke room.
  """
  use AllHandsSingAlongWeb, :live_view

  @brew_cmd ~S|/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"|

  @clone_cmd Enum.join(
               [
                 "git clone https://github.com/theblkguy/all-hands-sing-along.git",
                 "cd all-hands-sing-along",
                 "./script/setup"
               ],
               "\n"
             )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "All Hands Sing Song",
       brew_cmd: @brew_cmd,
       clone_cmd: @clone_cmd
     )}
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
              <.step_item n={1} class="size-8 text-sm" />
              <h3 class="mt-4 font-medium text-white">Host a room</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                Create a room and share the code so everyone lands in the same queue.
              </p>
            </div>
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <.step_item n={2} class="size-8 text-sm" />
              <h3 class="mt-4 font-medium text-white">Add songs</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                Anyone can join the queue with a title and artist. Audio is optional.
              </p>
            </div>
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <.step_item n={3} class="size-8 text-sm" />
              <h3 class="mt-4 font-medium text-white">Host hits Play</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                When a song is Ready, the host starts the singer. Headphones on. Zoom for faces.
              </p>
            </div>
          </div>
        </section>

        <section id="host-mac-setup" class="glass-panel space-y-6 rounded-3xl p-6 sm:p-8">
          <div class="max-w-2xl space-y-2">
            <h2 class="text-lg font-medium text-white">Host from a Mac</h2>
            <p class="text-sm leading-relaxed text-white/65">
              Your Mac strips vocals (Demucs) so people can sing over the track. One-time, about 15–30
              minutes. Guests do not install anything. Leave Terminal open later while people sing.
            </p>
          </div>

          <ol class="space-y-6">
            <li class="flex gap-4">
              <.step_item n={1} class="mt-0.5 size-8 text-sm" />
              <div class="min-w-0 flex-1">
                <h3 class="font-medium text-white">Homebrew</h3>
                <p class="mt-1 text-sm leading-relaxed text-white/60">
                  Skip if <code class="text-amber-100/80">brew --version</code>
                  works. On Apple Silicon,
                  follow Homebrew’s PATH “Next steps”, then open a new Terminal.
                </p>
                <.copy_snippet id="copy-setup-brew" text={@brew_cmd} />
              </div>
            </li>
            <li class="flex gap-4">
              <.step_item n={2} class="mt-0.5 size-8 text-sm" />
              <div class="min-w-0 flex-1">
                <h3 class="font-medium text-white">Clone and install</h3>
                <p class="mt-1 text-sm leading-relaxed text-white/60">
                  This installs Demucs, ffmpeg, and Elixir. If setup says
                  <code class="text-amber-100/80">mix</code>
                  was not found, open a new Terminal and run
                  <code class="text-amber-100/80">./script/setup</code>
                  again.
                </p>
                <.copy_snippet id="copy-setup-clone" text={@clone_cmd} />
              </div>
            </li>
            <li class="flex gap-4">
              <.step_item n={3} class="mt-0.5 size-8 text-sm" />
              <div class="min-w-0 flex-1">
                <h3 class="font-medium text-white">Create the room below</h3>
                <p class="mt-1 text-sm leading-relaxed text-white/60">
                  The next page shows the last command: <code class="text-amber-100/80">./script/worker --room … --token …</code>.
                  Run it from that project folder. Guests never need this.
                </p>
              </div>
            </li>
          </ol>
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
            <p id="join-no-install" class="text-sm leading-relaxed text-white/55">
              No install. Ask the host for the room code.
            </p>
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
