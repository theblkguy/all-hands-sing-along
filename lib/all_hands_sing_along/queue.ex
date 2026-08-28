# lib/all_hands_sing_along/queue.ex
defmodule AllHandsSingAlong.Queue do
  @moduledoc """
  Room singer queue. Playback never waits on a non-ready entry.
  """
  import Ecto.Query

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Queue.Entry
  alias AllHandsSingAlong.Repo
  alias AllHandsSingAlong.Rooms.Room

  @topic_prefix "room:"

  @spec topic(String.t()) :: String.t()
  def topic(code) when is_binary(code), do: @topic_prefix <> code

  @spec list_entries(integer()) :: [Entry.t()]
  def list_entries(room_id) when is_integer(room_id) do
    Entry
    |> where([e], e.room_id == ^room_id)
    |> order_by([e], asc: e.position)
    |> preload(:song)
    |> Repo.all()
  end

  @spec get_entry(integer()) :: {:ok, Entry.t()} | {:error, :not_found}
  def get_entry(id) when is_integer(id) do
    case Repo.get(Entry, id) |> Repo.preload(:song) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  def get_entry(_), do: {:error, :not_found}

  @spec enqueue(Room.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(%Room{} = room, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:room_id, room.id)
      |> Map.put_new(:position, next_position(room.id))
      |> Map.put_new(:status, infer_status(attrs))

    result =
      %Entry{}
      |> Entry.changeset(attrs)
      |> Repo.insert()

    with {:ok, entry} <- result do
      broadcast(room.code, {:queue_updated, room.id})
      {:ok, Repo.preload(entry, :song)}
    end
  end

  @spec next_ready(integer()) :: {:ok, Entry.t()} | {:error, :none_ready}
  def next_ready(room_id) when is_integer(room_id) do
    Entry
    |> where([e], e.room_id == ^room_id and e.status == :ready)
    |> order_by([e], asc: e.position)
    |> preload(:song)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :none_ready}
      entry -> {:ok, entry}
    end
  end

  @spec current_singing(integer()) :: {:ok, Entry.t()} | {:error, :not_found}
  def current_singing(room_id) when is_integer(room_id) do
    Entry
    |> where([e], e.room_id == ^room_id and e.status == :now_singing)
    |> preload(:song)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @spec mark_status(Entry.t(), Entry.status()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def mark_status(%Entry{} = entry, status)
      when status in [:requested, :preparing, :ready, :now_singing, :done] do
    room = Repo.get!(Room, entry.room_id)

    result =
      entry
      |> Entry.status_changeset(status)
      |> Repo.update()

    with {:ok, updated} <- result do
      broadcast(room.code, {:queue_updated, room.id})
      {:ok, Repo.preload(updated, :song, force: true)}
    end
  end

  @spec mark_ready(Entry.t()) ::
          {:ok, Entry.t()} | {:error, :missing_audio | :missing_lyrics | Ecto.Changeset.t()}
  def mark_ready(%Entry{} = entry) do
    entry = Repo.preload(entry, :song)

    cond do
      not Catalog.playable?(entry.song) -> {:error, :missing_audio}
      not Catalog.has_lyrics?(entry.song) -> {:error, :missing_lyrics}
      true -> mark_status(entry, :ready)
    end
  end

  @spec sync_preparation(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def sync_preparation(%Entry{} = entry) do
    entry = Repo.preload(entry, :song, force: true)

    cond do
      entry.status in [:now_singing, :done] ->
        {:ok, entry}

      Catalog.prepared?(entry.song) ->
        mark_ready(entry)

      true ->
        mark_status(entry, :preparing)
    end
  end

  @spec move_ready(Entry.t(), :up | :down) ::
          {:ok, Entry.t()} | {:error, :not_ready | :not_found | Ecto.Changeset.t()}
  def move_ready(%Entry{} = entry, direction) when direction in [:up, :down] do
    entry = Repo.preload(entry, :song)

    if entry.status == :ready do
      swap_ready_neighbor(entry, direction)
    else
      {:error, :not_ready}
    end
  end

  @spec mark_now_singing(Entry.t()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def mark_now_singing(%Entry{} = entry) do
    Repo.transaction(fn ->
      finish_now_singing(entry.room_id)

      case mark_status(entry, :now_singing) do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec finish_now_singing(integer()) :: :ok
  def finish_now_singing(room_id) when is_integer(room_id) do
    from(e in Entry,
      where: e.room_id == ^room_id and e.status == :now_singing,
      update: [set: [status: :done, updated_at: ^DateTime.utc_now(:second)]]
    )
    |> Repo.update_all([])

    :ok
  end

  @spec attach_song(Entry.t(), AllHandsSingAlong.Catalog.Song.t()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def attach_song(%Entry{} = entry, %AllHandsSingAlong.Catalog.Song{} = song) do
    room = Repo.get!(Room, entry.room_id)

    result =
      entry
      |> Entry.changeset(%{song_id: song.id, song_title: song.title})
      |> Repo.update()

    with {:ok, updated} <- result do
      broadcast(room.code, {:queue_updated, room.id})
      sync_preparation(Repo.preload(updated, :song, force: true))
    end
  end

  defp infer_status(attrs) do
    song_id = Map.get(attrs, :song_id) || Map.get(attrs, "song_id")
    song = song_id && Repo.get(Catalog.Song, song_id)

    if Catalog.prepared?(song), do: :ready, else: :preparing
  end

  defp swap_ready_neighbor(entry, direction) do
    ready =
      Entry
      |> where([e], e.room_id == ^entry.room_id and e.status == :ready)
      |> order_by([e], asc: e.position)
      |> Repo.all()

    index = Enum.find_index(ready, &(&1.id == entry.id))
    swap_index = neighbor_index(index, direction)

    cond do
      is_nil(index) ->
        {:error, :not_found}

      is_nil(swap_index) or swap_index < 0 or swap_index >= length(ready) ->
        {:ok, entry}

      true ->
        other = Enum.at(ready, swap_index)
        swap_positions(entry, other)
    end
  end

  defp neighbor_index(nil, _direction), do: nil
  defp neighbor_index(index, :up), do: index - 1
  defp neighbor_index(index, :down), do: index + 1

  defp swap_positions(entry, other) do
    room = Repo.get!(Room, entry.room_id)
    entry_pos = entry.position
    other_pos = other.position

    result =
      Repo.transaction(fn ->
        {:ok, _} = entry |> Entry.changeset(%{position: other_pos}) |> Repo.update()
        {:ok, _} = other |> Entry.changeset(%{position: entry_pos}) |> Repo.update()
        Repo.preload(Repo.get!(Entry, entry.id), :song)
      end)

    with {:ok, updated} <- result do
      broadcast(room.code, {:queue_updated, room.id})
      {:ok, updated}
    end
  end

  defp next_position(room_id) do
    Entry
    |> where([e], e.room_id == ^room_id)
    |> select([e], coalesce(max(e.position), 0))
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp broadcast(code, message) do
    Phoenix.PubSub.broadcast(AllHandsSingAlong.PubSub, topic(code), message)
  end
end
