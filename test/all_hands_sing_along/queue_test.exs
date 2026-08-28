# test/all_hands_sing_along/queue_test.exs
defmodule AllHandsSingAlong.QueueTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Fixtures
  alias AllHandsSingAlong.Queue
  alias AllHandsSingAlong.Rooms

  test "enqueue/2 appends preparing entries without a playable song" do
    room = Fixtures.room_fixture()
    {:ok, first} = Queue.enqueue(room, %{singer_name: "Ada", song_title: "One"})
    {:ok, second} = Queue.enqueue(room, %{singer_name: "Sam", song_title: "Two"})
    assert first.position == 1
    assert first.status == :preparing
    assert second.position == 2
    assert Enum.map(Queue.list_entries(room.id), & &1.song_title) == ["One", "Two"]
  end

  test "enqueue/2 marks prepared songs ready" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)

    {:ok, entry} =
      Queue.enqueue(room, %{singer_name: "Sam", song_title: song.title, song_id: song.id})

    assert entry.status == :ready
  end

  test "enqueue/2 stays preparing without lyrics" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room, %{lrc_text: nil, title: "No Lyrics"})

    {:ok, entry} =
      Queue.enqueue(room, %{singer_name: "Sam", song_title: song.title, song_id: song.id})

    assert entry.status == :preparing
  end

  test "next_ready/1 skips requested and preparing entries" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)

    requested =
      Fixtures.entry_fixture(room, %{singer_name: "A", song_title: "Wait", status: :requested})

    preparing =
      Fixtures.entry_fixture(room, %{
        singer_name: "B",
        song_title: "Prep",
        status: :preparing,
        song: song
      })

    ready = Fixtures.entry_fixture(room, %{singer_name: "C", song_title: "Go", song: song})
    later = Fixtures.entry_fixture(room, %{singer_name: "D", song_title: "Later", song: song})

    {:ok, _} = Queue.mark_status(preparing, :preparing)
    {:ok, _} = Queue.mark_ready(ready)
    {:ok, _} = Queue.mark_ready(later)

    assert {:ok, next} = Queue.next_ready(room.id)
    assert next.id == ready.id
    refute next.id == requested.id
  end

  test "mark_ready/1 requires playable audio and lyrics" do
    room = Fixtures.room_fixture()
    entry = Fixtures.entry_fixture(room, %{song_title: "No File"})
    assert {:error, :missing_audio} = Queue.mark_ready(entry)

    no_lyrics = Fixtures.song_fixture(room, %{lrc_text: nil, title: "Audio Only"})
    with_audio = Fixtures.entry_fixture(room, %{song_title: "Has File", song: no_lyrics})
    assert {:error, :missing_lyrics} = Queue.mark_ready(with_audio)

    song = Fixtures.song_fixture(room)

    prepared =
      Fixtures.entry_fixture(room, %{song_title: "Ready", song: song, status: :preparing})

    assert {:ok, ready} = Queue.mark_ready(prepared)
    assert ready.status == :ready
  end

  test "move_ready/2 reorders only ready songs" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)
    first = Fixtures.entry_fixture(room, %{singer_name: "A", song_title: "One", song: song})
    second = Fixtures.entry_fixture(room, %{singer_name: "B", song_title: "Two", song: song})
    preparing = Fixtures.entry_fixture(room, %{singer_name: "C", song_title: "Wait"})

    assert first.status == :ready
    assert second.status == :ready
    assert {:ok, moved} = Queue.move_ready(second, :up)
    assert moved.id == second.id

    titles = Enum.map(Queue.list_entries(room.id), & &1.song_title)
    assert titles == ["Two", "One", "Wait"]

    assert {:ok, next} = Queue.next_ready(room.id)
    assert next.id == second.id

    assert {:error, :not_ready} = Queue.move_ready(preparing, :up)
  end

  test "mark_now_singing/1 finishes the previous singer" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)
    first = Fixtures.entry_fixture(room, %{singer_name: "A", song_title: "One", song: song})
    second = Fixtures.entry_fixture(room, %{singer_name: "B", song_title: "Two", song: song})
    {:ok, first} = Queue.mark_ready(first)
    {:ok, second} = Queue.mark_ready(second)

    {:ok, singing} = Queue.mark_now_singing(first)
    assert singing.status == :now_singing
    {:ok, singing} = Queue.mark_now_singing(second)
    assert singing.id == second.id
    {:ok, done} = Queue.get_entry(first.id)
    assert done.status == :done
  end

  test "host mark_entry_ready/3 re-checks the token" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)
    entry = Fixtures.entry_fixture(room, %{song: song, status: :preparing})
    assert {:error, :unauthorized} = Rooms.mark_entry_ready(room, "wrong-token-wrong1", entry)
    assert {:ok, ready} = Rooms.mark_entry_ready(room, room.host_token, entry)
    assert ready.status == :ready
  end

  test "host move_ready_entry/4 re-checks the token" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)
    first = Fixtures.entry_fixture(room, %{song_title: "One", song: song})
    second = Fixtures.entry_fixture(room, %{song_title: "Two", song: song})

    assert {:error, :unauthorized} =
             Rooms.move_ready_entry(room, "wrong-token-wrong1", second, :up)

    assert {:ok, moved} = Rooms.move_ready_entry(room, room.host_token, second, :up)
    assert moved.id == second.id
    assert {:ok, next} = Queue.next_ready(room.id)
    assert next.id == second.id
    assert first.id != next.id
  end
end
