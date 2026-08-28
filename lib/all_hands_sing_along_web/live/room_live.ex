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
        |> assign(:attaching_audio_id, nil)
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
           {:ok, playback} <- Rooms.tune_lyrics(socket.assigns.room, host_token(socket), entry) do
        {:noreply, sync_playback(socket, playback)}
      else
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
             {:ok, song} <- ensure_song(socket, entry, title, artist),
             {:ok, _entry} <- Queue.attach_song(entry, song),
             {:ok, hits} <- Catalog.Lyrics.search(artist, title) do
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

          {:noreply, assign(socket, :lyric_search, search)}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
        end
    end
  end

  def handle_event("pick_lyrics", %{"id" => id, "lrclib-id" => lrclib_id}, socket) do
    with {:ok, entry} <- fetch_room_entry(socket, id),
         %{} = song <- entry.song,
         {:ok, lrc} <- Catalog.Lyrics.fetch_by_id(lrclib_id),
         {:ok, song} <- Catalog.apply_lrc(song, lrc),
         {:ok, _entry} <- Queue.attach_song(entry, song) do
      {:noreply,
       socket
       |> assign(:lyric_search, nil)
       |> put_flash(:info, "Lyrics attached")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Add the song to the queue first")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
    end
  end

  def handle_event("paste_lyrics", %{"entry_id" => id, "lrc_text" => lrc_text}, socket) do
    with {:ok, entry} <- fetch_room_entry(socket, id),
         {:ok, song} <-
           ensure_song(socket, entry, entry.song_title, (entry.song && entry.song.artist) || ""),
         {:ok, song} <- Catalog.apply_lrc(song, lrc_text),
         {:ok, _entry} <- Queue.attach_song(entry, song) do
      {:noreply,
       socket
       |> assign(:lyric_search, nil)
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
      <div class="space-y-6">
        <div class="alert alert-warning text-sm">
          Use headphones so the backing track does not leak into Zoom.
        </div>

        <div class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p class="text-sm text-base-content/60">Room code</p>
            <h1 class="text-3xl font-semibold tracking-wide">{@room.code}</h1>
            <p class="text-sm text-base-content/70">
              You are {@display_name}
              <span :if={@host?} class="badge badge-primary badge-sm ml-2">Host</span>
            </p>
          </div>
          <div :if={@host?} class="flex flex-col items-end gap-1">
            <div class="join">
              <.button id="start-singer" type="button" variant="primary" phx-click="play">
                Start singer
              </.button>
              <.button type="button" phx-click="pause">Pause</.button>
              <.button
                :if={playback_mode(@playback) != :tuning}
                id="skip-song"
                type="button"
                phx-click="skip"
              >
                Skip
              </.button>
            </div>
            <p class="text-xs text-base-content/60">
              Start singer plays the backing track (no vocals).
            </p>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body space-y-3">
            <p class="text-sm uppercase tracking-wide text-base-content/60">Now playing</p>
            <p
              :if={playback_mode(@playback)}
              id="playback-mode"
              class="badge badge-soft"
            >
              {playback_mode_label(@playback)}
            </p>
            <p id="now-playing-title" class="text-xl font-medium">
              {playback_heading(@playback)}
            </p>
            <p
              :if={@playback && @playback.singer_name}
              id="now-playing-singer"
              class="text-base-content/70"
            >
              {@playback.singer_name}
            </p>
            <div
              id="karaoke-player"
              phx-hook="KaraokePlayer"
              phx-update="ignore"
              data-playing={@playback && @playback.playing?}
            >
              <p id="lyric-line" class="text-2xl font-semibold min-h-10"></p>
              <audio id="karaoke-audio" controls class="w-full" preload="auto">
                <source :if={@playback && @playback.audio_url} src={@playback.audio_url} />
              </audio>
            </div>
            <div :if={@host?} class="flex flex-wrap items-center gap-2">
              <.button
                id="lyrics-later"
                type="button"
                phx-click="nudge_lyrics"
                phx-value-delta="-100"
              >
                Lyrics later
              </.button>
              <.button
                id="lyrics-earlier"
                type="button"
                phx-click="nudge_lyrics"
                phx-value-delta="100"
              >
                Lyrics earlier
              </.button>
              <p id="lyrics-offset" class="text-sm text-base-content/70">
                {offset_label(@playback && @playback.offset_ms)}
              </p>
            </div>
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-3">
          <section class="lg:col-span-2 space-y-4">
            <h2 class="text-lg font-semibold">Queue</h2>

            <.form
              for={%{}}
              id="add-queue-form"
              phx-change="validate_queue"
              phx-submit="add_to_queue"
              class="card bg-base-200"
            >
              <div class="card-body space-y-3">
                <h3 class="font-medium">Add a song</h3>
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
              </div>
            </.form>

            <ul id="queue" phx-update="stream" class="space-y-2">
              <li
                :for={{dom_id, entry} <- @streams.queue}
                id={dom_id}
                class="card bg-base-100 border border-base-300"
              >
                <div class="card-body py-4 gap-2">
                  <div class="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <p class="font-medium">
                        {Catalog.format_title(entry.song_title, entry.song && entry.song.artist)}
                      </p>
                      <p class="text-sm text-base-content/70">{entry.singer_name}</p>
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
                    <span class="badge badge-soft">{status_label(entry.status)}</span>
                  </div>
                  <div
                    :if={
                      entry.status in [:requested, :preparing] and not Catalog.has_lyrics?(entry.song)
                    }
                    class="space-y-3 border-t border-base-300 pt-3"
                  >
                    <.form
                      for={%{}}
                      id={"lyrics-search-#{entry.id}"}
                      phx-submit="search_lyrics"
                      class="space-y-2"
                    >
                      <input type="hidden" name="entry_id" value={entry.id} />
                      <.input
                        id={"lyrics-title-#{entry.id}"}
                        name="title"
                        label="Title"
                        value={entry.song_title}
                        required
                      />
                      <.input
                        id={"lyrics-artist-#{entry.id}"}
                        name="artist"
                        label="Artist"
                        value={(entry.song && entry.song.artist) || ""}
                        required
                      />
                      <.button type="submit">Search lyrics</.button>
                    </.form>
                    <div
                      :if={@lyric_search && @lyric_search.entry_id == entry.id}
                      id={"lyrics-results-#{entry.id}"}
                      class="space-y-2"
                    >
                      <p :if={@lyric_search.error} class="text-sm text-warning">
                        {@lyric_search.error}
                      </p>
                      <button
                        :for={hit <- @lyric_search.results}
                        id={"pick-lyrics-#{entry.id}-#{hit.id}"}
                        type="button"
                        class="btn btn-sm btn-soft w-full justify-start text-left"
                        phx-click="pick_lyrics"
                        phx-value-id={entry.id}
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
                      id={"lyrics-paste-#{entry.id}"}
                      phx-submit="paste_lyrics"
                      class="space-y-2"
                    >
                      <input type="hidden" name="entry_id" value={entry.id} />
                      <.input
                        id={"lyrics-paste-text-#{entry.id}"}
                        name="lrc_text"
                        type="textarea"
                        label="Paste .lrc"
                        value=""
                      />
                      <.button type="submit">Save pasted lyrics</.button>
                    </.form>
                  </div>
                  <div
                    :if={
                      can_attach_audio?(@host?, @display_name, entry) and
                        Catalog.missing_audio?(entry.song) and
                        entry.status in [:requested, :preparing]
                    }
                    class="space-y-2 border-t border-base-300 pt-3"
                  >
                    <.button
                      :if={@attaching_audio_id != entry.id}
                      id={"start-attach-audio-#{entry.id}"}
                      type="button"
                      phx-click="start_attach_audio"
                      phx-value-id={entry.id}
                    >
                      Upload audio
                    </.button>
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
                    <.button
                      :if={Catalog.stem_in_progress?(entry.song)}
                      id={"cancel-stems-#{entry.id}"}
                      type="button"
                      phx-click="cancel_stems"
                      phx-value-id={entry.id}
                    >
                      Cancel
                    </.button>
                    <.button
                      :if={not Catalog.stem_in_progress?(entry.song)}
                      id={"retry-stems-#{entry.id}"}
                      type="button"
                      phx-click="retry_stems"
                      phx-value-id={entry.id}
                    >
                      {stem_retry_label(entry.song)}
                    </.button>
                    <.button
                      id={"use-original-#{entry.id}"}
                      type="button"
                      phx-click="use_original"
                      phx-value-id={entry.id}
                    >
                      Use original anyway
                    </.button>
                  </div>
                  <.button
                    :if={
                      @host? and Catalog.has_original?(entry.song) and
                        Catalog.has_lyrics?(entry.song)
                    }
                    id={"tune-lyrics-#{entry.id}"}
                    type="button"
                    phx-click="tune_lyrics"
                    phx-value-id={entry.id}
                  >
                    Tune lyrics
                  </.button>
                  <div :if={@host? and entry.status == :ready} class="flex flex-wrap gap-2">
                    <.button
                      id={"move-up-#{entry.id}"}
                      type="button"
                      phx-click="move_ready"
                      phx-value-id={entry.id}
                      phx-value-direction="up"
                    >
                      Move up
                    </.button>
                    <.button
                      id={"move-down-#{entry.id}"}
                      type="button"
                      phx-click="move_ready"
                      phx-value-id={entry.id}
                      phx-value-direction="down"
                    >
                      Move down
                    </.button>
                  </div>
                </div>
              </li>
            </ul>

            <form
              :if={@host?}
              id="attach-instrumental-form"
              phx-change="validate_queue"
              phx-submit="attach_instrumental"
              class="card bg-base-200"
            >
              <div class="card-body space-y-3">
                <h3 class="font-medium">Attach instrumental</h3>
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
              </div>
            </form>
          </section>

          <section class="space-y-3">
            <h2 class="text-lg font-semibold">In the room</h2>
            <ul class="space-y-1">
              <li :for={person <- @presence} class="flex items-center gap-2">
                <span>{person.name}</span>
                <span :if={person.host?} class="badge badge-xs">Host</span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </Layouts.app>
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
    case socket.assigns.playback do
      nil -> socket
      playback -> sync_playback(socket, playback)
    end
  end

  defp sync_playback(socket, playback) do
    socket
    |> assign(:playback, playback)
    |> push_event("player-sync", player_payload(playback))
  end

  defp player_payload(nil), do: %{}

  defp player_payload(playback) do
    %{
      playing: playback.playing?,
      position_ms: playback.position_ms,
      server_time_ms: playback.server_time_ms,
      audio_url: playback.audio_url,
      lyrics: playback.lyrics,
      offset_ms: Map.get(playback, :offset_ms, 0)
    }
  end

  defp maybe_assign_text(socket, _key, nil), do: socket
  defp maybe_assign_text(socket, key, value) when is_binary(value), do: assign(socket, key, value)

  defp playback_heading(nil), do: "Nothing yet — host can start the singer or demo track"

  defp playback_heading(%{title: title} = playback) when is_binary(title) and title != "" do
    Catalog.format_title(title, Map.get(playback, :artist))
  end

  defp playback_heading(_), do: "Nothing yet — host can start the singer or demo track"

  defp playback_mode(%{mode: mode}) when mode in [:tuning, :singing], do: mode
  defp playback_mode(_), do: nil

  defp playback_mode_label(%{mode: :tuning}), do: "Tuning (vocals on)"
  defp playback_mode_label(%{mode: :singing}), do: "Singer (backing track)"

  defp stem_progress_label(%{stem_status: :queued}), do: "Queued"

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

  defp error_text(:tuning), do: "Skip is for the singer, not lyric tuning"
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
