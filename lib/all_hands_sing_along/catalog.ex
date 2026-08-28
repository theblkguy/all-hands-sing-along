# lib/all_hands_sing_along/catalog.ex
defmodule AllHandsSingAlong.Catalog do
  @moduledoc """
  Songs and playable audio paths.
  """
  import Ecto.Query

  alias AllHandsSingAlong.Catalog.Lyrics
  alias AllHandsSingAlong.Catalog.Song
  alias AllHandsSingAlong.Repo
  alias AllHandsSingAlong.Rooms.Room

  @fixture_path "/audio/fixture.wav"
  @fixture_title "Demo Track"

  @spec fixture_path() :: String.t()
  def fixture_path, do: @fixture_path

  @spec fixture_title() :: String.t()
  def fixture_title, do: @fixture_title

  @spec fixture_lrc() :: String.t()
  def fixture_lrc do
    """
    [00:00.00]Headphones on — Zoom is for faces
    [00:02.00]This is a demo backing track
    [00:05.00]Add a song to the queue to sing for real
    """
  end

  @spec get_song(integer()) :: {:ok, Song.t()} | {:error, :not_found}
  def get_song(id) when is_integer(id) do
    case Repo.get(Song, id) do
      nil -> {:error, :not_found}
      song -> {:ok, song}
    end
  end

  def get_song(_), do: {:error, :not_found}

  @spec create_song(Room.t() | nil, map()) :: {:ok, Song.t()} | {:error, Ecto.Changeset.t()}
  def create_song(%Room{} = room, attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> Map.put("room_id", room.id)
    |> create_song()
  end

  def create_song(attrs) when is_map(attrs) do
    %Song{}
    |> Song.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_song(Song.t(), map()) :: {:ok, Song.t()} | {:error, Ecto.Changeset.t()}
  def update_song(%Song{} = song, attrs) when is_map(attrs) do
    song
    |> Song.changeset(attrs)
    |> Repo.update()
  end

  @spec create_prepared_song(Room.t(), map()) ::
          {:ok, Song.t()} | {:error, Ecto.Changeset.t()}
  def create_prepared_song(%Room{} = room, attrs) when is_map(attrs) do
    with {:ok, song} <- create_song(room, attrs) do
      {:ok, maybe_attach_lyrics(song)}
    end
  end

  @spec maybe_attach_lyrics(Song.t()) :: Song.t()
  def maybe_attach_lyrics(%Song{} = song) do
    if has_lyrics?(song) do
      song
    else
      case Lyrics.resolve(song.artist, song.title) do
        {:ok, lrc} ->
          case update_song(song, %{lrc_text: lrc}) do
            {:ok, updated} -> updated
            {:error, _} -> song
          end

        {:error, _} ->
          song
      end
    end
  end

  @spec playable_path(Song.t() | nil) :: String.t() | nil
  def playable_path(nil), do: nil

  def playable_path(%Song{} = song) do
    song.instrumental_path || song.original_path
  end

  @spec playable?(Song.t() | nil) :: boolean()
  def playable?(song) do
    path = playable_path(song)
    is_binary(path) and path != ""
  end

  @spec has_lyrics?(Song.t() | nil) :: boolean()
  def has_lyrics?(nil), do: false

  def has_lyrics?(%Song{lrc_text: text}) when is_binary(text), do: String.trim(text) != ""

  def has_lyrics?(%Song{}), do: false

  @spec prepared?(Song.t() | nil) :: boolean()
  def prepared?(song), do: playable?(song) and has_lyrics?(song)

  @spec apply_lrc(Song.t(), String.t()) ::
          {:ok, Song.t()} | {:error, :invalid_lrc | Ecto.Changeset.t()}
  def apply_lrc(%Song{} = song, lrc) when is_binary(lrc) do
    lines = AllHandsSingAlong.Rooms.Sync.parse_lrc(lrc)

    if lines == [] do
      {:error, :invalid_lrc}
    else
      update_song(song, %{lrc_text: lrc})
    end
  end

  @spec format_title(String.t() | nil, String.t() | nil) :: String.t() | nil
  def format_title(title, artist) when is_binary(title) and is_binary(artist) do
    if String.trim(artist) == "", do: title, else: "#{title} — #{artist}"
  end

  def format_title(title, _) when is_binary(title), do: title
  def format_title(_, _), do: nil

  @spec list_room_songs(integer()) :: [Song.t()]
  def list_room_songs(room_id) when is_integer(room_id) do
    Song
    |> where([s], s.room_id == ^room_id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
