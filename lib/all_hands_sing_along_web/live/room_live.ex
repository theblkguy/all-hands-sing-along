# lib/all_hands_sing_along_web/live/room_live.ex
defmodule AllHandsSingAlongWeb.RoomLive do
  @moduledoc """
  Shared karaoke room: queue, presence, and host playback controls.
  """
  use AllHandsSingAlongWeb, :live_view

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.Uploads
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlongWeb.Presence

  @impl true
  def mount(%{"code" => code}, session, socket) do
    display_name = session["display_name"]
    guest_id = session["guest_id"] || Ecto.UUID.generate()

    with {:ok, room} <- Rooms.get_room_by_code(code),
         true <- is_binary(display_name) and display_name != "" do
      host_token = host_token_from_session(session, room.code)
      host? = Rooms.host?(room, host_token)

      socket =
        socket
        |> put_host_token(host_token)
        |> assign(:room, room)
        |> assign(:host?, host?)
        |> assign(:display_name, display_name)
        |> assign(:guest_id, guest_id)
        |> assign(:page_title, "Room #{room.code}")
        |> assign(:playback, Rooms.playback_snapshot(room))
        |> assign(:presence, [])
        |> assign(:song_title, "")
        |> assign(:song_artist, "")
        |> assign(:lyric_search, nil)
        |> assign(:lyric_preview, nil)
        |> assign(:changing_lyrics_id, nil)
        |> assign(:attaching_audio_id, nil)
        |> assign(:stem_local?, AllHandsSingAlong.Catalog.StemSeparator.local_available?())
        |> assign(:host_token, if(host?, do: host_token, else: nil))
        |> allow_upload(:audio, accept: :any, max_entries: 1, max_file_size: 32_000_000)
        |> allow_upload(:lrc, accept: :any, max_entries: 1, max_file_size: 200_000)
        |> allow_upload(:instrumental, accept: :any, max_entries: 1, max_file_size: 32_000_000)
        |> allow_upload(:late_audio, accept: :any, max_entries: 1, max_file_size: 32_000_000)
        |> stream(:queue, Queue.list_entries(room.id))

      socket =
        if connected?(socket) do
          topic = Queue.topic(room.code)
          Phoenix.PubSub.subscribe(AllHandsSingAlong.PubSub, topic)

          {:ok, _} =
            Presence.track(self(), topic, guest_id, %{name: display_name, host?: host?})

          socket
          |> assign_presence()
          |> maybe_push_playback()
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
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("play", _params, socket) do
    if socket.assigns.host? do
      socket = close_lyric_preview(socket)

      case Rooms.play(socket.assigns.room, host_token(socket)) do
        {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("pause", _params, socket) do
    if socket.assigns.host? do
      case Rooms.pause(socket.assigns.room, host_token(socket)) do
        {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("skip", _params, socket) do
    if socket.assigns.host? do
      socket = close_lyric_preview(socket)

      case Rooms.skip(socket.assigns.room, host_token(socket)) do
        {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("tune_lyrics", %{"id" => id}, socket) do
    if socket.assigns.host? do
      with {:ok, entry} <- fetch_room_entry(socket, id),
           {:ok, preview} <-
             Rooms.lyric_preview(socket.assigns.room, host_token(socket), entry) do
        {:noreply, open_lyric_preview(socket, preview)}
      else
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("close_lyric_preview", _params, socket) do
    if socket.assigns.host? do
      {:noreply, close_lyric_preview(socket)}
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("nudge_preview", %{"delta" => delta}, socket) do
    case Integer.parse(to_string(delta)) do
      {ms, ""} ->
        if socket.assigns.host? do
          {:noreply, nudge_lyric_preview(socket, ms)}
        else
          {:noreply, put_flash(socket, :error, "Host only")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  def handle_event("toggle_change_lyrics", %{"id" => id}, socket) do
    if socket.assigns.host? do
      with {:ok, entry} <- fetch_room_entry(socket, id),
           true <- can_replace_lyrics?(entry) do
        current = socket.assigns.changing_lyrics_id

        socket =
          if current == entry.id do
            socket
            |> assign(:changing_lyrics_id, nil)
            |> clear_lyric_search(entry.id)
          else
            socket
            |> assign(:changing_lyrics_id, entry.id)
            |> clear_lyric_search(current)
          end

        {:noreply, restream_queue(socket)}
      else
        false -> {:noreply, put_flash(socket, :error, "Host only")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("nudge_lyrics", %{"delta" => delta}, socket) do
    case Integer.parse(to_string(delta)) do
      {ms, ""} ->
        if socket.assigns.host? do
          case Rooms.nudge_lyrics(socket.assigns.room, host_token(socket), ms) do
            {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
            {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
          end
        else
          {:noreply, put_flash(socket, :error, "Host only")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  def handle_event("search_lyrics", %{"entry_id" => id} = params, socket) do
    title = params |> Map.get("title", "") |> String.trim()
    artist = params |> Map.get("artist", "") |> String.trim()

    cond do
      title == "" or artist == "" ->
        {:noreply, put_flash(socket, :error, "Title and artist are required to search")}

      true ->
        with {:ok, entry} <- fetch_room_entry(socket, id),
             :ok <- authorize_lyric_search(socket, entry),
             {:ok, hits} <- search_lyric_hits(socket, entry, title, artist) do
          search =
            if hits == [] do
              %{
                entry_id: entry.id,
                results: [],
                error: "No matches. Try another spelling or paste an .lrc file."
              }
            else
              %{entry_id: entry.id, results: hits, error: nil}
            end

          {:noreply, socket |> assign(:lyric_search, search) |> restream_queue()}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
        end
    end
  end

  def handle_event("pick_lyrics", %{"id" => id, "lrclib-id" => lrclib_id}, socket) do
    with {:ok, entry} <- fetch_room_entry(socket, id),
         :ok <- authorize_lyric_edit(socket, entry),
         %{} = song <- entry.song,
         {:ok, lrc} <- Catalog.Lyrics.fetch_by_id(lrclib_id),
         {:ok, song} <- Catalog.apply_lrc(song, lrc),
         {:ok, entry} <- Queue.attach_song(entry, song) do
      {:noreply,
       socket
       |> finish_lyric_edit(entry)
       |> put_flash(:info, "Lyrics attached")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Add the song to the queue first")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("paste_lyrics", %{"entry_id" => id, "lrc_text" => lrc_text}, socket) do
    with {:ok, entry} <- fetch_room_entry(socket, id),
         :ok <- authorize_lyric_edit(socket, entry),
         {:ok, song} <- song_for_lyric_edit(socket, entry),
         {:ok, song} <- Catalog.apply_lrc(song, lrc_text),
         {:ok, entry} <- Queue.attach_song(entry, song) do
      {:noreply,
       socket
       |> finish_lyric_edit(entry)
       |> put_flash(:info, "Lyrics attached")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("validate_late_audio", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("start_attach_audio", %{"id" => id}, socket) do
    with {:ok, entry} <- fetch_room_entry(socket, id),
         true <- can_attach_audio?(socket, entry) do
      {:noreply,
       socket
       |> assign(:attaching_audio_id, entry.id)
       |> stream(:queue, Queue.list_entries(socket.assigns.room.id), reset: true)}
    else
      false ->
        {:noreply, put_flash(socket, :error, "You can only add audio to your own queue song")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("attach_audio", %{"entry_id" => id}, socket) do
    case fetch_room_entry(socket, id) do
      {:ok, entry} ->
        cond do
          not can_attach_audio?(socket, entry) ->
            {:noreply, put_flash(socket, :error, "You can only add audio to your own queue song")}

          not Catalog.missing_audio?(entry.song) ->
            {:noreply, put_flash(socket, :error, "This song already has audio")}

          true ->
            save_late_audio(socket, entry)
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("validate_queue", params, socket) when is_map(params) do
    {:noreply,
     socket
     |> maybe_assign_text(:song_title, params["song_title"])
     |> maybe_assign_text(:song_artist, params["song_artist"])}
  end

  def handle_event("add_to_queue", params, socket) when is_map(params) do
    title = params |> Map.get("song_title", "") |> String.trim()
    artist = params |> Map.get("song_artist", "") |> String.trim()

    cond do
      title == "" ->
        {:noreply, put_flash(socket, :error, "Song title is required")}

      artist == "" ->
        {:noreply, put_flash(socket, :error, "Artist is required")}

      true ->
        case consume_guest_media(socket, title, artist) do
          {:ok, socket, song} ->
            attrs = %{
              singer_name: socket.assigns.display_name,
              song_title: title,
              song_id: song.id
            }

            case Queue.enqueue(socket.assigns.room, attrs) do
              {:ok, _entry} ->
                _ = Catalog.maybe_start_isolation(song)

                socket =
                  socket
                  |> assign(:song_title, "")
                  |> assign(:song_artist, "")

                socket =
                  if Catalog.has_lyrics?(song) do
                    socket
                  else
                    put_flash(
                      socket,
                      :error,
                      "Couldn't find timed lyrics for #{title} — #{artist}. Search below, fix the title, or paste an .lrc."
                    )
                  end

                {:noreply, socket}

              {:error, changeset} ->
                {:noreply, put_flash(socket, :error, changeset_error(changeset))}
            end

          {:error, socket, reason} ->
            {:noreply, put_flash(socket, :error, error_text(reason))}
        end
    end
  end

  def handle_event("move_ready", %{"id" => id, "direction" => direction}, socket) do
    parsed =
      case direction do
        "up" -> :up
        "down" -> :down
        _ -> nil
      end

    if parsed do
      host_queue_action(socket, id, fn entry ->
        Rooms.move_ready_entry(socket.assigns.room, host_token(socket), entry, parsed)
      end)
    else
      {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  def handle_event("mark_ready", %{"id" => id}, socket) do
    host_queue_action(socket, id, fn entry ->
      Rooms.mark_entry_ready(socket.assigns.room, host_token(socket), entry)
    end)
  end

  def handle_event("mark_preparing", %{"id" => id}, socket) do
    host_queue_action(socket, id, fn entry ->
      Rooms.mark_entry_preparing(socket.assigns.room, host_token(socket), entry)
    end)
  end

  def handle_event("attach_instrumental", %{"entry_id" => id}, socket) do
    if socket.assigns.host? do
      with {:ok, entry} <- fetch_room_entry(socket, id),
           {:ok, socket, path} <- consume_one_audio(socket, :instrumental) do
        song_result =
          case entry.song do
            nil ->
              Catalog.create_song(socket.assigns.room, %{
                title: entry.song_title,
                artist: "Unknown",
                instrumental_path: path
              })

            song ->
              AllHandsSingAlong.Catalog.StemSeparator.cancel(song.id)

              Catalog.update_song(song, %{
                instrumental_path: path,
                stem_status: :ok,
                stem_error: nil
              })
          end

        with {:ok, song} <- song_result,
             {:ok, _entry} <- Queue.attach_song(entry, song) do
          {:noreply, socket}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
        end
      else
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  def handle_event("retry_stems", %{"id" => id}, socket) do
    host_queue_action(socket, id, fn entry ->
      Rooms.retry_stems(socket.assigns.room, host_token(socket), entry)
    end)
  end

  def handle_event("cancel_stems", %{"id" => id}, socket) do
    host_queue_action(socket, id, fn entry ->
      Rooms.cancel_stems(socket.assigns.room, host_token(socket), entry)
    end)
  end

  def handle_event("use_original", %{"id" => id}, socket) do
    host_queue_action(socket, id, fn entry ->
      Rooms.use_original_audio(socket.assigns.room, host_token(socket), entry)
    end)
  end

  @impl true
  def handle_info({:queue_updated, _room_id}, socket) do
    {:noreply, stream(socket, :queue, Queue.list_entries(socket.assigns.room.id), reset: true)}
  end

  def handle_info({:playback, playback}, socket) do
    {:noreply, sync_playback(socket, playback)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_presence(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <div
          class="glass-panel flex items-center gap-3 rounded-full px-4 py-2 text-sm text-amber-100/80"
          title="Use headphones so the backing track does not leak into Zoom."
        >
          <.icon name="hero-speaker-x-mark" class="size-5 shrink-0 text-amber-200" />
          <span class="sr-only">
            Use headphones so the backing track does not leak into Zoom.
          </span>
          <span class="hidden sm:inline">Headphones on. Keep the mix out of Zoom.</span>
        </div>

        <div
          :if={@host? and not @stem_local?}
          id="stem-worker-hint"
          class="glass-panel rounded-2xl px-4 py-3 text-sm text-amber-100/85"
        >
          <p class="font-medium text-amber-100">Vocal isolation runs on your Mac</p>
          <p class="mt-1 text-white/70">
            This command only processes <span class="font-medium text-white">this room</span>.
            Other hosts run their own copy. Guests do not need it.
          </p>
          <pre
            id="stem-worker-command"
            class="mt-2 overflow-x-auto rounded-lg bg-black/35 px-3 py-2 font-mono text-[13px] text-amber-50"
          >./script/worker --room {@room.code} --token {@host_token}</pre>
        </div>

        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">Room code</p>
            <h1 class="mt-1 font-mono text-4xl font-semibold tracking-[0.2em] text-white">
              {@room.code}
            </h1>
            <p class="mt-2 text-sm text-white/65">
              You are {@display_name}
              <span
                :if={@host?}
                class="ml-2 rounded-full border border-amber-200/30 bg-amber-200/15 px-2 py-0.5 text-[11px] uppercase tracking-wider text-amber-100"
              >
                Host
              </span>
            </p>
          </div>
          <div :if={@host?} class="flex flex-col items-end gap-2">
            <div class="flex items-center gap-2">
              <.icon_button
                id="start-singer"
                icon="hero-play"
                label="Start singer"
                variant="primary"
                phx-click="play"
              />
              <.icon_button id="pause-song" icon="hero-pause" label="Pause" phx-click="pause" />
              <.icon_button id="skip-song" icon="hero-forward" label="Skip" phx-click="skip" />
            </div>
            <p class="text-xs text-white/45">Backing track, no vocals</p>
          </div>
        </div>

        <div class="glass-panel space-y-5 rounded-3xl p-6 sm:p-8">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <p class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">Now playing</p>
            <p
              :if={playback_mode(@playback)}
              id="playback-mode"
              class="rounded-full border border-white/15 px-3 py-1 text-xs text-white/70"
            >
              {playback_mode_label(@playback)}
            </p>
          </div>
          <p id="now-playing-title" class="text-2xl font-medium tracking-tight text-white sm:text-3xl">
            {playback_heading(@playback)}
          </p>
          <p
            :if={@playback && @playback.singer_name}
            id="now-playing-singer"
            class="text-white/60"
          >
            {@playback.singer_name}
          </p>
          <div
            id="karaoke-player"
            phx-hook="KaraokePlayer"
            phx-update="ignore"
            data-playing={@playback && @playback.playing?}
            class="space-y-4"
          >
            <div class="lyric-roll">
              <p id="lyric-line-outgoing" class="lyric-roll-line is-outgoing" aria-hidden="true"></p>
              <p id="lyric-line" class="lyric-roll-line is-current"></p>
            </div>
            <audio id="karaoke-audio" controls class="w-full" preload="auto">
              <source :if={@playback && @playback.audio_url} src={@playback.audio_url} />
            </audio>
          </div>
          <div :if={@host?} class="flex flex-wrap items-center gap-2">
            <.icon_button
              id="lyrics-later"
              icon="hero-minus"
              label="Lyrics later"
              phx-click="nudge_lyrics"
              phx-value-delta="-100"
            />
            <.icon_button
              id="lyrics-earlier"
              icon="hero-plus"
              label="Lyrics earlier"
              phx-click="nudge_lyrics"
              phx-value-delta="100"
            />
            <p id="lyrics-offset" class="text-sm text-white/55">
              {offset_label(@playback && @playback.offset_ms)}
            </p>
          </div>
          <p
            :if={@host? and @lyric_preview}
            id="singer-muted-note"
            class="text-sm text-amber-100/70"
          >
            Singer track is muted in your headphones while you tune the next song.
          </p>
        </div>

        <div
          :if={@host? and @lyric_preview}
          id="lyric-preview-card"
          class="glass-panel space-y-4 rounded-3xl p-6"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p class="text-xs font-medium uppercase tracking-[0.28em] text-white/45">
                Tune next song
              </p>
              <p id="lyric-preview-title" class="mt-1 text-xl font-medium text-white">
                {Catalog.format_title(@lyric_preview.title, @lyric_preview.artist)}
              </p>
              <p class="text-white/60">{@lyric_preview.singer_name}</p>
            </div>
            <.icon_button
              id="close-lyric-preview"
              icon="hero-x-mark"
              label="Close preview"
              phx-click="close_lyric_preview"
            />
          </div>
          <p class="text-sm text-white/55">Original mix (vocals on). Guests still hear the singer.</p>
          <div id="lyric-preview" phx-hook="LyricPreview" phx-update="ignore" class="space-y-4">
            <div class="lyric-roll">
              <p
                id="lyric-preview-line-outgoing"
                class="lyric-roll-line is-outgoing"
                aria-hidden="true"
              >
              </p>
              <p id="lyric-preview-line" class="lyric-roll-line is-current"></p>
            </div>
            <audio id="lyric-preview-audio" controls class="w-full" preload="auto"></audio>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <.icon_button
              id="preview-lyrics-later"
              icon="hero-minus"
              label="Lyrics later"
              phx-click="nudge_preview"
              phx-value-delta="-100"
            />
            <.icon_button
              id="preview-lyrics-earlier"
              icon="hero-plus"
              label="Lyrics earlier"
              phx-click="nudge_preview"
              phx-value-delta="100"
            />
            <p id="lyric-preview-offset" class="text-sm text-white/55">
              {offset_label(@lyric_preview.offset_ms)}
            </p>
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-3">
          <section class="lg:col-span-2 space-y-4">
            <h2 class="text-lg font-medium text-white">Queue</h2>

            <.form
              for={%{}}
              id="add-queue-form"
              phx-change="validate_queue"
              phx-submit="add_to_queue"
              class="glass-panel space-y-4 rounded-3xl p-6"
            >
              <h3 class="font-medium text-white">Add a song</h3>
              <.input
                id="song-title"
                name="song_title"
                label="Song title"
                value={@song_title}
                required
              />
              <.input
                id="song-artist"
                name="song_artist"
                label="Artist"
                value={@song_artist}
                required
              />
              <div>
                <p class="label mb-1">Audio (optional)</p>
                <.live_file_input
                  upload={@uploads.audio}
                  class="file-input file-input-bordered w-full"
                />
                <div
                  :for={entry <- @uploads.audio.entries}
                  id="audio-upload-progress"
                  class="space-y-1 pt-2"
                >
                  <p class="text-sm text-base-content/70">Uploading {entry.progress}%</p>
                  <progress class="progress w-full" max="100" value={entry.progress}></progress>
                </div>
              </div>
              <div>
                <p class="label mb-1">Lyrics .lrc (optional)</p>
                <.live_file_input
                  upload={@uploads.lrc}
                  class="file-input file-input-bordered w-full"
                />
                <div
                  :for={entry <- @uploads.lrc.entries}
                  id="lrc-upload-progress"
                  class="space-y-1 pt-2"
                >
                  <p class="text-sm text-base-content/70">Uploading {entry.progress}%</p>
                  <progress class="progress w-full" max="100" value={entry.progress}></progress>
                </div>
              </div>
              <.button type="submit" variant="primary">Add me to the queue</.button>
            </.form>

            <ul id="queue" phx-update="stream" class="space-y-2">
              <li
                :for={{dom_id, entry} <- @streams.queue}
                id={dom_id}
                class="glass-panel rounded-2xl px-5 py-4"
              >
                <div class="flex flex-col gap-3">
                  <div class="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <p class="font-medium text-white">
                        {Catalog.format_title(entry.song_title, entry.song && entry.song.artist)}
                      </p>
                      <p class="text-sm text-white/55">{entry.singer_name}</p>
                      <p
                        :if={
                          entry.status in [:requested, :preparing] and
                            Catalog.missing_audio?(entry.song)
                        }
                        id={"no-audio-#{entry.id}"}
                        class="text-sm text-warning"
                      >
                        No song file yet. Upload one if you joined the queue first.
                      </p>
                      <p
                        :if={entry.status == :preparing and not Catalog.has_lyrics?(entry.song)}
                        id={"no-lyrics-#{entry.id}"}
                        class="text-sm text-warning"
                      >
                        Couldn't find timed lyrics. Search with a fuller title, or paste an .lrc.
                      </p>
                      <p
                        :if={Catalog.stem_in_progress?(entry.song)}
                        id={"stem-progress-#{entry.id}"}
                        class="space-y-1"
                      >
                        <span class="text-sm text-base-content/70">
                          {stem_progress_label(entry.song)}
                        </span>
                        <progress
                          class="progress w-full"
                          max="100"
                          value={entry.song.stem_progress || 0}
                        ></progress>
                      </p>
                      <p
                        :if={Catalog.stem_failed?(entry.song)}
                        id={"stem-failed-#{entry.id}"}
                        class="text-sm text-warning"
                      >
                        {entry.song.stem_error || "Couldn't remove vocals."}
                      </p>
                    </div>
                    <span class="rounded-full border border-white/15 px-2.5 py-0.5 text-[11px] uppercase tracking-wider text-white/60">
                      {status_label(entry.status)}
                    </span>
                  </div>
                  <div
                    :if={can_attach_missing_lyrics?(entry)}
                    class="space-y-3 border-t border-white/10 pt-3"
                  >
                    <.lyrics_editor entry={entry} lyric_search={@lyric_search} />
                  </div>
                  <div
                    :if={@host? and can_replace_lyrics?(entry)}
                    class="space-y-3 border-t border-white/10 pt-3"
                  >
                    <.icon_button
                      id={"change-lyrics-#{entry.id}"}
                      icon="hero-magnifying-glass"
                      label={
                        if @changing_lyrics_id == entry.id,
                          do: "Hide lyrics search",
                          else: "Change lyrics"
                      }
                      class={
                        icon_button_class(
                          if(@changing_lyrics_id == entry.id, do: "primary", else: nil)
                        )
                      }
                      phx-click="toggle_change_lyrics"
                      phx-value-id={entry.id}
                    />
                    <div :if={@changing_lyrics_id == entry.id} class="space-y-3">
                      <.lyrics_editor entry={entry} lyric_search={@lyric_search} />
                    </div>
                  </div>
                  <div
                    :if={
                      can_attach_audio?(@host?, @display_name, entry) and
                        Catalog.missing_audio?(entry.song) and
                        entry.status in [:requested, :preparing]
                    }
                    class="space-y-2 border-t border-white/10 pt-3"
                  >
                    <.icon_button
                      :if={@attaching_audio_id != entry.id}
                      id={"start-attach-audio-#{entry.id}"}
                      icon="hero-arrow-up-tray"
                      label="Upload audio"
                      phx-click="start_attach_audio"
                      phx-value-id={entry.id}
                    />
                    <.form
                      :if={@attaching_audio_id == entry.id}
                      for={%{}}
                      id={"attach-audio-#{entry.id}"}
                      phx-change="validate_late_audio"
                      phx-submit="attach_audio"
                      class="space-y-2"
                    >
                      <input type="hidden" name="entry_id" value={entry.id} />
                      <.live_file_input
                        upload={@uploads.late_audio}
                        class="file-input file-input-bordered w-full"
                      />
                      <div
                        :for={upload_entry <- @uploads.late_audio.entries}
                        id={"late-audio-progress-#{entry.id}"}
                        class="space-y-1"
                      >
                        <p class="text-sm text-base-content/70">Uploading {upload_entry.progress}%</p>
                        <progress
                          class="progress w-full"
                          max="100"
                          value={upload_entry.progress}
                        ></progress>
                      </div>
                      <.button type="submit">Save audio</.button>
                    </.form>
                  </div>
                  <div
                    :if={@host? and Catalog.needs_isolation?(entry.song)}
                    class="flex flex-wrap gap-2"
                  >
                    <.icon_button
                      :if={Catalog.stem_in_progress?(entry.song)}
                      id={"cancel-stems-#{entry.id}"}
                      icon="hero-stop"
                      label="Cancel"
                      phx-click="cancel_stems"
                      phx-value-id={entry.id}
                    />
                    <.icon_button
                      :if={not Catalog.stem_in_progress?(entry.song)}
                      id={"retry-stems-#{entry.id}"}
                      icon="hero-arrow-path"
                      label={stem_retry_label(entry.song)}
                      phx-click="retry_stems"
                      phx-value-id={entry.id}
                    />
                    <.icon_button
                      id={"use-original-#{entry.id}"}
                      icon="hero-speaker-wave"
                      label="Use original anyway"
                      phx-click="use_original"
                      phx-value-id={entry.id}
                    />
                  </div>
                  <.icon_button
                    :if={@host? and can_preview_lyrics?(entry)}
                    id={"tune-lyrics-#{entry.id}"}
                    icon="hero-adjustments-horizontal"
                    label="Tune lyrics"
                    phx-click="tune_lyrics"
                    phx-value-id={entry.id}
                  />
                  <div :if={@host? and entry.status == :ready} class="flex flex-wrap gap-2">
                    <.icon_button
                      id={"move-up-#{entry.id}"}
                      icon="hero-chevron-up"
                      label="Move up"
                      phx-click="move_ready"
                      phx-value-id={entry.id}
                      phx-value-direction="up"
                    />
                    <.icon_button
                      id={"move-down-#{entry.id}"}
                      icon="hero-chevron-down"
                      label="Move down"
                      phx-click="move_ready"
                      phx-value-id={entry.id}
                      phx-value-direction="down"
                    />
                  </div>
                </div>
              </li>
            </ul>

            <form
              :if={@host?}
              id="attach-instrumental-form"
              phx-change="validate_queue"
              phx-submit="attach_instrumental"
              class="glass-panel space-y-4 rounded-3xl p-6"
            >
              <h3 class="font-medium text-white">Attach instrumental</h3>
              <.input name="entry_id" label="Queue entry id" value="" />
              <.live_file_input
                upload={@uploads.instrumental}
                class="file-input file-input-bordered w-full"
              />
              <div
                :for={entry <- @uploads.instrumental.entries}
                id="instrumental-upload-progress"
                class="space-y-1"
              >
                <p class="text-sm text-base-content/70">Uploading {entry.progress}%</p>
                <progress class="progress w-full" max="100" value={entry.progress}></progress>
              </div>
              <.button type="submit">Attach</.button>
            </form>
          </section>

          <section class="glass-panel space-y-3 rounded-3xl p-5">
            <h2 class="text-lg font-medium text-white">In the room</h2>
            <ul class="space-y-2">
              <li :for={person <- @presence} class="flex items-center gap-2 text-white/80">
                <span>{person.name}</span>
                <span
                  :if={person.host?}
                  class="rounded-full border border-amber-200/30 px-2 py-0.5 text-[10px] uppercase tracking-wider text-amber-100"
                >
                  Host
                </span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :variant, :string, default: nil
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(disabled phx-click phx-value-id phx-value-delta phx-value-direction)

  defp icon_button(assigns) do
    assigns =
      assign(assigns, :computed_class, assigns.class || icon_button_class(assigns.variant))

    ~H"""
    <.button
      id={@id}
      type="button"
      class={@computed_class}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <.icon name={@icon} class="size-5" />
    </.button>
    """
  end

  defp icon_button_class("primary") do
    "inline-flex size-10 items-center justify-center rounded-full border border-amber-200/40 bg-amber-200 text-neutral-950 transition hover:bg-amber-100"
  end

  defp icon_button_class(_) do
    "inline-flex size-10 items-center justify-center rounded-full border border-white/15 bg-white/10 text-white transition hover:border-amber-200/40 hover:bg-white/15 hover:text-amber-100"
  end

  attr :entry, :map, required: true
  attr :lyric_search, :map, default: nil

  defp lyrics_editor(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"lyrics-search-#{@entry.id}"}
      phx-submit="search_lyrics"
      class="space-y-2"
    >
      <input type="hidden" name="entry_id" value={@entry.id} />
      <.input
        id={"lyrics-title-#{@entry.id}"}
        name="title"
        label="Title"
        value={@entry.song_title}
        required
      />
      <.input
        id={"lyrics-artist-#{@entry.id}"}
        name="artist"
        label="Artist"
        value={(@entry.song && @entry.song.artist) || ""}
        required
      />
      <.button type="submit">Search lyrics</.button>
    </.form>
    <div
      :if={@lyric_search && @lyric_search.entry_id == @entry.id}
      id={"lyrics-results-#{@entry.id}"}
      class="space-y-2"
    >
      <p :if={@lyric_search.error} class="text-sm text-warning">
        {@lyric_search.error}
      </p>
      <button
        :for={hit <- @lyric_search.results}
        id={"pick-lyrics-#{@entry.id}-#{hit.id}"}
        type="button"
        class="btn btn-sm btn-soft w-full justify-start text-left"
        phx-click="pick_lyrics"
        phx-value-id={@entry.id}
        phx-value-lrclib-id={hit.id}
      >
        {Catalog.format_title(hit.track_name, hit.artist_name)}
        <span :if={hit.album_name} class="text-base-content/60 font-normal">
          · {hit.album_name}
        </span>
      </button>
    </div>
    <.form
      for={%{}}
      id={"lyrics-paste-#{@entry.id}"}
      phx-submit="paste_lyrics"
      class="space-y-2"
    >
      <input type="hidden" name="entry_id" value={@entry.id} />
      <.input
        id={"lyrics-paste-text-#{@entry.id}"}
        name="lrc_text"
        type="textarea"
        label="Paste .lrc"
        value=""
      />
      <.button type="submit">Save pasted lyrics</.button>
    </.form>
    """
  end

  defp consume_guest_media(socket, title, artist) do
    socket =
      socket
      |> cancel_entries(:instrumental)
      |> cancel_entries(:late_audio)

    audio_paths =
      consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
        case Uploads.store_audio!(path, entry.client_name) do
          {:ok, url} -> {:ok, url}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    lrc_texts =
      consume_uploaded_entries(socket, :lrc, fn %{path: path}, _entry ->
        {:ok, Uploads.read_text!(path)}
      end)

    audio_path = List.first(audio_paths)
    lrc_text = List.first(lrc_texts)

    attrs = %{
      title: title,
      artist: artist,
      original_path: audio_path,
      lrc_text: lrc_text
    }

    case Catalog.create_prepared_song(socket.assigns.room, attrs) do
      {:ok, song} -> {:ok, socket, song}
      {:error, changeset} -> {:error, socket, changeset}
    end
  end

  defp consume_one_audio(socket, name) do
    socket =
      socket
      |> cancel_entries(:audio)
      |> cancel_entries(:lrc)

    paths =
      consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
        case Uploads.store_audio!(path, entry.client_name) do
          {:ok, url} -> {:ok, url}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    case paths do
      [path | _] when is_binary(path) -> {:ok, socket, path}
      _ -> {:error, :no_file}
    end
  end

  defp save_late_audio(socket, entry) do
    case consume_late_audio(socket) do
      {:ok, socket, path} ->
        song_result =
          case entry.song do
            nil ->
              Catalog.create_prepared_song(socket.assigns.room, %{
                title: entry.song_title,
                artist: "Unknown",
                original_path: path
              })

            song ->
              Catalog.update_song(song, %{
                original_path: path,
                stem_status: :idle,
                stem_error: nil
              })
          end

        with {:ok, song} <- song_result,
             {:ok, _entry} <- Queue.attach_song(entry, song) do
          _ = Catalog.maybe_start_isolation(song)

          {:noreply,
           socket
           |> assign(:attaching_audio_id, nil)
           |> stream(:queue, Queue.list_entries(socket.assigns.room.id), reset: true)
           |> put_flash(:info, "Audio added")}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  defp consume_late_audio(socket) do
    paths =
      consume_uploaded_entries(socket, :late_audio, fn %{path: path}, entry ->
        case Uploads.store_audio!(path, entry.client_name) do
          {:ok, url} -> {:ok, url}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    case paths do
      [path | _] when is_binary(path) -> {:ok, socket, path}
      _ -> {:error, :no_file}
    end
  end

  defp can_attach_audio?(socket, entry) do
    can_attach_audio?(socket.assigns.host?, socket.assigns.display_name, entry)
  end

  defp can_attach_audio?(host?, display_name, entry) do
    host? or entry.singer_name == display_name
  end

  defp host_queue_action(socket, id, fun) do
    if socket.assigns.host? do
      with {:ok, entry} <- fetch_room_entry(socket, id),
           {:ok, _} <- fun.(entry) do
        {:noreply, socket}
      else
        {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Queue entry not found")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  defp fetch_room_entry(socket, id) do
    with {entry_id, ""} <- Integer.parse(to_string(id)),
         {:ok, entry} <- Queue.get_entry(entry_id),
         true <- entry.room_id == socket.assigns.room.id do
      {:ok, entry}
    else
      _ -> {:error, :not_found}
    end
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

  defp maybe_push_playback(socket) do
    push_player_sync(socket)
  end

  defp sync_playback(socket, playback) do
    socket
    |> assign(:playback, playback)
    |> push_player_sync()
  end

  defp push_player_sync(socket) do
    if connected?(socket) do
      push_event(socket, "player-sync", player_payload(socket, socket.assigns.playback))
    else
      socket
    end
  end

  defp player_payload(socket, playback) do
    previewing? = socket.assigns.host? and not is_nil(socket.assigns.lyric_preview)

    base = %{
      muted: previewing?,
      show_controls: not previewing?
    }

    case playback do
      nil ->
        Map.merge(base, %{
          playing: false,
          position_ms: 0,
          server_time_ms: System.system_time(:millisecond),
          audio_url: nil,
          lyrics: [],
          offset_ms: 0
        })

      playback ->
        Map.merge(base, %{
          playing: playback.playing?,
          position_ms: playback.position_ms,
          server_time_ms: playback.server_time_ms,
          audio_url: playback.audio_url,
          lyrics: playback.lyrics,
          offset_ms: Map.get(playback, :offset_ms, 0)
        })
    end
  end

  defp open_lyric_preview(socket, preview) do
    socket
    |> assign(:lyric_preview, preview)
    |> push_preview_sync(preview)
    |> push_player_sync()
  end

  defp close_lyric_preview(socket) do
    socket
    |> assign(:lyric_preview, nil)
    |> push_player_sync()
  end

  defp push_preview_sync(socket, preview) do
    if connected?(socket) do
      push_event(socket, "preview-sync", %{
        playing: true,
        audio_url: preview.audio_url,
        lyrics: preview.lyrics,
        offset_ms: preview.offset_ms
      })
    else
      socket
    end
  end

  defp nudge_lyric_preview(socket, delta_ms) do
    preview = socket.assigns.lyric_preview

    cond do
      is_nil(preview) ->
        put_flash(socket, :error, "Not found")

      true ->
        with {:ok, song} <- Catalog.get_song(preview.song_id),
             {:ok, song} <-
               Rooms.nudge_song_offset(
                 socket.assigns.room,
                 host_token(socket),
                 song,
                 delta_ms
               ) do
          preview = %{preview | offset_ms: Catalog.lyric_offset_ms(song)}

          socket
          |> assign(:lyric_preview, preview)
          |> push_preview_sync(preview)
        else
          {:error, reason} -> put_flash(socket, :error, error_text(reason))
        end
    end
  end

  defp refresh_lyric_preview(socket, %Queue.Entry{} = entry) do
    case socket.assigns.lyric_preview do
      %{entry_id: id} when id == entry.id ->
        case Rooms.lyric_preview(socket.assigns.room, host_token(socket), entry) do
          {:ok, preview} -> open_lyric_preview(socket, preview)
          {:error, _} -> close_lyric_preview(socket)
        end

      _ ->
        socket
    end
  end

  defp finish_lyric_edit(socket, entry) do
    socket
    |> assign(:lyric_search, nil)
    |> assign(:changing_lyrics_id, nil)
    |> refresh_lyric_preview(entry)
    |> restream_queue()
  end

  defp restream_queue(socket) do
    stream(socket, :queue, Queue.list_entries(socket.assigns.room.id), reset: true)
  end

  defp clear_lyric_search(socket, entry_id) do
    search = socket.assigns.lyric_search

    if search && search.entry_id == entry_id do
      assign(socket, :lyric_search, nil)
    else
      socket
    end
  end

  defp authorize_lyric_search(socket, entry) do
    cond do
      can_attach_missing_lyrics?(entry) -> :ok
      socket.assigns.host? and can_replace_lyrics?(entry) -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp authorize_lyric_edit(socket, entry) do
    cond do
      can_attach_missing_lyrics?(entry) -> :ok
      socket.assigns.host? and can_replace_lyrics?(entry) -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp search_lyric_hits(socket, entry, title, artist) do
    if can_replace_lyrics?(entry) do
      Catalog.Lyrics.search(artist, title)
    else
      with {:ok, song} <- ensure_song(socket, entry, title, artist),
           {:ok, _entry} <- Queue.attach_song(entry, song) do
        Catalog.Lyrics.search(artist, title)
      end
    end
  end

  defp song_for_lyric_edit(socket, entry) do
    if can_replace_lyrics?(entry) do
      case entry.song do
        %{} = song -> {:ok, song}
        _ -> {:error, :not_found}
      end
    else
      ensure_song(socket, entry, entry.song_title, (entry.song && entry.song.artist) || "")
    end
  end

  defp can_preview_lyrics?(entry) do
    entry.status in [:requested, :preparing, :ready] and
      Catalog.has_original?(entry.song) and
      Catalog.has_lyrics?(entry.song)
  end

  defp can_replace_lyrics?(entry) do
    entry.status in [:requested, :preparing, :ready] and Catalog.has_lyrics?(entry.song)
  end

  defp can_attach_missing_lyrics?(entry) do
    entry.status in [:requested, :preparing] and not Catalog.has_lyrics?(entry.song)
  end

  defp maybe_assign_text(socket, _key, nil), do: socket
  defp maybe_assign_text(socket, key, value) when is_binary(value), do: assign(socket, key, value)

  defp playback_heading(nil), do: "Nothing yet — host can start the singer or demo track"

  defp playback_heading(%{title: title} = playback) when is_binary(title) and title != "" do
    Catalog.format_title(title, Map.get(playback, :artist))
  end

  defp playback_heading(_), do: "Nothing yet — host can start the singer or demo track"

  defp playback_mode(%{mode: :singing}), do: :singing
  defp playback_mode(_), do: nil

  defp playback_mode_label(%{mode: :singing}), do: "Singer (backing track)"

  defp stem_progress_label(%{stem_status: :queued}),
    do: "Waiting for your Mac to remove vocals…"

  defp stem_progress_label(%{stem_status: :running, stem_progress: pct}) when is_integer(pct) do
    "Removing vocals #{pct}%"
  end

  defp stem_progress_label(_), do: "Removing vocals…"

  defp offset_label(nil), do: "Lyrics on time"
  defp offset_label(0), do: "Lyrics on time"

  defp offset_label(ms) when is_integer(ms) and ms > 0 do
    "Lyrics #{format_offset(ms)} earlier"
  end

  defp offset_label(ms) when is_integer(ms) do
    "Lyrics #{format_offset(-ms)} later"
  end

  defp format_offset(ms) when rem(ms, 1000) == 0, do: "#{div(ms, 1000)}s"
  defp format_offset(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp ensure_song(socket, %{song: nil} = _entry, title, artist) when artist != "" do
    Catalog.create_song(socket.assigns.room, %{title: title, artist: artist})
  end

  defp ensure_song(_socket, %{song: nil}, _title, _artist), do: {:error, :invalid}

  defp ensure_song(_socket, %{song: song}, title, artist) do
    attrs = %{title: title}
    attrs = if artist != "", do: Map.put(attrs, :artist, artist), else: attrs
    Catalog.update_song(song, attrs)
  end

  defp host_token_from_session(session, code) do
    session
    |> Map.get("host_tokens", %{})
    |> Map.get(code)
  end

  defp put_host_token(socket, token) do
    %{socket | private: Map.put(socket.private, :host_token, token)}
  end

  defp host_token(socket), do: Map.get(socket.private, :host_token)

  defp cancel_entries(socket, name) do
    entries = socket.assigns.uploads[name].entries
    Enum.reduce(entries, socket, fn entry, acc -> cancel_upload(acc, name, entry.ref) end)
  end

  defp status_label(:requested), do: "Requested"
  defp status_label(:preparing), do: "Preparing"
  defp status_label(:ready), do: "Ready"
  defp status_label(:now_singing), do: "Now singing"
  defp status_label(:done), do: "Done"
  defp status_label(other), do: to_string(other)

  defp stem_retry_label(song) do
    if Catalog.stem_failed?(song), do: "Retry", else: "Remove vocals"
  end

  defp error_text(:unauthorized), do: "Host only"
  defp error_text(:missing_audio), do: "Attach audio before marking ready"
  defp error_text(:missing_lyrics), do: "Lyrics are still missing"
  defp error_text(:not_installed), do: "Vocal isolation isn’t installed on this machine"
  defp error_text(:stem_failed), do: "Couldn't remove vocals"
  defp error_text(:not_ready), do: "Only ready songs can be reordered"
  defp error_text(:not_found), do: "Not found"
  defp error_text(:invalid_lrc), do: "That didn't look like timed .lrc lyrics"
  defp error_text(:invalid), do: "Title and artist are required"
  defp error_text(:no_synced_lyrics), do: "That match has no timed lyrics"
  defp error_text(:ambiguous), do: "Several matches — pick one below"
  defp error_text(:none_ready), do: "No ready songs"
  defp error_text(:invalid_ext), do: "Unsupported audio type"
  defp error_text(:no_file), do: "Choose a file"
  defp error_text({:http, _status}), do: "Couldn't fetch those lyrics"
  defp error_text(%Ecto.Changeset{} = changeset), do: changeset_error(changeset)
  defp error_text(_), do: "Something went wrong"

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
