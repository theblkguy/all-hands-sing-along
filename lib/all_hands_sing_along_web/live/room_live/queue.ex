# lib/all_hands_sing_along_web/live/room_live/queue.ex
defmodule AllHandsSingAlongWeb.RoomLive.Queue do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2, upload_errors: 1, upload_errors: 2]

  import Phoenix.LiveView,
    only: [
      cancel_upload: 3,
      consume_uploaded_entries: 3,
      put_flash: 3,
      stream: 4
    ]

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.Song
  alias AllHandsSingAlong.Catalog.Uploads
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms
  alias AllHandsSingAlongWeb.RoomLive.Auth
  alias AllHandsSingAlongWeb.RoomLive.HTML

  def validate(socket, params) when is_map(params) do
    changeset =
      %Song{}
      |> Song.changeset(params["song"] || %{})
      |> Map.put(:action, :validate)

    socket = assign(socket, :song_form, to_form(changeset, as: :song))

    case first_upload_error(socket, :audio) || first_upload_error(socket, :lrc) do
      nil -> {:noreply, socket}
      reason -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def add(socket, params) when is_map(params) do
    changeset =
      %Song{}
      |> Song.changeset(params["song"] || %{})
      |> Map.put(:action, :insert)

    socket = assign(socket, :song_form, to_form(changeset, as: :song))

    with {:ok, %{title: title, artist: artist}} <- Ecto.Changeset.apply_action(changeset, :insert),
         :ok <- upload_ok(socket, :audio),
         :ok <- upload_ok(socket, :lrc),
         :ok <- audio_cap_ok(socket, :audio) do
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
                assign(socket, :song_form, to_form(Song.changeset(%Song{}, %{}), as: :song))

              socket =
                if Catalog.has_lyrics?(song) do
                  socket
                else
                  put_flash(
                    socket,
                    :error,
                    "No timed lyrics for #{title} — #{artist}. Search below, or paste an .lrc."
                  )
                end

              {:noreply, socket}

            {:error, changeset} ->
              {:noreply, put_flash(socket, :error, Auth.error_text(changeset))}
          end

        {:error, socket, reason} ->
          {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :song_form, to_form(changeset, as: :song))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def validate_late_audio(socket) do
    case first_upload_error(socket, :late_audio) do
      nil -> {:noreply, socket}
      reason -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def start_attach_audio(socket, id) do
    with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
         true <- can_attach_audio?(socket, entry) do
      {:noreply,
       socket
       |> assign(:attaching_audio_id, entry.id)
       |> stream(:queue, Queue.list_entries(socket.assigns.room.id), reset: true)}
    else
      false ->
        {:noreply, put_flash(socket, :error, "You can only add audio to your own song")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def attach_audio(socket, id) do
    case Auth.fetch_room_entry(socket, id) do
      {:ok, entry} ->
        cond do
          not can_attach_audio?(socket, entry) ->
            {:noreply, put_flash(socket, :error, "You can only add audio to your own song")}

          not Catalog.missing_audio?(entry.song) ->
            {:noreply, put_flash(socket, :error, "This song already has audio")}

          not Catalog.audio_slot_available?(socket.assigns.room) ->
            {:noreply, put_flash(socket, :error, Auth.error_text(:room_full))}

          true ->
            save_late_audio(socket, entry)
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
    end
  end

  def move_ready(socket, id, direction) do
    parsed =
      case direction do
        "up" -> :up
        "down" -> :down
        _ -> nil
      end

    if parsed do
      host_queue_action(socket, id, fn entry ->
        Rooms.move_ready_entry(socket.assigns.room, Auth.host_token(socket), entry, parsed)
      end)
    else
      {:noreply, put_flash(socket, :error, Auth.error_text(:invalid_direction))}
    end
  end

  def retry_stems(socket, id) do
    host_queue_action(socket, id, fn entry ->
      Rooms.retry_stems(socket.assigns.room, Auth.host_token(socket), entry)
    end)
  end

  def cancel_stems(socket, id) do
    host_queue_action(socket, id, fn entry ->
      Rooms.cancel_stems(socket.assigns.room, Auth.host_token(socket), entry)
    end)
  end

  def use_original(socket, id) do
    host_queue_action(socket, id, fn entry ->
      Rooms.use_original_audio(socket.assigns.room, Auth.host_token(socket), entry)
    end)
  end

  defp host_queue_action(socket, id, fun) do
    Auth.with_host(socket, fn socket ->
      with {:ok, entry} <- Auth.fetch_room_entry(socket, id),
           {:ok, _} <- fun.(entry) do
        {:noreply, socket}
      else
        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "That song isn't in the queue")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
      end
    end)
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
              {:error, :invalid}

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
           |> put_flash(:info, "Audio saved")}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Auth.error_text(reason))}
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
    HTML.can_attach_audio?(socket.assigns.host?, socket.assigns.display_name, entry)
  end

  defp cancel_entries(socket, name) do
    entries = socket.assigns.uploads[name].entries
    Enum.reduce(entries, socket, fn entry, acc -> cancel_upload(acc, name, entry.ref) end)
  end

  defp first_upload_error(socket, name) do
    uploads = socket.assigns.uploads[name]
    config_error = List.first(upload_errors(uploads))

    entry_error =
      uploads.entries
      |> Enum.flat_map(&upload_errors(uploads, &1))
      |> List.first()

    config_error || entry_error
  end

  defp upload_ok(socket, name) do
    case first_upload_error(socket, name) do
      nil -> :ok
      reason -> {:error, reason}
    end
  end

  defp audio_cap_ok(socket, name) do
    entries = socket.assigns.uploads[name].entries

    cond do
      entries == [] -> :ok
      Catalog.audio_slot_available?(socket.assigns.room) -> :ok
      true -> {:error, :room_full}
    end
  end
end
