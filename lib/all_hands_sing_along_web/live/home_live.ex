# lib/all_hands_sing_along_web/live/home_live.ex
defmodule AllHandsSingAlongWeb.HomeLive do
  @moduledoc """
  Create or join a karaoke room.
  """
  use AllHandsSingAlongWeb, :live_view

  alias AllHandsSingAlong.Rooms.SessionForm

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "All Hands Sing Song",
       host_form: to_form(SessionForm.host_changeset(%{}), as: :host),
       join_form: to_form(SessionForm.join_changeset(%{}), as: :join)
     )}
  end

  @impl true
  def handle_event("validate_host", params, socket) do
    changeset =
      params
      |> SessionForm.host_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, host_form: to_form(changeset, as: :host))}
  end

  def handle_event("validate_join", params, socket) do
    changeset =
      params
      |> SessionForm.join_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, join_form: to_form(changeset, as: :join))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-10 pt-6">
        <div class="max-w-xl space-y-4">
          <p class="text-xs font-medium uppercase tracking-[0.28em] text-amber-100/70">
            Karaoke night
          </p>
          <h1 class="text-4xl font-semibold tracking-tight text-white sm:text-5xl">
            All Hands Sing Song
          </h1>
          <p class="text-base leading-relaxed text-white/65">
            Someone hosts. Everyone else opens this page for the songs and lyrics.
            Stay on Zoom for faces, and wear headphones so the track doesn't leak into the call.
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
                Make a room and send people the code.
              </p>
            </div>
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <.step_item n={2} class="size-8 text-sm" />
              <h3 class="mt-4 font-medium text-white">Add a song</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                Put your name on a title and artist. You can add audio now or later.
              </p>
            </div>
            <div class="glass-panel rounded-3xl p-5 transition duration-200 hover:border-amber-200/25 hover:bg-white/[0.07]">
              <.step_item n={3} class="size-8 text-sm" />
              <h3 class="mt-4 font-medium text-white">Host hits Play</h3>
              <p class="mt-2 text-sm leading-relaxed text-white/60">
                When a song is Ready, the host starts the singer.
              </p>
            </div>
          </div>
        </section>

        <p id="host-mac-setup" class="text-sm leading-relaxed text-white/55">
          Want vocals stripped? First-time setup is in <a
            href="https://github.com/theblkguy/all-hands-sing-along#host-strip-vocals-with-demucs"
            class="text-amber-100/90 underline decoration-amber-100/30 underline-offset-4 transition hover:text-white"
          >
            the README
          </a>. Then, in the room, show the Mac command and run it from the project folder.
        </p>

        <div class="grid gap-6 md:grid-cols-2">
          <.form
            for={@host_form}
            as={:host}
            action={~p"/session/host"}
            method="post"
            id="create-room-form"
            phx-change="validate_host"
            class="glass-panel space-y-4 rounded-3xl p-6"
          >
            <h2 class="text-lg font-medium text-white">Host a room</h2>
            <.input field={@host_form[:display_name]} label="Your name" />
            <.button type="submit" variant="primary">Create room</.button>
          </.form>

          <.form
            for={@join_form}
            as={:join}
            action={~p"/session/join"}
            method="post"
            id="join-room-form"
            phx-change="validate_join"
            class="glass-panel space-y-4 rounded-3xl p-6"
          >
            <h2 class="text-lg font-medium text-white">Join a room</h2>
            <p id="join-no-install" class="text-sm leading-relaxed text-white/55">
              Just the room code. Nothing to install.
            </p>
            <.input field={@join_form[:display_name]} label="Your name" />
            <.input field={@join_form[:code]} label="Room code" />
            <.button type="submit">Join</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
