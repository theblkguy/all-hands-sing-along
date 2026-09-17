# lib/all_hands_sing_along_web/live/home_live.ex
defmodule AllHandsSingAlongWeb.HomeLive do
  @moduledoc """
  Create or join a karaoke room.
  """
  use AllHandsSingAlongWeb, :live_view

  alias AllHandsSingAlong.Accounts
  alias AllHandsSingAlong.Accounts.User
  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlong.Rooms.SessionForm
  alias AllHandsSingAlongWeb.UserAuth

  @impl true
  def mount(_params, session, socket) do
    socket = assign_new(socket, :current_user, fn -> nil end)
    user = socket.assigns.current_user
    signed_in? = match?(%User{}, user)
    needs_sign_in? = UserAuth.required?() and is_nil(user)
    needs_username? = UserAuth.required?() and signed_in? and not User.username?(user)

    {:ok,
     socket
     |> assign(
       page_title: "All Hands Sing Song",
       stem_mode: AllHandsSingAlong.Catalog.StemSeparator.mode(),
       needs_sign_in?: needs_sign_in?,
       needs_username?: needs_username?,
       signed_in?: signed_in?,
       return_to: session["user_return_to"],
       past_rooms: past_rooms(user, needs_username?)
     )
     |> assign_username_form(user)
     |> assign_session_forms(user, signed_in?)}
  end

  @impl true
  def handle_event("validate_host", params, socket) do
    changeset =
      params
      |> SessionForm.host_changeset(signed_in: socket.assigns.signed_in?)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, host_form: to_form(changeset, as: :host))}
  end

  def handle_event("validate_join", params, socket) do
    changeset =
      params
      |> SessionForm.join_changeset(signed_in: socket.assigns.signed_in?)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, join_form: to_form(changeset, as: :join))}
  end

  def handle_event("validate_username", params, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_username(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, username_form: to_form(changeset, as: :user))}
  end

  def handle_event("save_username", params, socket) do
    first_pick? = socket.assigns.needs_username?

    case Accounts.update_username(socket.assigns.current_user, params) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:needs_username?, false)
          |> assign(:past_rooms, past_rooms(user, false))
          |> assign_username_form(user)
          |> assign_session_forms(user, true)

        if first_pick? and is_binary(socket.assigns.return_to) do
          {:noreply, redirect(socket, to: socket.assigns.return_to)}
        else
          {:noreply, socket}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, username_form: to_form(changeset, as: :user))}
    end
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
              <h3 class="mt-4 font-medium text-white">Host starts the song</h3>
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
          Want vocals removed? First-time setup is in <a
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
              Use your work Google account.
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

        <.form
          :if={@signed_in? and not @needs_sign_in?}
          for={@username_form}
          id="username-form"
          phx-change="validate_username"
          phx-submit="save_username"
          class="glass-panel space-y-4 rounded-3xl p-6"
        >
          <h2 class="text-lg font-medium text-white">
            {if @needs_username?, do: "Pick a username", else: "Username"}
          </h2>
          <p :if={@needs_username?} class="text-sm leading-relaxed text-white/60">
            This is what the room shows. Letters, numbers, underscore.
          </p>
          <.input field={@username_form[:username]} id="username" label="Username" />
          <.button type="submit" variant="primary">
            {if @needs_username?, do: "Save", else: "Update"}
          </.button>
        </.form>

        <section
          :if={not @needs_sign_in? and not @needs_username? and @past_rooms != []}
          id="past-rooms"
          class="space-y-4"
        >
          <h2 class="text-lg font-medium text-white">Rooms you were in</h2>
          <ul class="grid gap-3 sm:grid-cols-2">
            <li :for={room <- @past_rooms} id={"past-room-#{room.code}"}>
              <.form
                for={%{}}
                action={~p"/session/join"}
                method="post"
                id={"rejoin-#{room.code}"}
                class="glass-panel flex items-center justify-between gap-3 rounded-2xl p-4"
              >
                <input type="hidden" name="join[code]" value={room.code} />
                <span class="font-mono text-lg tracking-[0.18em] text-white">{room.code}</span>
                <.button type="submit">Open</.button>
              </.form>
            </li>
          </ul>
        </section>

        <div :if={not @needs_sign_in? and not @needs_username?} class="grid gap-6 md:grid-cols-2">
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
            <.input :if={not @signed_in?} field={@host_form[:display_name]} label="Your name" />
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
            <.input :if={not @signed_in?} field={@join_form[:display_name]} label="Your name" />
            <.input field={@join_form[:code]} label="Room code" />
            <.button type="submit">Join</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_username_form(socket, %User{} = user) do
    assign(socket, username_form: to_form(Accounts.change_username(user), as: :user))
  end

  defp assign_username_form(socket, _), do: assign(socket, username_form: nil)

  defp assign_session_forms(socket, user, signed_in?) do
    prefill =
      cond do
        signed_in? -> %{}
        user -> %{"display_name" => user.name}
        true -> %{}
      end

    assign(socket,
      host_form: to_form(SessionForm.host_changeset(prefill, signed_in: signed_in?), as: :host),
      join_form: to_form(SessionForm.join_changeset(prefill, signed_in: signed_in?), as: :join)
    )
  end

  defp past_rooms(_user, true), do: []
  defp past_rooms(%User{} = user, _), do: Rooms.list_rooms_for_user(user)
  defp past_rooms(_, _), do: []
end
