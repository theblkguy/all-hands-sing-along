# lib/all_hands_sing_along_web/live/room_live.ex
defmodule AllHandsSingAlongWeb.RoomLive do
  @moduledoc """
  Shared karaoke room: queue, presence, and host playback controls.
  """
  use AllHandsSingAlongWeb, :live_view

  alias AllHandsSingAlong.Catalog.Song
  alias AllHandsSingAlong.Catalog.Uploads
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlongWeb.Presence
  alias AllHandsSingAlongWeb.RoomLive.Auth
  alias AllHandsSingAlongWeb.RoomLive.Lyrics
  alias AllHandsSingAlongWeb.RoomLive.Playback
  alias AllHandsSingAlongWeb.RoomLive.Queue, as: QueueEvents

  import AllHandsSingAlongWeb.Onboarding, only: [gate: 1]
  import AllHandsSingAlongWeb.RoomLive.HTML, only: [room: 1]

  @impl true
  def mount(%{"code" => code}, session, socket) do
    display_name = session["display_name"]
    guest_id = session["guest_id"] || Ecto.UUID.generate()

    with {:ok, room} <- Rooms.get_room_by_code(code),
         true <- is_binary(display_name) and display_name != "" do
      host_token = Auth.host_token_from_session(session, room.code)
      host? = Rooms.host?(room, host_token)

      socket =
        socket
        |> Auth.put_host_token(host_token)
        |> assign(:room, room)
        |> assign(:host?, host?)
        |> assign(:display_name, display_name)
        |> assign(:page_title, "Room #{room.code}")
        |> assign(:playback, Rooms.playback_snapshot(room))
        |> assign(:presence, [])
        |> assign(:song_form, to_form(Song.changeset(%Song{}, %{}), as: :song))
        |> assign(:lyric_search, nil)
        |> assign(:lyric_preview, nil)
        |> assign(:changing_lyrics_id, nil)
        |> assign(:attaching_audio_id, nil)
        |> assign(:stem_local?, AllHandsSingAlong.Catalog.StemSeparator.local_available?())
        |> assign(:host_token, nil)
        |> assign(:show_worker_command?, false)
        |> assign(:show_onboarding?, false)
        |> allow_upload(:audio,
          accept: Uploads.audio_accept(),
          max_entries: 1,
          max_file_size: Uploads.max_audio_bytes()
        )
        |> allow_upload(:lrc,
          accept: Uploads.lrc_accept(),
          max_entries: 1,
          max_file_size: Uploads.max_lrc_bytes()
        )
        |> allow_upload(:late_audio,
          accept: Uploads.audio_accept(),
          max_entries: 1,
          max_file_size: Uploads.max_audio_bytes()
        )
        |> stream(:queue, Queue.list_entries(room.id))

      socket =
        if connected?(socket) do
          topic = Queue.topic(room.code)
          Phoenix.PubSub.subscribe(AllHandsSingAlong.PubSub, topic)

          {:ok, _} =
            Presence.track(self(), topic, guest_id, %{name: display_name, host?: host?})

          socket
          |> assign_presence()
          |> Playback.push_sync()
        else
          socket
        end

      {:ok, socket}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Room not found")
         |> redirect(to: ~p"/")}

      false ->
        {:ok,
         socket
         |> put_flash(:error, "Enter your name to join")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("open_onboarding", _params, socket) do
    {:noreply, assign(socket, :show_onboarding?, true)}
  end

  def handle_event("dismiss_onboarding", _params, socket) do
    {:noreply, assign(socket, :show_onboarding?, false)}
  end

  def handle_event("reveal_worker_command", _params, socket) do
    if socket.assigns.host? do
      {:noreply,
       socket
       |> assign(:show_worker_command?, true)
       |> assign(:host_token, Auth.host_token(socket))}
    else
      {:noreply, put_flash(socket, :error, "Only the host can do that")}
    end
  end

  def handle_event("play", _params, socket), do: Playback.play(socket)
  def handle_event("pause", _params, socket), do: Playback.pause(socket)
  def handle_event("skip", _params, socket), do: Playback.skip(socket)

  def handle_event("tune_lyrics", %{"id" => id}, socket), do: Lyrics.tune(socket, id)
  def handle_event("close_lyric_preview", _params, socket), do: Lyrics.close_preview_event(socket)

  def handle_event("nudge_preview", %{"delta" => delta}, socket),
    do: Lyrics.nudge_preview(socket, delta)

  def handle_event("toggle_change_lyrics", %{"id" => id}, socket),
    do: Lyrics.toggle_change(socket, id)

  def handle_event("nudge_lyrics", %{"delta" => delta}, socket),
    do: Lyrics.nudge_playback(socket, delta)

  def handle_event("search_lyrics", params, socket), do: Lyrics.search(socket, params)

  def handle_event("pick_lyrics", %{"id" => id, "lrclib-id" => lrclib_id}, socket),
    do: Lyrics.pick(socket, id, lrclib_id)

  def handle_event("paste_lyrics", %{"entry_id" => id, "lrc_text" => lrc_text}, socket),
    do: Lyrics.paste(socket, id, lrc_text)

  def handle_event("validate_late_audio", _params, socket),
    do: QueueEvents.validate_late_audio(socket)

  def handle_event("start_attach_audio", %{"id" => id}, socket),
    do: QueueEvents.start_attach_audio(socket, id)

  def handle_event("attach_audio", %{"entry_id" => id}, socket),
    do: QueueEvents.attach_audio(socket, id)

  def handle_event("validate_queue", params, socket) when is_map(params),
    do: QueueEvents.validate(socket, params)

  def handle_event("add_to_queue", params, socket) when is_map(params),
    do: QueueEvents.add(socket, params)

  def handle_event("move_ready", %{"id" => id, "direction" => direction}, socket),
    do: QueueEvents.move_ready(socket, id, direction)

  def handle_event("retry_stems", %{"id" => id}, socket), do: QueueEvents.retry_stems(socket, id)

  def handle_event("cancel_stems", %{"id" => id}, socket),
    do: QueueEvents.cancel_stems(socket, id)

  def handle_event("use_original", %{"id" => id}, socket),
    do: QueueEvents.use_original(socket, id)

  @impl true
  def handle_info({:queue_updated, _room_id}, socket) do
    {:noreply, stream(socket, :queue, Queue.list_entries(socket.assigns.room.id), reset: true)}
  end

  def handle_info({:playback, playback}, socket) do
    {:noreply, Playback.sync(socket, playback)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_presence(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.gate
        host?={@host?}
        stem_local?={@stem_local?}
        show?={@show_onboarding?}
        room_code={@room.code}
      />
      <.room {assigns} />
    </Layouts.app>
    """
  end

  defp assign_presence(socket) do
    people =
      socket.assigns.room.code
      |> Queue.topic()
      |> Presence.list()
      |> Enum.map(fn {_key, %{metas: [meta | _]}} ->
        %{name: meta.name, host?: Map.get(meta, :host?, false)}
      end)

    assign(socket, :presence, people)
  end
end
