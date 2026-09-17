# test/all_hands_sing_along/catalog/stem_cache_test.exs
defmodule AllHandsSingAlong.Catalog.StemCacheTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.StemCache
  alias AllHandsSingAlong.Catalog.StemSeparator
  alias AllHandsSingAlong.Fixtures
  alias AllHandsSingAlong.Queue

  @hash String.duplicate("ab", 32)

  test "put/lookup round-trips and counts hits" do
    assert StemCache.lookup(@hash, 0.12) == nil
    assert :ok = StemCache.put(@hash, 0.12, "/uploads/cached.mp3", "test")
    assert StemCache.lookup(@hash, 0.12) == "/uploads/cached.mp3"
    # A different guide-vocal mix is a different cache entry.
    assert StemCache.lookup(@hash, 0.0) == nil
    # First write wins; a second put is a no-op.
    assert :ok = StemCache.put(@hash, 0.12, "/uploads/other.mp3", "test")
    assert StemCache.lookup(@hash, 0.12) == "/uploads/cached.mp3"
    assert Repo.get_by!(StemCache, content_hash: @hash).hits == 2
  end

  test "enqueue/1 short-circuits to the cached instrumental" do
    room = Fixtures.room_fixture()
    Application.put_env(:all_hands_sing_along, :stem_available, false)
    on_exit(fn -> Application.put_env(:all_hands_sing_along, :stem_available, true) end)

    :ok = StemCache.put(@hash, StemSeparator.vocal_mix(), "/uploads/cached.mp3", "test")

    song =
      Fixtures.song_fixture(room, %{
        title: "Seen Before",
        original_path: Catalog.fixture_path(),
        instrumental_path: nil,
        content_hash: @hash
      })

    {:ok, entry} =
      Queue.enqueue(room, %{singer_name: "Sam", song_title: song.title, song_id: song.id})

    assert entry.status == :preparing

    # No adapter is available, yet the song becomes playable immediately.
    assert :ok = StemSeparator.enqueue(song.id)

    {:ok, song} = Catalog.get_song(song.id)
    assert song.stem_status == :ok
    assert song.instrumental_path == "/uploads/cached.mp3"

    {:ok, entry} = Queue.get_entry(entry.id)
    assert entry.status == :ready
  end

  test "a finished separation is written to the cache" do
    room = Fixtures.room_fixture()
    hash = String.duplicate("cd", 32)

    song =
      Fixtures.song_fixture(room, %{
        original_path: Catalog.fixture_path(),
        instrumental_path: nil,
        content_hash: hash
      })

    assert :ok = StemSeparator.enqueue(song.id)
    {:ok, song} = Catalog.get_song(song.id)
    assert StemCache.lookup(hash, StemSeparator.vocal_mix()) == song.instrumental_path
  end
end
