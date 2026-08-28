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
    assert has_element?(host_view, "button", "Play")

    guest_conn =
      conn
      |> recycle()
      |> guest_conn(room, "Sam")

    {:ok, guest_view, guest_html} = live(guest_conn, ~p"/rooms/#{room.code}")
    refute has_element?(guest_view, "button", "Play")
    refute has_element?(guest_view, "button", "Skip")
    assert guest_html =~ "Sam"
  end

  test "host play starts the fixture track", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    html = view |> element("button", "Play") |> render_click()
    assert html =~ "Demo Track"
  end

  test "host pause tells the player to stop", %{conn: conn} do
    room = Fixtures.room_fixture()
    {:ok, view, _html} = live(host_conn(conn, room), ~p"/rooms/#{room.code}")
    view |> element("button", "Play") |> render_click()
    assert_push_event(view, "player-sync", %{playing: true})

    view |> element("button", "Pause") |> render_click()
    assert_push_event(view, "player-sync", %{playing: false})
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
    assert has_element?(view, "#no-lyrics-#{entry.id}")
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

    view |> element("button", "Play") |> render_click()
    assert has_element?(view, "#now-playing-title", "Two — Test Artist")

    {:ok, first_after} = Queue.get_entry(first.id)
    {:ok, second_after} = Queue.get_entry(second.id)
    assert second_after.position < first_after.position
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
end
