# test/all_hands_sing_along_web/live/room_live_test.exs
defmodule AllHandsSingAlongWeb.RoomLiveTest do
  use AllHandsSingAlongWeb.ConnCase

  alias AllHandsSingAlong.Fixtures
  alias AllHandsSingAlong.Queue

  test "redirects home without a display name", %{conn: conn} do
    room = Fixtures.room_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/rooms/#{room.code}")
  end

  test "host sees playback controls and guests do not", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, host_view, host_html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    assert host_html =~ "Host"
    assert has_element?(host_view, "#start-singer")
    assert has_element?(host_view, "#pause-song")
    assert has_element?(host_view, "#skip-song")
    assert has_element?(host_view, "#lyric-line")
    assert has_element?(host_view, "#disco-wash")

    guest_conn =
      conn
      |> recycle()
      |> guest_conn(room, "Sam")

    {:ok, guest_view, guest_html} = live(guest_conn, ~p"/rooms/#{room.code}")
    refute has_element?(guest_view, "#start-singer")
    refute has_element?(guest_view, "#pause-song")
    refute has_element?(guest_view, "#skip-song")
    assert guest_html =~ "Sam"
  end

  test "host play starts the fixture track", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    html = view |> element("#start-singer") |> render_click()
    assert html =~ "Demo Track"
  end

  test "host pause tells the player to stop", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    view |> element("#start-singer") |> render_click()
    assert_push_event(view, "player-sync", %{playing: true})

    view |> element("#pause-song") |> render_click()
    assert_push_event(view, "player-sync", %{playing: false})
  end

  test "host nudges lyrics by 0.1 seconds", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")

    assert has_element?(view, "#lyrics-later[phx-value-delta='-100']")
    assert has_element?(view, "#lyrics-earlier[phx-value-delta='100']")

    view |> element("#start-singer") |> render_click()
    view |> element("#lyrics-earlier") |> render_click()
    assert has_element?(view, "#lyrics-offset", "Lyrics 0.1s earlier")

    view |> element("#lyrics-later") |> render_click()
    assert has_element?(view, "#lyrics-offset", "Lyrics on time")
  end

  test "guest can search and pick lyrics after a failed lookup", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Can You Stand the Rain",
        artist: "New Edition",
        lrc_text: nil
      })

    entry =
      Fixtures.entry_fixture(room, %{
        singer_name: "Sam",
        song_title: "Can You Stand the Rain",
        song: song
      })

    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      cond do
        String.ends_with?(conn.request_path, "/search") ->
          Req.Test.json(conn, [
            %{
              "id" => 42,
              "trackName" => "Can You Stand the Rain",
              "artistName" => "New Edition",
              "albumName" => "Heart Break",
              "duration" => 287
            }
          ])

        String.ends_with?(conn.request_path, "/get/42") ->
          Req.Test.json(conn, %{"syncedLyrics" => "[00:12.00]On a perfect day"})

        true ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"message" => "Not Found"})
      end
    end)

    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")

    view
    |> form("#lyrics-search-#{entry.id}", %{
      title: "Can You Stand the Rain",
      artist: "New Edition"
    })
    |> render_submit()

    assert has_element?(view, "#pick-lyrics-#{entry.id}-42")

    view
    |> element("#pick-lyrics-#{entry.id}-42")
    |> render_click()

    {:ok, updated} = Queue.get_entry(entry.id)
    assert updated.song.lrc_text =~ "perfect day"
  end

  test "guest can paste timed lyrics onto a queued song", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "If It Isn't Love",
        artist: "New Edition",
        lrc_text: nil
      })

    entry =
      Fixtures.entry_fixture(room, %{
        singer_name: "Sam",
        song_title: "If It Isn't Love",
        song: song
      })

    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")

    view
    |> form("#lyrics-paste-#{entry.id}", %{lrc_text: "[00:01.00]When I first saw you"})
    |> render_submit()

    {:ok, updated} = Queue.get_entry(entry.id)
    assert updated.song.lrc_text =~ "When I first saw you"
  end

  test "guest cannot trigger host events", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")
    html = render_click(view, "play", %{})
    assert html =~ "Host only"
  end

  test "guest can add to the queue with title and artist", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")

    view
    |> form("#add-queue-form", %{song_title: "Levitating", song_artist: "Dua Lipa"})
    |> render_submit()

    [entry] = Queue.list_entries(room.id)
    refute AllHandsSingAlong.Catalog.has_lyrics?(entry.song)
    assert AllHandsSingAlong.Catalog.missing_audio?(entry.song)
    assert has_element?(view, "#no-lyrics-#{entry.id}")
    assert has_element?(view, "#no-audio-#{entry.id}")
    assert has_element?(view, "#start-attach-audio-#{entry.id}")
    assert has_element?(view, "#lyrics-search-#{entry.id}")
    assert render(view) =~ "Levitating — Dua Lipa"
    assert render(view) =~ "Preparing"
    assert entry.singer_name == "Sam"
    assert entry.status == :preparing
    assert entry.song.artist == "Dua Lipa"
  end

  test "guest cannot add a song without an artist", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")

    html =
      view
      |> form("#add-queue-form", %{song_title: "Levitating"})
      |> render_submit()

    assert html =~ "Artist is required"
    assert Queue.list_entries(room.id) == []
  end

  test "singer can upload audio after joining the queue without a file", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")

    view
    |> form("#add-queue-form", %{song_title: "Levitating", song_artist: "Dua Lipa"})
    |> render_submit()

    [entry] = Queue.list_entries(room.id)
    assert AllHandsSingAlong.Catalog.missing_audio?(entry.song)

    view |> element("#start-attach-audio-#{entry.id}") |> render_click()
    assert has_element?(view, "#attach-audio-#{entry.id}")

    wav = minimal_wav()

    audio =
      file_input(view, "#attach-audio-#{entry.id}", :late_audio, [
        %{name: "song.wav", content: wav, type: "audio/wav"}
      ])

    render_upload(audio, "song.wav")

    view
    |> form("#attach-audio-#{entry.id}")
    |> render_submit()

    {:ok, updated} = Queue.get_entry(entry.id)
    refute AllHandsSingAlong.Catalog.missing_audio?(updated.song)
    assert updated.song.original_path
    assert updated.song.stem_status == :ok
    refute has_element?(view, "#no-audio-#{entry.id}")
  end

  test "another guest cannot upload audio for someone else's queue song", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, sam, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")

    sam
    |> form("#add-queue-form", %{song_title: "Levitating", song_artist: "Dua Lipa"})
    |> render_submit()

    [entry] = Queue.list_entries(room.id)

    ada_conn =
      conn
      |> recycle()
      |> guest_conn(room, "Ada")

    {:ok, ada, _html} = live(ada_conn, ~p"/rooms/#{room.code}")
    refute has_element?(ada, "#start-attach-audio-#{entry.id}")
    assert has_element?(sam, "#start-attach-audio-#{entry.id}")
  end

  test "prepared songs show as ready without a host click", %{conn: conn} do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room, %{title: "Go", artist: "Sam Smith"})
    entry = Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Go", song: song})

    {:ok, view, html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    assert html =~ "Go — Sam Smith"
    assert html =~ "Ready"
    refute has_element?(view, "button", "Mark ready")
    {:ok, ready} = Queue.get_entry(entry.id)
    assert ready.status == :ready
    assert has_element?(view, "#move-up-#{entry.id}")
  end

  test "host sees stem progress separately from missing lyrics", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Vocal Mix",
        original_path: AllHandsSingAlong.Catalog.fixture_path(),
        instrumental_path: nil,
        lrc_text: nil,
        stem_status: :running,
        stem_progress: 42
      })

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Vocal Mix", song: song})

    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")

    assert has_element?(view, "#no-lyrics-#{entry.id}")
    assert has_element?(view, "#stem-progress-#{entry.id}")
    assert render(view) =~ "Removing vocals 42%"
    assert has_element?(view, "#cancel-stems-#{entry.id}")
    refute has_element?(view, "#retry-stems-#{entry.id}")
  end

  test "host can retry failed isolation and use the original", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Retry Mix",
        original_path: AllHandsSingAlong.Catalog.fixture_path(),
        instrumental_path: nil,
        stem_status: :failed,
        stem_error: "Vocal isolation isn’t installed on this machine"
      })

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Retry Mix", song: song})

    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    assert has_element?(view, "#stem-failed-#{entry.id}")
    assert render(view) =~ "Vocal isolation isn’t installed on this machine"
    assert has_element?(view, "#retry-stems-#{entry.id}")

    view |> element("#retry-stems-#{entry.id}") |> render_click()
    {:ok, updated} = Queue.get_entry(entry.id)
    assert updated.song.stem_status == :ok
    assert updated.status == :ready
  end

  test "host can play the original when isolation fails", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Keep Vocals",
        original_path: AllHandsSingAlong.Catalog.fixture_path(),
        instrumental_path: nil,
        stem_status: :failed
      })

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Keep Vocals", song: song})

    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    view |> element("#use-original-#{entry.id}") |> render_click()

    {:ok, updated} = Queue.get_entry(entry.id)
    assert updated.song.instrumental_path == song.original_path
    assert updated.status == :ready
  end

  test "host can reorder ready songs and play uses the new first", %{conn: conn} do
    room = Fixtures.room_fixture()
    song_one = Fixtures.song_fixture(room, %{title: "One"})
    song_two = Fixtures.song_fixture(room, %{title: "Two"})
    first = Fixtures.entry_fixture(room, %{singer_name: "Ada", song_title: "One", song: song_one})

    second =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Two", song: song_two})

    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")

    view
    |> element("#move-up-#{second.id}")
    |> render_click()

    view |> element("#start-singer") |> render_click()
    assert has_element?(view, "#now-playing-title", "Two — Test Artist")

    {:ok, first_after} = Queue.get_entry(first.id)
    {:ok, second_after} = Queue.get_entry(second.id)
    assert second_after.position < first_after.position
  end

  test "host can preview lyrics locally then start the singer mix", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Align Me",
        original_path: "/uploads/with-vocals.wav",
        instrumental_path: AllHandsSingAlong.Catalog.fixture_path()
      })

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Align Me", song: song})

    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    assert has_element?(view, "#tune-lyrics-#{entry.id}")
    assert has_element?(view, "#skip-song")

    view |> element("#tune-lyrics-#{entry.id}") |> render_click()
    assert has_element?(view, "#lyric-preview-card")
    assert has_element?(view, "#lyric-preview-title", "Align Me — Test Artist")
    assert has_element?(view, "#singer-muted-note")
    refute has_element?(view, "#playback-mode", "Singer (backing track)")
    assert has_element?(view, "#skip-song")
    assert has_element?(view, "#now-playing-title", "Nothing yet")

    view |> element("#preview-lyrics-earlier") |> render_click()
    assert has_element?(view, "#lyric-preview-offset", "Lyrics 0.1s earlier")

    {:ok, still} = Queue.get_entry(entry.id)
    assert still.status == :ready
    assert still.song.lyric_offset_ms == 100

    view |> element("#start-singer") |> render_click()
    refute has_element?(view, "#lyric-preview-card")
    assert has_element?(view, "#playback-mode", "Singer (backing track)")
    assert has_element?(view, "#skip-song")

    {:ok, singing} = Queue.get_entry(entry.id)
    assert singing.status == :now_singing
  end

  test "host preview does not change the guest now-playing track", %{conn: conn} do
    room = Fixtures.room_fixture()
    current = Fixtures.song_fixture(room, %{title: "Now"})
    nxt = Fixtures.song_fixture(room, %{title: "Next", original_path: "/uploads/next-orig.wav"})

    _current_entry =
      Fixtures.entry_fixture(room, %{singer_name: "Ada", song_title: "Now", song: current})

    next_entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Next", song: nxt})

    {:ok, host, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    host |> element("#start-singer") |> render_click()
    assert has_element?(host, "#now-playing-title", "Now — Test Artist")

    guest_conn =
      conn
      |> recycle()
      |> guest_conn(room, "Sam")

    {:ok, guest, _html} = live(guest_conn, ~p"/rooms/#{room.code}")
    assert has_element?(guest, "#now-playing-title", "Now — Test Artist")

    host |> element("#tune-lyrics-#{next_entry.id}") |> render_click()
    assert has_element?(host, "#lyric-preview-title", "Next — Test Artist")
    assert has_element?(host, "#now-playing-title", "Now — Test Artist")
    assert has_element?(guest, "#now-playing-title", "Now — Test Artist")
    refute has_element?(guest, "#lyric-preview-card")
    refute has_element?(guest, "#tune-lyrics-#{next_entry.id}")
  end

  test "guest cannot tune lyrics", %{conn: conn} do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room, %{title: "Guest Tune"})

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Guest Tune", song: song})

    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")
    refute has_element?(view, "#tune-lyrics-#{entry.id}")
    html = render_click(view, "tune_lyrics", %{"id" => to_string(entry.id)})
    assert html =~ "Host only"
  end

  test "host can search and pick replacement lyrics on a ready song", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "If It Isn't Love",
        artist: "New Edition",
        lrc_text: "[00:00.00]Wrong words",
        lyric_offset_ms: 700
      })

    entry =
      Fixtures.entry_fixture(room, %{
        singer_name: "Sam",
        song_title: "If It Isn't Love",
        song: song
      })

    Req.Test.stub(AllHandsSingAlong.Catalog.Lyrics, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      cond do
        String.ends_with?(conn.request_path, "/search") ->
          Req.Test.json(conn, [
            %{
              "id" => 99,
              "trackName" => "If It Isn't Love",
              "artistName" => "New Edition",
              "albumName" => "Heart Break",
              "duration" => 220
            }
          ])

        String.ends_with?(conn.request_path, "/get/99") ->
          Req.Test.json(conn, %{"syncedLyrics" => "[00:08.00]I think it's time"})

        true ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"message" => "Not Found"})
      end
    end)

    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    assert has_element?(view, "#change-lyrics-#{entry.id}")
    refute has_element?(view, "#lyrics-search-#{entry.id}")

    view |> element("#change-lyrics-#{entry.id}") |> render_click()
    assert has_element?(view, "#lyrics-search-#{entry.id}")

    view
    |> form("#lyrics-search-#{entry.id}", %{
      title: "If It Isnt Love",
      artist: "New Edition"
    })
    |> render_submit()

    {:ok, after_search} = Queue.get_entry(entry.id)
    assert after_search.song.title == "If It Isn't Love"
    assert after_search.song.lrc_text =~ "Wrong words"

    assert has_element?(view, "#pick-lyrics-#{entry.id}-99")
    view |> element("#pick-lyrics-#{entry.id}-99") |> render_click()

    {:ok, updated} = Queue.get_entry(entry.id)
    assert updated.song.lrc_text =~ "I think it's time"
    refute updated.song.lrc_text =~ "Wrong words"
    assert updated.song.lyric_offset_ms == 0
    assert updated.song.title == "If It Isn't Love"
  end

  test "guest cannot change lyrics that are already attached", %{conn: conn} do
    room = Fixtures.room_fixture()
    song = Fixtures.song_fixture(room, %{title: "Keep These"})

    entry =
      Fixtures.entry_fixture(room, %{singer_name: "Sam", song_title: "Keep These", song: song})

    {:ok, view, _html} = live(guest_conn(conn, room, "Sam"), ~p"/rooms/#{room.code}")
    refute has_element?(view, "#change-lyrics-#{entry.id}")
    html = render_click(view, "toggle_change_lyrics", %{"id" => to_string(entry.id)})
    assert html =~ "Host only"
  end

  test "room URL includes the join code", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    assert html =~ room.code
    assert render(view) =~ room.code
  end

  defp host_conn(conn, room) do
    init_test_session(conn, %{
      "display_name" => "Ada",
      "guest_id" => "host-ada",
      "host_tokens" => %{room.code => room.host_token}
    })
  end

  defp guest_conn(conn, _room, name) do
    init_test_session(conn, %{
      "display_name" => name,
      "guest_id" => "guest-#{name}"
    })
  end

  defp minimal_wav do
    "RIFF" <> :binary.copy(<<0>>, 64)
  end
end
