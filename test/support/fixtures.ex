# test/support/fixtures.ex
defmodule AllHandsSingAlong.Fixtures do
  @moduledoc false

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms

  def room_fixture do
    {:ok, room} = Rooms.create_room()
    room
  end

  def song_fixture(room, attrs \\ %{}) do
    defaults = %{
      title: "Test Song",
      artist: "Test Artist",
      original_path: Catalog.fixture_path(),
      instrumental_path: Catalog.fixture_path(),
      lrc_text: Catalog.fixture_lrc()
    }

    {:ok, song} = Catalog.create_song(room, Map.merge(defaults, attrs))
    song
  end

  def entry_fixture(room, attrs \\ %{}) do
    song = Map.get(attrs, :song) || Map.get(attrs, "song")

    base = %{
      singer_name: "Sam",
      song_title: "Test Song"
    }

    attrs =
      base
      |> Map.merge(Map.drop(attrs, [:song, "song"]))
      |> then(fn map ->
        if song, do: Map.put(map, :song_id, song.id), else: map
      end)

    {:ok, entry} = Queue.enqueue(room, attrs)
    entry
  end
end
