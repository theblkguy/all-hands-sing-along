# test/all_hands_sing_along/catalog/stem_separator_test.exs
defmodule AllHandsSingAlong.Catalog.StemSeparatorTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.StemSeparator
  alias AllHandsSingAlong.Fixtures
  alias AllHandsSingAlong.Queue

  test "enqueue/1 stores an instrumental and marks the queue ready when lyrics exist" do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Isolate Me",
        original_path: Catalog.fixture_path(),
        instrumental_path: nil
      })

    {:ok, entry} =
      Queue.enqueue(room, %{singer_name: "Sam", song_title: song.title, song_id: song.id})

    assert entry.status == :preparing

    assert :ok = StemSeparator.enqueue(song.id)

    {:ok, song} = Catalog.get_song(song.id)
    assert song.stem_status == :ok
    assert song.stem_progress == 100
    assert Catalog.playable?(song)

    {:ok, entry} = Queue.get_entry(entry.id)
    assert entry.status == :ready
  end

  test "enqueue/1 records failure and leaves the row preparing" do
    room = Fixtures.room_fixture()
    Application.put_env(:all_hands_sing_along, :stem_stub, {:error, :not_installed})

    song =
      Fixtures.song_fixture(room, %{
        title: "Broken Stems",
        original_path: Catalog.fixture_path(),
        instrumental_path: nil,
        lrc_text: nil
      })

    {:ok, entry} =
      Queue.enqueue(room, %{singer_name: "Sam", song_title: song.title, song_id: song.id})

    assert :ok = StemSeparator.enqueue(song.id)

    {:ok, song} = Catalog.get_song(song.id)
    assert song.stem_status == :failed
    assert song.stem_error == "Vocal isolation isn’t installed on this machine"
    refute Catalog.playable?(song)

    {:ok, entry} = Queue.get_entry(entry.id)
    assert entry.status == :preparing
    refute Catalog.has_lyrics?(entry.song)
  end

  test "enqueue/1 waits for a remote Mac worker when Demucs is not on this machine" do
    room = Fixtures.room_fixture()
    Application.put_env(:all_hands_sing_along, :stem_available, false)

    song =
      Fixtures.song_fixture(room, %{
        title: "Remote Stems",
        original_path: Catalog.fixture_path(),
        instrumental_path: nil
      })

    assert :ok = StemSeparator.enqueue(song.id)

    {:ok, song} = Catalog.get_song(song.id)
    assert song.stem_status == :queued
    refute Catalog.playable?(song)

    assert {:ok, claimed} = StemSeparator.claim_remote_job(room.id)
    assert claimed.id == song.id
    assert claimed.stem_status == :running

    wav = Path.join(:code.priv_dir(:all_hands_sing_along), "static/audio/fixture.wav")
    assert :ok = StemSeparator.complete_remote_job(room.id, song.id, wav, "no_vocals.wav")

    {:ok, done} = Catalog.get_song(song.id)
    assert done.stem_status == :ok
    assert Catalog.playable?(done)
  end

  test "claim_remote_job/1 only returns songs from that room" do
    room_a = Fixtures.room_fixture()
    room_b = Fixtures.room_fixture()
    Application.put_env(:all_hands_sing_along, :stem_available, false)

    song_b =
      Fixtures.song_fixture(room_b, %{
        title: "Other Room",
        original_path: Catalog.fixture_path(),
        instrumental_path: nil
      })

    assert :ok = StemSeparator.enqueue(song_b.id)
    assert :empty = StemSeparator.claim_remote_job(room_a.id)

    {:ok, still} = Catalog.get_song(song_b.id)
    assert still.stem_status == :queued
  end

  test "skips isolation when an instrumental is already attached" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room, %{title: "Already Backing"})
    assert song.stem_status == :ok

    assert :ok = StemSeparator.enqueue(song.id)

    {:ok, same} = Catalog.get_song(song.id)
    assert same.instrumental_path == song.instrumental_path
  end
end
