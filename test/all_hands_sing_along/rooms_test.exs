# test/all_hands_sing_along/rooms_test.exs
defmodule AllHandsSingAlong.RoomsTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Fixtures
  alias AllHandsSingAlong.Rooms

  test "create_room/0 generates a code and host token" do
    assert {:ok, room} = Rooms.create_room()
    assert String.length(room.code) == 6
    assert room.code == String.upcase(room.code)
    assert is_binary(room.host_token)
    assert byte_size(room.host_token) > 8
  end

  test "get_room_by_code/1 is case-insensitive" do
    {:ok, room} = Rooms.create_room()
    assert {:ok, found} = Rooms.get_room_by_code(String.downcase(room.code))
    assert found.id == room.id
    assert {:error, :not_found} = Rooms.get_room_by_code("NOPE12")
  end

  test "authorize_host/2 accepts only the room token" do
    room = Fixtures.room_fixture()
    assert :ok = Rooms.authorize_host(room, room.host_token)
    assert {:error, :unauthorized} = Rooms.authorize_host(room, "not-the-token-value1")
    assert {:error, :unauthorized} = Rooms.authorize_host(room, nil)
    refute Rooms.host?(room, "nope")
    assert Rooms.host?(room, room.host_token)
  end

  test "play/2 is host-only and falls back to the fixture track" do
    room = Fixtures.room_fixture()
    assert {:error, :unauthorized} = Rooms.play(room, "wrong-token-wrong1")
    assert {:ok, snapshot} = Rooms.play(room, room.host_token)
    assert snapshot.playing?
    assert snapshot.audio_url == AllHandsSingAlong.Catalog.fixture_path()
    assert snapshot.title == AllHandsSingAlong.Catalog.fixture_title()
    assert Enum.any?(snapshot.lyrics, &(&1.text =~ "Headphones"))
  end

  test "play/2 uses the first ready song after reorder" do
    room = Fixtures.room_fixture()
    song_one = Fixtures.song_fixture(room, %{title: "One"})
    song_two = Fixtures.song_fixture(room, %{title: "Two"})

    _first =
      Fixtures.entry_fixture(room, %{singer_name: "Ada", song_title: "One", song: song_one})

    second =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Two", song: song_two})

    assert {:ok, _} = AllHandsSingAlong.Queue.move_ready(second, :up)
    assert {:ok, snapshot} = Rooms.play(room, room.host_token)
    assert snapshot.title == "Two"
    assert snapshot.artist == "Test Artist"
    assert snapshot.singer_name == "Sam"
  end

  test "pause/2 is host-only" do
    room = Fixtures.room_fixture()
    assert {:ok, _} = Rooms.play(room, room.host_token)
    assert {:error, :unauthorized} = Rooms.pause(room, "wrong-token-wrong1")
    assert {:ok, snapshot} = Rooms.pause(room, room.host_token)
    refute snapshot.playing?
  end

  test "nudge_lyrics/3 is host-only and updates offset" do
    room = Fixtures.room_fixture()
    assert {:ok, _} = Rooms.play(room, room.host_token)
    assert {:error, :unauthorized} = Rooms.nudge_lyrics(room, "wrong-token-wrong1", 500)
    assert {:ok, snapshot} = Rooms.nudge_lyrics(room, room.host_token, 500)
    assert snapshot.offset_ms == 500
    assert {:ok, snapshot} = Rooms.nudge_lyrics(room, room.host_token, -1000)
    assert snapshot.offset_ms == -500
  end

  test "tune_lyrics/3 plays the original without starting the singer" do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Tune Me",
        original_path: "/uploads/with-vocals.wav",
        instrumental_path: AllHandsSingAlong.Catalog.fixture_path()
      })

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Tune Me", song: song})

    assert {:error, :unauthorized} = Rooms.tune_lyrics(room, "wrong-token-wrong1", entry)
    assert {:ok, snapshot} = Rooms.tune_lyrics(room, room.host_token, entry)
    assert snapshot.playing?
    assert snapshot.mode == :tuning
    assert snapshot.audio_url == "/uploads/with-vocals.wav"
    assert snapshot.offset_ms == 0

    {:ok, still} = AllHandsSingAlong.Queue.get_entry(entry.id)
    assert still.status == :ready
  end

  test "lyric offset is saved on the song and reused for the singer mix" do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Keep Time",
        original_path: "/uploads/with-vocals.wav",
        instrumental_path: AllHandsSingAlong.Catalog.fixture_path()
      })

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Keep Time", song: song})

    assert {:ok, _} = Rooms.tune_lyrics(room, room.host_token, entry)
    assert {:ok, tuned} = Rooms.nudge_lyrics(room, room.host_token, 500)
    assert tuned.offset_ms == 500

    {:ok, saved} = AllHandsSingAlong.Catalog.get_song(song.id)
    assert saved.lyric_offset_ms == 500

    assert {:ok, singing} = Rooms.play(room, room.host_token)
    assert singing.mode == :singing
    assert singing.audio_url == AllHandsSingAlong.Catalog.fixture_path()
    assert singing.offset_ms == 500

    {:ok, now} = AllHandsSingAlong.Queue.get_entry(entry.id)
    assert now.status == :now_singing
  end
end
