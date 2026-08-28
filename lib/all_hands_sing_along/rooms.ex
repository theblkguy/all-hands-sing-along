# lib/all_hands_sing_along/rooms.ex
defmodule AllHandsSingAlong.Rooms do
  @moduledoc """
  Rooms, host authorization, and playback commands.
  """
  require Logger

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Queue.Entry
  alias AllHandsSingAlong.Repo
  alias AllHandsSingAlong.Rooms.Playback
  alias AllHandsSingAlong.Rooms.Room
  alias AllHandsSingAlong.Rooms.Sync

  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6

  @spec create_room() :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def create_room do
    insert_room(5)
  end

  @spec get_room_by_code(String.t()) :: {:ok, Room.t()} | {:error, :not_found}
  def get_room_by_code(code) when is_binary(code) do
    case Repo.get_by(Room, code: Room.normalize_code(code)) do
      nil -> {:error, :not_found}
      room -> {:ok, room}
    end
  end

  def get_room_by_code(_), do: {:error, :not_found}

  @spec host?(Room.t(), String.t() | nil) :: boolean()
  def host?(%Room{} = room, token) when is_binary(token) do
    authorize_host(room, token) == :ok
  end

  def host?(%Room{}, _), do: false

  @spec authorize_host(Room.t(), String.t() | nil) :: :ok | {:error, :unauthorized}
  def authorize_host(%Room{host_token: expected}, token)
      when is_binary(expected) and is_binary(token) and byte_size(expected) == byte_size(token) do
    if Plug.Crypto.secure_compare(expected, token), do: :ok, else: {:error, :unauthorized}
  end

  def authorize_host(%Room{}, _), do: {:error, :unauthorized}

  @spec play(Room.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def play(%Room{} = room, token) do
    with :ok <- authorize_host(room, token) do
      case Playback.get(room.id) do
        %{playing?: true, audio_url: url} when is_binary(url) ->
          {:ok, Playback.get(room.id)}

        %{audio_url: url, playing?: false} when is_binary(url) ->
          :ok = Playback.resume(room.id)
          {:ok, Playback.get(room.id)}

        _ ->
          start_track(room)
      end
    end
  end

  @spec pause(Room.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def pause(%Room{} = room, token) do
    with :ok <- authorize_host(room, token),
         :ok <- Playback.pause(room.id) do
      {:ok, Playback.get(room.id)}
    end
  end

  @spec skip(Room.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def skip(%Room{} = room, token) do
    with :ok <- authorize_host(room, token) do
      Queue.finish_now_singing(room.id)

      Phoenix.PubSub.broadcast(
        AllHandsSingAlong.PubSub,
        Queue.topic(room.code),
        {:queue_updated, room.id}
      )

      start_track(room)
    end
  end

  @spec nudge_lyrics(Room.t(), String.t(), integer()) :: {:ok, map()} | {:error, atom()}
  def nudge_lyrics(%Room{} = room, token, delta_ms) when is_integer(delta_ms) do
    with :ok <- authorize_host(room, token),
         :ok <- Playback.nudge_offset(room.id, delta_ms) do
      {:ok, Playback.get(room.id)}
    end
  end

  @spec mark_entry_ready(Room.t(), String.t(), Entry.t()) ::
          {:ok, Entry.t()} | {:error, atom() | Ecto.Changeset.t()}
  def mark_entry_ready(%Room{} = room, token, %Entry{} = entry) do
    with :ok <- authorize_host(room, token),
         true <- entry.room_id == room.id do
      Queue.mark_ready(entry)
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec mark_entry_preparing(Room.t(), String.t(), Entry.t()) ::
          {:ok, Entry.t()} | {:error, atom() | Ecto.Changeset.t()}
  def mark_entry_preparing(%Room{} = room, token, %Entry{} = entry) do
    with :ok <- authorize_host(room, token),
         true <- entry.room_id == room.id do
      Queue.mark_status(entry, :preparing)
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec move_ready_entry(Room.t(), String.t(), Entry.t(), :up | :down) ::
          {:ok, Entry.t()} | {:error, atom() | Ecto.Changeset.t()}
  def move_ready_entry(%Room{} = room, token, %Entry{} = entry, direction)
      when direction in [:up, :down] do
    with :ok <- authorize_host(room, token),
         true <- entry.room_id == room.id do
      Queue.move_ready(entry, direction)
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec playback_snapshot(Room.t()) :: map() | nil
  def playback_snapshot(%Room{} = room), do: Playback.get(room.id)

  defp start_track(room) do
    case current_or_next_ready(room) do
      {:ok, entry} ->
        {:ok, entry} = Queue.mark_now_singing(entry)
        track = track_from_entry(room, entry)
        :ok = Playback.play(room.id, track)
        {:ok, Playback.get(room.id)}

      {:error, :none_ready} ->
        track = fixture_track(room)
        :ok = Playback.play(room.id, track)
        {:ok, Playback.get(room.id)}
    end
  end

  defp current_or_next_ready(room) do
    case Queue.current_singing(room.id) do
      {:ok, entry} -> {:ok, entry}
      {:error, :not_found} -> Queue.next_ready(room.id)
    end
  end

  defp track_from_entry(room, %Entry{} = entry) do
    song = entry.song
    audio_url = Catalog.playable_path(song) || Catalog.fixture_path()
    lrc = (song && song.lrc_text) || Catalog.fixture_lrc()

    %{
      room_code: room.code,
      audio_url: audio_url,
      lyrics: Sync.parse_lrc(lrc),
      title: entry.song_title,
      artist: song && song.artist,
      singer_name: entry.singer_name,
      position_ms: 0
    }
  end

  defp fixture_track(room) do
    %{
      room_code: room.code,
      audio_url: Catalog.fixture_path(),
      lyrics: Sync.parse_lrc(Catalog.fixture_lrc()),
      title: Catalog.fixture_title(),
      artist: nil,
      singer_name: nil,
      position_ms: 0
    }
  end

  defp insert_room(retries) when retries > 0 do
    attrs = %{code: generate_code(), host_token: generate_token()}

    case %Room{} |> Room.changeset(attrs) |> Repo.insert() do
      {:ok, room} ->
        {:ok, room}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if Keyword.has_key?(errors, :code) do
          insert_room(retries - 1)
        else
          Logger.error("Failed to create room", errors: inspect(errors))
          error
        end
    end
  end

  defp insert_room(_retries) do
    {:error, Room.changeset(%Room{}, %{})}
  end

  defp generate_code do
    1..@code_length
    |> Enum.map(fn _ -> Enum.random(@code_alphabet) end)
    |> List.to_string()
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
