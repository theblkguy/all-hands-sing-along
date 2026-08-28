# test/all_hands_sing_along/catalog_test.exs
defmodule AllHandsSingAlong.CatalogTest do
  use AllHandsSingAlong.DataCase

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Fixtures

  test "create_song/2 and playable_path/1 prefer instrumental" do
    room = Fixtures.room_fixture()

    assert {:ok, song} =
             Catalog.create_song(room, %{
               title: "Levitating",
               artist: "Dua Lipa",
               original_path: "/uploads/orig.mp3",
               instrumental_path: "/uploads/inst.mp3"
             })

    assert Catalog.playable_path(song) == "/uploads/inst.mp3"
    assert Catalog.playable?(song)
  end

  test "create_song/2 requires artist" do
    room = Fixtures.room_fixture()
    assert {:error, changeset} = Catalog.create_song(room, %{title: "Levitating"})
    assert %{artist: ["can't be blank"]} = errors_on(changeset)
  end

  test "create_prepared_song/2 fetches lyrics when none are uploaded" do
    room = Fixtures.room_fixture()
    stub_lyrics_synced("[00:00.00]If you wanna run away")

    assert {:ok, song} =
             Catalog.create_prepared_song(room, %{
               title: "Levitating",
               artist: "Dua Lipa"
             })

    assert song.lrc_text =~ "run away"
  end

  test "create_prepared_song/2 keeps an uploaded LRC" do
    room = Fixtures.room_fixture()
    stub_lyrics_synced("[00:00.00]from the network")

    assert {:ok, song} =
             Catalog.create_prepared_song(room, %{
               title: "Levitating",
               artist: "Dua Lipa",
               lrc_text: "[00:00.00]Mine"
             })

    assert song.lrc_text == "[00:00.00]Mine"
  end

  test "prepared?/1 needs audio and lyrics" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room)
    assert Catalog.prepared?(song)

    no_lyrics = Fixtures.song_fixture(room, %{lrc_text: nil, title: "No Lyrics"})
    refute Catalog.has_lyrics?(no_lyrics)
    refute Catalog.prepared?(no_lyrics)
  end

  test "format_title/2 joins title and artist" do
    assert Catalog.format_title("Levitating", "Dua Lipa") == "Levitating — Dua Lipa"
    assert Catalog.format_title("Levitating", "  ") == "Levitating"
    assert Catalog.format_title("Levitating", nil) == "Levitating"
  end

  test "apply_lrc/2 rejects untimed text" do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room, %{lrc_text: nil, title: "If It Isn't Love"})
    assert {:error, :invalid_lrc} = Catalog.apply_lrc(song, "just words")

    assert {:ok, song} = Catalog.apply_lrc(song, "[00:01.00]When I first saw you")
    assert song.lrc_text =~ "When I first saw you"
  end

  test "get_song/1 returns not_found" do
    assert {:error, :not_found} = Catalog.get_song(-1)
  end
end
