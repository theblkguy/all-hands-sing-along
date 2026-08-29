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

  import AllHandsSingAlongWeb.Onboarding, only: [gate: 1]

  import AllHandsSingAlongWeb.RoomLive.HTML,
    only: [
      room: 1,
      can_attach_audio?: 3,
      can_replace_lyrics?: 1,
      can_attach_missing_lyrics?: 1
    ]

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
        |> assign(:show_onboarding?, false)
        |> allow_upload(:audio, accept: :any, max_entries: 1, max_file_size: 32_000_000)
        |> allow_upload(:lrc, accept: :any, max_entries: 1, max_file_size: 200_000)
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
          |> push_player_sync()
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

  def handle_event("play", _params, socket) do
    with_host(socket, fn socket ->
      socket = close_lyric_preview(socket)

      case Rooms.play(socket.assigns.room, host_token(socket)) do
        {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    end)
  end

  def handle_event("pause", _params, socket) do
    with_host(socket, fn socket ->
      case Rooms.pause(socket.assigns.room, host_token(socket)) do
        {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    end)
  end

  def handle_event("skip", _params, socket) do
    with_host(socket, fn socket ->
      socket = close_lyric_preview(socket)

      case Rooms.skip(socket.assigns.room, host_token(socket)) do
        {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    end)
  end

  def handle_event("tune_lyrics", %{"id" => id}, socket) do
    with_host(socket, fn socket ->
      with {:ok, entry} <- fetch_room_entry(socket, id),
           {:ok, preview} <-
             Rooms.lyric_preview(socket.assigns.room, host_token(socket), entry) do
        {:noreply, open_lyric_preview(socket, preview)}
      else
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    end)
  end

  def handle_event("close_lyric_preview", _params, socket) do
    with_host(socket, fn socket ->
      {:noreply, close_lyric_preview(socket)}
    end)
  end

  def handle_event("nudge_preview", %{"delta" => delta}, socket) do
    with {:ok, ms} <- parse_delta(delta) do
      with_host(socket, fn socket ->
        {:noreply, nudge_lyric_preview(socket, ms)}
      end)
    else
      :error -> {:noreply, put_flash(socket, :error, "Something went wrong")}
    end
  end

  def handle_event("toggle_change_lyrics", %{"id" => id}, socket) do
    with_host(socket, fn socket ->
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
    end)
  end

  def handle_event("nudge_lyrics", %{"delta" => delta}, socket) do
    with {:ok, ms} <- parse_delta(delta) do
      with_host(socket, fn socket ->
        case Rooms.nudge_lyrics(socket.assigns.room, host_token(socket), ms) do
          {:ok, playback} -> {:noreply, sync_playback(socket, playback)}
          {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
        end
      end)
    else
      :error -> {:noreply, put_flash(socket, :error, "Something went wrong")}
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
             :ok <- authorize_lyric_edit(socket, entry),
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

  defp consume_guest_media(socket, title, artist) do
    socket = cancel_entries(socket, :late_audio)

    audio_paths = consume_uploaded_audio(socket, :audio)

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
    case consume_uploaded_audio(socket, :late_audio) do
      [path | _] when is_binary(path) -> {:ok, socket, path}
      _ -> {:error, :no_file}
    end
  end

  defp consume_uploaded_audio(socket, name) do
    consume_uploaded_entries(socket, name, fn %{path: path}, entry ->
      case Uploads.store_audio!(path, entry.client_name) do
        {:ok, url} -> {:ok, url}
        {:error, reason} -> {:postpone, reason}
      end
    end)
  end

  defp can_attach_audio?(socket, entry) do
    can_attach_audio?(socket.assigns.host?, socket.assigns.display_name, entry)
  end

  defp with_host(socket, fun) do
    if socket.assigns.host? do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, "Host only")}
    end
  end

  defp parse_delta(delta) do
    case Integer.parse(to_string(delta)) do
      {ms, ""} -> {:ok, ms}
      _ -> :error
    end
  end

  defp host_queue_action(socket, id, fun) do
    with_host(socket, fn socket ->
      with {:ok, entry} <- fetch_room_entry(socket, id),
           {:ok, _} <- fun.(entry) do
        {:noreply, socket}
      else
        {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Queue entry not found")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, error_text(reason))}
      end
    end)
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

  defp maybe_assign_text(socket, _key, nil), do: socket
  defp maybe_assign_text(socket, key, value) when is_binary(value), do: assign(socket, key, value)

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

  defp error_text(:unauthorized), do: "Host only"
  defp error_text(:missing_audio), do: "Attach audio before marking ready"
  defp error_text(:missing_lyrics), do: "Lyrics are still missing"
  defp error_text(:not_installed), do: "Vocal isolation isn’t installed on this machine"
  defp error_text(:missing_ffmpeg), do: "Vocal isolation needs ffmpeg to mix a quiet guide vocal"
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
