# lib/all_hands_sing_along_web/live/room_live/lyrics.ex
defmodule AllHandsSingAlongWeb.RoomLive.Lyrics do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [connected?: 1, push_event: 3, put_flash: 3, stream: 4]

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.Song
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlongWeb.RoomLive.Auth
  alias AllHandsSingAlongWeb.RoomLive.HTML
  alias AllHandsSingAlongWeb.RoomLive.Playback

  def tune(socket, id) do
    Auth.with_host(socket, fn socket ->
      with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
           {:ok, preview} <-
             Rooms.lyric_preview(socket.assigns.room, Auth.host_token(socket), entry) do
        {:noreply, open_preview(socket, preview)}
      else
        {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    end)
  end

  def close_preview_event(socket) do
    Auth.with_host(socket, fn socket ->
      {:noreply, close_preview(socket)}
    end)
  end

  def nudge_preview(socket, delta) do
    with {:ok, ms} <- parse_delta(delta) do
      Auth.with_host(socket, fn socket ->
        {:noreply, do_nudge_preview(socket, ms)}
      end)
    else
      :error -> {:noreply, put_flash(socket, :error, Auth.error_text(:invalid_delta))}
    end
  end

  def toggle_change(socket, id) do
    Auth.with_host(socket, fn socket ->
      with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
           true <- HTML.can_replace_lyrics?(entry) do
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
        false -> {:noreply, put_flash(socket, :error, "Only the host can do that")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    end)
  end

  def nudge_playback(socket, delta) do
    with {:ok, ms} <- parse_delta(delta) do
      Auth.with_host(socket, fn socket ->
        case Rooms.nudge_lyrics(socket.assigns.room, Auth.host_token(socket), ms) do
          {:ok, playback} -> {:noreply, Playback.sync(socket, playback)}
          {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
        end
      end)
    else
      :error -> {:noreply, put_flash(socket, :error, Auth.error_text(:invalid_delta))}
    end
  end

  def search(socket, %{"entry_id" => id} = params) do
    changeset = Song.changeset(%Song{}, %{title: params["title"], artist: params["artist"]})

    case Ecto.Changeset.apply_action(changeset, :search) do
      {:ok, %{title: title, artist: artist}} ->
        with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
             :ok <- authorize_lyric_edit(socket, entry),
             {:ok, hits} <- search_lyric_hits(socket, entry, title, artist) do
          search =
            if hits == [] do
              %{
                entry_id: entry.id,
                results: [],
                error: "No matches. Try another spelling, or paste an .lrc."
              }
            else
              %{entry_id: entry.id, results: hits, error: nil}
            end

          {:noreply, socket |> assign(:lyric_search, search) |> restream_queue()}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
        end

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, Auth.error_text(changeset))}
    end
  end

  def pick(socket, id, lrclib_id) do
    with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
         :ok <- authorize_lyric_edit(socket, entry),
         %{} = song <- entry.song,
         {:ok, lrc} <- Catalog.Lyrics.fetch_by_id(lrclib_id),
         {:ok, song} <- Catalog.apply_lrc(song, lrc),
         {:ok, entry} <- Queue.attach_song(entry, song) do
      {:noreply,
       socket
       |> finish_lyric_edit(entry)
       |> put_flash(:info, "Lyrics saved")}
    else
      nil -> {:noreply, put_flash(socket, :error, "Add the song to the queue first")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def paste(socket, id, lrc_text) do
    with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
         :ok <- authorize_lyric_edit(socket, entry),
         {:ok, song} <- song_for_lyric_edit(socket, entry),
         {:ok, song} <- Catalog.apply_lrc(song, lrc_text),
         {:ok, entry} <- Queue.attach_song(entry, song) do
      {:noreply,
       socket
       |> finish_lyric_edit(entry)
       |> put_flash(:info, "Lyrics saved")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def close_preview(socket) do
    socket
    |> assign(:lyric_preview, nil)
    |> Playback.push_sync()
  end

  defp open_preview(socket, preview) do
    socket
    |> assign(:lyric_preview, preview)
    |> push_preview_sync(preview)
    |> Playback.push_sync()
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

  defp do_nudge_preview(socket, delta_ms) do
    preview = socket.assigns.lyric_preview

    cond do
      is_nil(preview) ->
        put_flash(socket, :error, "Not found")

      true ->
        with {:ok, song} <- Catalog.get_song(preview.song_id),
             {:ok, song} <-
               Rooms.nudge_song_offset(
                 socket.assigns.room,
                 Auth.host_token(socket),
                 song,
                 delta_ms
               ) do
          preview = %{preview | offset_ms: Catalog.lyric_offset_ms(song)}

          socket
          |> assign(:lyric_preview, preview)
          |> push_preview_sync(preview)
        else
          {:error, reason} -> put_flash(socket, :error, Auth.error_text(reason))
        end
    end
  end

  defp refresh_lyric_preview(socket, %Queue.Entry{} = entry) do
    case socket.assigns.lyric_preview do
      %{entry_id: id} when id == entry.id ->
        case Rooms.lyric_preview(socket.assigns.room, Auth.host_token(socket), entry) do
          {:ok, preview} -> open_preview(socket, preview)
          {:error, _} -> close_preview(socket)
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
      HTML.can_attach_missing_lyrics?(entry) -> :ok
      socket.assigns.host? and HTML.can_replace_lyrics?(entry) -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp search_lyric_hits(socket, entry, title, artist) do
    if HTML.can_replace_lyrics?(entry) do
      Catalog.Lyrics.search(artist, title)
    else
      with {:ok, song} <- ensure_song(socket, entry, title, artist),
           {:ok, _entry} <- Queue.attach_song(entry, song) do
        Catalog.Lyrics.search(artist, title)
      end
    end
  end

  defp song_for_lyric_edit(socket, entry) do
    if HTML.can_replace_lyrics?(entry) do
      case entry.song do
        %{} = song -> {:ok, song}
        _ -> {:error, :not_found}
      end
    else
      ensure_song(socket, entry, entry.song_title, entry.song && entry.song.artist)
    end
  end

  defp ensure_song(socket, %{song: nil} = _entry, title, artist)
       when is_binary(artist) and artist != "" do
    Catalog.create_song(socket.assigns.room, %{title: title, artist: artist})
  end

  defp ensure_song(_socket, %{song: nil}, _title, _artist), do: {:error, :invalid}

  defp ensure_song(_socket, %{song: song}, title, artist) do
    attrs = %{title: title}

    attrs =
      if is_binary(artist) and artist != "", do: Map.put(attrs, :artist, artist), else: attrs

    Catalog.update_song(song, attrs)
  end

  defp parse_delta(delta) do
    case Integer.parse(to_string(delta)) do
      {ms, ""} -> {:ok, ms}
      _ -> :error
    end
  end
end
