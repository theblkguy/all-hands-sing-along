# test/all_hands_sing_along/rooms/sync_test.exs
defmodule AllHandsSingAlong.Rooms.SyncTest do
  use ExUnit.Case, async: true

  alias AllHandsSingAlong.Rooms.Sync

  test "client_position_ms/5 holds still when paused" do
    assert Sync.client_position_ms(1_200, 10_000, 10_500, 0, false) == 1_200
  end

  test "client_position_ms/5 advances from server time while playing" do
    assert Sync.client_position_ms(1_000, 5_000, 5_250, 0, true) == 1_250
  end

  test "client_position_ms/5 applies a clock offset" do
    assert Sync.client_position_ms(1_000, 5_000, 5_000, 80, true) == 1_080
  end

  test "client_position_ms/5 never goes negative" do
    assert Sync.client_position_ms(10, 5_000, 4_000, 0, true) == 0
  end

  test "parse_lrc/1 reads timed lines" do
    lyrics = Sync.parse_lrc("[00:00.00]Hello\n[00:01.50]World\n")
    assert [%{time_ms: 0, text: "Hello"}, %{time_ms: 1_500, text: "World"}] = lyrics
  end

  test "current_line/2 picks the last line at or before the playhead" do
    lyrics = Sync.parse_lrc("[00:00.00]Hello\n[00:01.50]World\n")
    assert %{text: "Hello"} = Sync.current_line(lyrics, 200)
    assert %{text: "World"} = Sync.current_line(lyrics, 1_500)
    assert %{text: ""} = Sync.current_line(lyrics, -1)
  end
end
