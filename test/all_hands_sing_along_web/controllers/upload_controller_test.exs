defmodule AllHandsSingAlongWeb.UploadControllerTest do
  use AllHandsSingAlongWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:all_hands_sing_along, :uploads_path)
    tmp = Path.join(System.tmp_dir!(), "ahsa-uploads-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    Application.put_env(:all_hands_sing_along, :uploads_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if original do
        Application.put_env(:all_hands_sing_along, :uploads_path, original)
      else
        Application.delete_env(:all_hands_sing_along, :uploads_path)
      end
    end)

    %{tmp: tmp}
  end

  test "GET /uploads/:filename serves a file from the uploads dir", %{conn: conn, tmp: tmp} do
    File.write!(Path.join(tmp, "clip.wav"), "RIFF")

    conn = get(conn, ~p"/uploads/clip.wav")
    assert conn.status == 200
    assert conn.resp_body == "RIFF"
    assert get_resp_header(conn, "content-type") == ["audio/wav"]
  end

  test "GET /uploads/:filename is 404 when missing", %{conn: conn} do
    conn = get(conn, ~p"/uploads/missing.mp3")
    assert conn.status == 404
  end

  test "GET /uploads/:filename is 404 for names containing ..", %{conn: conn} do
    conn = get(conn, ~p"/uploads/foo..bar.wav")
    assert conn.status == 404
  end
end
