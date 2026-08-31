# test/all_hands_sing_along/catalog/uploads/tigris_test.exs
defmodule AllHandsSingAlong.Catalog.Uploads.TigrisTest do
  use ExUnit.Case, async: false

  alias AllHandsSingAlong.Catalog.Uploads
  alias AllHandsSingAlong.Catalog.Uploads.Tigris

  setup do
    original = Application.get_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.Uploads)

    Application.put_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.Uploads,
      adapter: Tigris,
      endpoint: "https://s3.test",
      bucket: "karaoke",
      region: "auto",
      access_key_id: "AKIAFAKE",
      secret_access_key: "secret",
      req_options: [plug: {Req.Test, Tigris}]
    )

    on_exit(fn ->
      if original do
        Application.put_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.Uploads, original)
      else
        Application.delete_env(:all_hands_sing_along, AllHandsSingAlong.Catalog.Uploads)
      end
    end)

    :ok
  end

  test "public_url/1 signs a GET for upload keys" do
    url = Uploads.public_url("/uploads/track.mp3")
    assert url =~ "https://s3.test/karaoke/uploads/track.mp3"
    assert url =~ "X-Amz-Algorithm=AWS4-HMAC-SHA256"
    assert url =~ "X-Amz-Signature="
  end

  test "public_url/1 leaves fixture paths alone" do
    assert Uploads.public_url("/audio/fixture.wav") == "/audio/fixture.wav"
  end

  test "store_audio!/2 PUTs to Tigris" do
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(Tigris, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path =~ "/karaoke/uploads/"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    tmp = Path.join(System.tmp_dir!(), "tigris-#{System.unique_integer([:positive])}.mp3")
    File.write!(tmp, "bytes")
    on_exit(fn -> File.rm(tmp) end)

    assert {:ok, "/uploads/" <> name} = Uploads.store_audio!(tmp, "song.mp3")
    assert String.ends_with?(name, ".mp3")
  end

  test "serve/1 redirects to a signed URL" do
    assert {:redirect, url} = Uploads.serve("/uploads/track.mp3")
    assert url =~ "X-Amz-Signature="
  end

  test "serve/1 is not_found for unsafe names" do
    assert :not_found = Uploads.serve("/uploads/../secret.mp3")
  end
end
