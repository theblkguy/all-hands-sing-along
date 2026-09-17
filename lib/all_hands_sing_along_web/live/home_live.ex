# lib/all_hands_sing_along_web/live/home_live.ex
defmodule AllHandsSingAlongWeb.HomeLive do
  @moduledoc """
  Create or join a karaoke room.
  """
  use AllHandsSingAlongWeb, :live_view

  alias AllHandsSingAlong.Rooms.SessionForm
  alias AllHandsSingAlongWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    socket = assign_new(socket, :current_user, fn -> nil end)
    user = socket.assigns.current_user
    prefill = if user, do: %{"display_name" => user.name}, else: %{}

    {:ok,
     assign(socket,
       page_title: "All Hands Sing Song",
       stem_mode: AllHandsSingAlong.Catalog.StemSeparator.mode(),
       needs_sign_in?: UserAuth.required?() and is_nil(user),
       host_form: to_form(SessionForm.host_changeset(prefill), as: :host),
       join_form: to_form(SessionForm.join_changeset(prefill), as: :join)
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
    <Layouts.app flash={@flash} current_user={@current_user}>
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

        <p
          :if={@stem_mode == :remote_worker}
          id="host-mac-setup"
          class="text-sm leading-relaxed text-white/55"
        >
          Want vocals stripped? First-time setup is in <a
            href="https://github.com/theblkguy/all-hands-sing-along#mac-worker-fallback"
            class="text-amber-100/90 underline decoration-amber-100/30 underline-offset-4 transition hover:text-white"
          >
            the README
          </a>. Then, in the room, show the Mac command and run it from the project folder.
        </p>

        <p
          :if={@stem_mode != :remote_worker}
          id="host-no-setup"
          class="text-sm leading-relaxed text-white/55"
        >
          Nothing to install. Upload a song and vocals come off automatically; tracks anyone has
          used before are ready instantly.
        </p>

        <section
          :if={@needs_sign_in?}
          id="sign-in-panel"
          class="glass-panel flex flex-col items-start gap-4 rounded-3xl p-6 sm:flex-row sm:items-center sm:justify-between"
        >
          <div>
            <h2 class="text-lg font-medium text-white">Sign in to sing</h2>
            <p class="mt-1 text-sm leading-relaxed text-white/60">
              Use your work Google account. Your name comes from your profile.
            </p>
          </div>
          <a
            id="sign-in-google"
            href={~p"/auth/google"}
            class="btn btn-primary inline-flex items-center gap-2"
          >
            <svg viewBox="0 0 24 24" class="size-4" aria-hidden="true">
              <path
                fill="currentColor"
                d="M21.6 12.2c0-.7-.1-1.4-.2-2H12v3.9h5.4a4.6 4.6 0 0 1-2 3v2.5h3.2c1.9-1.7 3-4.3 3-7.4Z"
              />
              <path
                fill="currentColor"
                opacity=".7"
                d="M12 22c2.7 0 5-.9 6.6-2.4l-3.2-2.5c-.9.6-2 1-3.4 1a6 6 0 0 1-5.6-4.1H3.1v2.6A10 10 0 0 0 12 22Z"
              />
              <path
                fill="currentColor"
                opacity=".5"
                d="M6.4 14a6 6 0 0 1 0-3.9V7.4H3.1a10 10 0 0 0 0 9.2L6.4 14Z"
              />
              <path
                fill="currentColor"
                opacity=".85"
                d="M12 6c1.5 0 2.8.5 3.8 1.5l2.9-2.9A10 10 0 0 0 3.1 7.4L6.4 10A6 6 0 0 1 12 6Z"
              />
            </svg>
            Sign in with Google
          </a>
        </section>

        <div :if={not @needs_sign_in?} class="grid gap-6 md:grid-cols-2">
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
