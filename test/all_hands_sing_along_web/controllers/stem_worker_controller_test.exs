defmodule AllHandsSingAlongWeb.StemWorkerControllerTest do
  use AllHandsSingAlongWeb.ConnCase, async: false

  alias AllHandsSingAlong.Catalog
  alias AllHandsSingAlong.Catalog.StemSeparator
  alias AllHandsSingAlong.Fixtures

  @token "test-stem-worker-token"

  setup do
    original = Application.get_env(:all_hands_sing_along, :uploads_path)
    tmp = Path.join(System.tmp_dir!(), "ahsa-stems-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    Application.put_env(:all_hands_sing_along, :uploads_path, tmp)
    Application.put_env(:all_hands_sing_along, :stem_available, false)

    on_exit(fn ->
      File.rm_rf(tmp)

      if original do
        Application.put_env(:all_hands_sing_along, :uploads_path, original)
      else
        Application.delete_env(:all_hands_sing_along, :uploads_path)
      end
    end)

    %{tmp: tmp}
  end

  test "rejects requests without the worker token", %{conn: conn} do
    conn = post(conn, ~p"/internal/stems/claim")
    assert conn.status == 401
  end

  test "claim returns 204 when the queue is empty", %{conn: conn} do
    conn = conn |> auth() |> post(~p"/internal/stems/claim")
    assert conn.status == 204
  end

  test "claim, progress, and complete isolate a song from the Mac worker", %{conn: conn} do
    room = Fixtures.room_fixture()

    song =
      Fixtures.song_fixture(room, %{
        title: "Mac Mix",
        original_path: Catalog.fixture_path(),
        instrumental_path: nil
      })

    assert :ok = StemSeparator.enqueue(song.id)

    conn = conn |> auth() |> post(~p"/internal/stems/claim")
    assert json_response(conn, 200)["id"] == song.id
    assert json_response(conn, 200)["original_path"] == Catalog.fixture_path()

    wav = Path.join(:code.priv_dir(:all_hands_sing_along), "static/audio/fixture.wav")

    conn =
      build_conn()
      |> auth()
      |> post(~p"/internal/stems/#{song.id}/progress", %{"percent" => 40})

    assert json_response(conn, 200) == %{"ok" => true}

    {:ok, running} = Catalog.get_song(song.id)
    assert running.stem_status == :running
    assert running.stem_progress == 40

    upload = %Plug.Upload{
      path: wav,
      filename: "no_vocals.wav",
      content_type: "audio/wav"
    }

    conn =
      build_conn()
      |> auth()
      |> post(~p"/internal/stems/#{song.id}/complete", %{"instrumental" => upload})

    assert json_response(conn, 200) == %{"ok" => true}

    {:ok, done} = Catalog.get_song(song.id)
    assert done.stem_status == :ok
    assert Catalog.playable?(done)
  end

  defp auth(conn) do
    put_req_header(conn, "authorization", "Bearer #{@token}")
  end
end
